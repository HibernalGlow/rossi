import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:zephyr/util/text/tag_text.dart';

/// 宿主内置的 EhTagTranslation 字典：英文 tag ↔ 中文译名 双向查表。
///
/// 数据来自 `script/build_tag_translation.py`（与 e-hentai 插件的翻译同源，
/// 插件显示什么译名，这里就能反推回什么原词）。存在的意义是让「跨站写法」
/// 不再全靠用户登记别名：收藏 `footjob`，EH 详情页那颗被插件翻成「足交」的
/// 胶囊也命中；收藏中文名，别的站给的英文原词也命中。
///
/// 展开只发生在**收藏侧**（`FavoriteTagMatcher.buildAliasIndex` 建表时），
///  incoming 的匹配路径保持纯查表：收藏列表几十个词，翻一遍字典是常数开销；
/// 反过来去展开每颗胶囊才是 O(字典)。
class TagTranslation {
  TagTranslation._();

  /// 归一化英文 tag → 归一化中文译名列表。
  static Map<String, List<String>> _toChinese = const {};

  /// 归一化中文译名 → 归一化英文 tag 列表。
  static Map<String, List<String>> _toEnglish = const {};

  static Future<void>? _loading;

  /// 字典是否已可用（未就绪时展开返回空，行为退回「只有登记别名」）。
  static bool get isReady => _toChinese.isNotEmpty;

  /// 应用启动时调用一次；重复调用无副作用。加载失败静默（不阻塞任何 UI）。
  static Future<void> ensureLoaded() {
    return _loading ??= _load().catchError((Object e) {
      debugPrint('TagTranslation 加载失败（自动别名不可用）: $e');
    });
  }

  static Future<void> _load() async {
    final data = await rootBundle.load(
      'asset/tag_translation/etht.json.gz',
    );
    final decoded = jsonDecode(
      utf8.decode(gzip.decode(data.buffer.asUint8List())),
    ) as Map<String, dynamic>;
    final toChinese = <String, List<String>>{};
    final toEnglish = <String, List<String>>{};
    for (final ns in decoded.entries) {
      final tags = ns.value;
      if (tags is! Map) continue;
      for (final tag in tags.entries) {
        final enKey = TagText.normalize(tag.key.toString());
        final zhKey = TagText.normalize(tag.value.toString());
        if (enKey.isEmpty || zhKey.isEmpty) continue;
        toChinese.putIfAbsent(enKey, () => []).add(zhKey);
        toEnglish.putIfAbsent(zhKey, () => []).add(enKey);
      }
    }
    _toChinese = toChinese;
    _toEnglish = toEnglish;
  }

  /// [normalizedKey]（已归一化）的**其它**归一化写法：英文给译名、中文给原词。
  /// 查不到或字典未就绪 ⇒ 空。
  static Iterable<String> expansionsNormalized(String normalizedKey) {
    if (normalizedKey.isEmpty) return const [];
    final zh = _toChinese[normalizedKey];
    if (zh != null) return zh;
    return _toEnglish[normalizedKey] ?? const [];
  }

  /// 测试注入：直接装一张双向表，绕开 rootBundle。
  @visibleForTesting
  static void installForTest({
    Map<String, List<String>> toChinese = const {},
    Map<String, List<String>> toEnglish = const {},
  }) {
    _toChinese = toChinese;
    _toEnglish = toEnglish;
    _loading = Future.value();
  }

  @visibleForTesting
  static void resetForTest() {
    _toChinese = const {};
    _toEnglish = const {};
    _loading = null;
  }
}
