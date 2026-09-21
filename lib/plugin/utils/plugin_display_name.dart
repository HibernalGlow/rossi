/// 插件 id ⇒ 界面上认得出的名字。
///
/// 为什么要单独一份：书签与历史里存的 `source` 就是插件 uuid，而 uuid 长这样
/// `A16835E9-D405-4E01-8019-08E30BA6CDE2` —— 大写之后摆在行上等于没显示。
/// 发现页自己解析过一遍（`discover_tabs.dart` 的 `_pluginDisplay`），这里补的是
/// 「列表按行查」那一口：一次取全表，别让每行去问一遍数据库。
library;

import 'dart:async';

import 'package:zephyr/main.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/utils/plugin_update_channel_utils.dart';
import 'package:zephyr/util/json/json_value.dart';

Map<String, String>? _cached;
StreamSubscription<Map<String, PluginRuntimeState>>? _invalidator;

/// 全表的「插件 uuid（小写）⇒ 显示名」。只包含解析得到名字的插件。
///
/// 键统一小写：uuid 是 `Uuid.v4()` 的形态，而记录里的 `source` 不保证同一写法，
/// 查的时候两边都走 [shelfPluginName]。
///
/// 结果按注册表的变更事件失效重算：装 / 删 / 启用 / 首次 `getInfo` 都会发一次
/// （`updateLoadResult` 在 `_fetchPluginInfo` 里就调）。不缓存的话，列表每次重建
/// 都要把每个插件的 `getInfoJson` 重解一遍，而代价会由「用户在搜索框里敲一个字」
/// 来付。
///
/// 两个来源，后者盖前者：
///
/// 1. ObjectBox 里持久化的 `getInfoJson` —— 装插件时就写进去了，本次会话没跑过
///    `getInfo` 也拿得到名字（已删除的插件也算，历史行还得认得它）；
/// 2. 注册表的内存缓存 —— 插件刚更新过，名字可能已经和落盘那份不同。
Map<String, String> pluginDisplayNames() {
  _invalidator ??= PluginRegistryService.I.stream.listen((_) => _cached = null);
  return _cached ??= _readPluginDisplayNames();
}

Map<String, String> _readPluginDisplayNames() {
  final names = <String, String>{};
  void put(String uuid, String? name) {
    final key = uuid.trim().toLowerCase();
    if (key.isEmpty || name == null) return;
    names[key] = name;
  }

  for (final info in objectbox.pluginInfoBox.getAll()) {
    put(info.uuid, pluginNameFromInfo(parseGetInfoJson(info.getInfoJson)));
  }
  final registry = PluginRegistryService.I;
  for (final uuid in registry.snapshot.keys) {
    put(uuid, pluginNameFromInfo(registry.getCachedPluginInfo(uuid)));
  }
  return names;
}

/// getInfo 结果里的名字；没填或空白返回 null（调用方据此退回 id）。
///
/// 插件常常不填 `name` 只在 `creator.name` 里署名，与发现页同一口径；另有
/// 一批把整包内容挂在 `data` 下面（`readNpmNameFromInfo` 认的就是这个形状），
/// 所以两种都要看。
String? pluginNameFromInfo(Map<String, dynamic>? info) {
  if (info == null) return null;
  final direct = _nameOf(info);
  if (direct != null) return direct;
  final data = asJsonMap(info['data']);
  return data.isEmpty ? null : _nameOf(data);
}

String? _nameOf(Map info) {
  final name = _text(info['name']);
  if (name != null) return name;
  return _text(asJsonMap(info['creator'])['name']);
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
