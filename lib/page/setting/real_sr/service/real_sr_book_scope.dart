import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/util/path_util.dart';

/// 书级超分开关：**这本书自己的选择**，压在全局默认（`realsr_auto_upscale`）之上。
///
/// 为什么要有这一层：全局那条是「所有书的默认」，而「这本书我不想超分」是另一件事
/// —— 在阅读器里关掉一本，不该顺手把别的书一起关掉（反过来也一样）。
///
/// 口径：
/// - 键：本地书 = 规范化路径（与阅读历史同源，见 [normalizeLocalComicPath]）；
///   在线书 = `插件id:漫画id`（与下载记录的 uniqueKey 同形）；
/// - **没有覆盖 = 跟随全局**；拨回与全局同值时**清掉覆盖** —— 否则一条旧覆盖会把
///   某本书永久钉在旧值上，之后改全局再也影响不到它，看起来就像「设置没生效」；
/// - 条目上限 [maxEntries]，超出按最后写入时间淘汰最旧的（同视频进度那套口径，
///   防「读过几千本之后偏好文件无限长」）；
/// - 存 SharedPreferences，不进 ObjectBox —— 与 RealSr 其余设置同源。
class RealSrBookScope {
  RealSrBookScope._();

  static const String prefsKey = 'realsr_book_overrides_json';

  /// 覆盖条数上限。一本书一条，200 条足够覆盖「最近在读」，更久以前的书回到
  /// 全局默认本来也更合理。
  static const int maxEntries = 200;

  /// 书级开关（含全局那条）变化时的通知。
  ///
  /// 合成一个通知源：消费方（呈现器 / 芯片 / 面板）只关心「这本书最终该不该超分」
  /// 这一个问题的答案变没变，不该各自去拼两个 notifier。
  static final _ScopeNotifier _changes = _makeNotifier();
  static ChangeNotifier get changes => _changes;

  static _ScopeNotifier _makeNotifier() {
    final notifier = _ScopeNotifier();
    // 全局那条变了也要通知：没有覆盖的书要当场跟随（有覆盖的书重算后值不变，
    // 消费方自己会短路）。
    RealSrSettings.autoUpscaleChanges.addListener(notifier.notify);
    return notifier;
  }

  /// 当前阅读会话里那本**本地书**的路径（已归一化）；不在阅读器里时为 null。
  ///
  /// 为什么是静态字段而不是让呈现器去问会话：呈现器在**构造里**就要读这本书的
  /// 初值，而那时它自己还没推过任何一页；能回答「现在读的是哪本书」的只有读会话，
  /// 而读会话又反过来依赖呈现器 —— 静态字段把这条环解开。
  static String? _activeLocalBook;

  static String? get activeLocalBook => _activeLocalBook;

  static void setActiveLocalBook(String? path) {
    final normalized = path == null || path.trim().isEmpty
        ? null
        : normalizeLocalComicPath(path);
    if (_activeLocalBook == normalized) return;
    _activeLocalBook = normalized;
    _changes.notify();
  }

  /// 书身份：本地路径优先（它一定是磁盘身份），否则拼 `插件id:漫画id`。
  ///
  /// 两样都拿不到就返回 null —— 调用方按「跟随全局」处理，而不是编一个键出来。
  static String? keyFor({String? localPath, String? from, String? comicId}) {
    if (localPath != null && localPath.trim().isNotEmpty) {
      return normalizeLocalComicPath(localPath);
    }
    final id = comicId?.trim() ?? '';
    if (id.isEmpty) return null;
    final plugin = from?.trim() ?? '';
    return plugin.isEmpty ? id : '$plugin:$id';
  }

  /// 覆盖表的内存快照（读多写少：图片下载的每个文件都要问一次）。
  ///
  /// 缓存键是**原始 JSON 串**而不是「写过没写过」的布尔：任何来路的写入（本类之外
  /// 的同步/测试直接改 prefs）都会让串变掉，缓存自己就失效了 —— 不用靠人记得清。
  static String? _cachedRaw;
  static Map<String, bool>? _cachedOverrides;

  static Map<String, bool> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, bool>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, bool>{};
    final result = <String, bool>{};
    decoded.forEach((Object? key, Object? value) {
      if (key is! String || value is! Map) return;
      final Object? enabled = value['e'];
      if (enabled is bool) result[key] = enabled;
    });
    return result;
  }

  static String _encode(Map<String, bool> overrides, Map<String, int> stamps) {
    return jsonEncode(<String, Object?>{
      for (final MapEntry<String, bool> entry in overrides.entries)
        entry.key: <String, Object?>{
          'e': entry.value,
          't': stamps[entry.key] ?? 0,
        },
    });
  }

  static Future<Map<String, bool>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    final cached = _cachedOverrides;
    if (cached != null && raw == _cachedRaw) return cached;
    final loaded = _decode(raw);
    _cachedRaw = raw;
    _cachedOverrides = loaded;
    return loaded;
  }

  static Map<String, int> _stampsOf(String? raw) {
    final result = <String, int>{};
    if (raw == null || raw.isEmpty) return result;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return result;
    decoded.forEach((Object? key, Object? value) {
      if (key is! String || value is! Map) return;
      final Object? stamp = value['t'];
      if (stamp is int) result[key] = stamp;
    });
    return result;
  }

  /// 读取某本书的覆盖：`null` = 没有覆盖（跟随全局）。
  static Future<bool?> overrideFor(String? bookKey) async {
    if (bookKey == null) return null;
    return (await _loadAll())[bookKey];
  }

  /// 这本书最终该不该超分：有覆盖用覆盖，否则用全局默认。
  static Future<bool> enabledFor(String? bookKey) async {
    final bool? override = await overrideFor(bookKey);
    if (override != null) return override;
    return RealSrSettings.loadAutoUpscale();
  }

  /// 当前阅读会话里那本书最终该不该超分（呈现器与芯片用这个）。
  static Future<bool> enabledForActiveLocalBook() => enabledFor(_activeLocalBook);

  /// 阅读器里拨「本书」开关用的一步到位入口（当前会话那本本地书）。
  static Future<void> setForActiveLocalBook(bool value) =>
      save(_activeLocalBook, value);

  /// 写某本书的覆盖。与全局同值就清掉（回到「跟随全局」）。
  static Future<void> save(String? bookKey, bool value) async {
    if (bookKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    final overrides = _decode(raw);
    final stamps = _stampsOf(raw);
    final bool global = await RealSrSettings.loadAutoUpscale();
    if (value == global) {
      overrides.remove(bookKey);
      stamps.remove(bookKey);
    } else {
      overrides[bookKey] = value;
      stamps[bookKey] = DateTime.now().millisecondsSinceEpoch;
    }
    while (overrides.length > maxEntries) {
      String? oldestKey;
      int oldestStamp = 1 << 62;
      for (final String key in overrides.keys) {
        final int stamp = stamps[key] ?? 0;
        if (stamp < oldestStamp) {
          oldestStamp = stamp;
          oldestKey = key;
        }
      }
      if (oldestKey == null) break;
      overrides.remove(oldestKey);
      stamps.remove(oldestKey);
    }
    final encoded = _encode(overrides, stamps);
    await prefs.setString(prefsKey, encoded);
    _cachedRaw = encoded;
    _cachedOverrides = overrides;
    _changes.notify();
  }
}

class _ScopeNotifier extends ChangeNotifier {
  /// `notifyListeners` 在 ChangeNotifier 里是 protected；服务内部（含它注册到
  /// 全局那条 notifier 上的回调）需要一个公开口子，外部仍然只能 listen。
  void notify() => notifyListeners();
}
