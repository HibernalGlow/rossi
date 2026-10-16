import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 只保存页码和可见条目的锚点，不保存已翻过的封面或插件数据。
class PluginListPosition {
  const PluginListPosition({
    required this.page,
    this.entryKey,
    this.offset = 0,
  });
  final int page;
  final String? entryKey;
  final double offset;

  Map<String, dynamic> toJson() => {
    'page': page,
    'entryKey': entryKey,
    'offset': offset,
  };

  static PluginListPosition? parse(dynamic value) {
    if (value is! Map) return null;
    final page = value['page'];
    final offset = value['offset'];
    if (page is! int || page < 1 || offset is! num || !offset.isFinite) {
      return null;
    }
    return PluginListPosition(
      page: page,
      entryKey: value['entryKey'] is String ? value['entryKey'] : null,
      offset: offset.toDouble(),
    );
  }
}

/// 插件、请求、筛选参数共同组成身份；Map 插入顺序不改变身份。
String pluginListPositionScope(
  String pluginId,
  String fnPath,
  Map<String, dynamic> core,
  Map<String, dynamic> extern,
) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return jsonEncode([pluginId, fnPath, canonical(core), canonical(extern)]);
}

class PluginListPositionStore {
  static final instance = PluginListPositionStore();
  static const _key = 'rossi.discover.listPositions.v1';
  Future<void> _pending = Future.value();

  Map<String, dynamic> _read(SharedPreferences prefs) {
    try {
      final data = jsonDecode(prefs.getString(_key) ?? '{}');
      return data is Map<String, dynamic> ? data : {};
    } on Object {
      return {};
    }
  }

  Future<PluginListPosition?> read(String scope) async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    return PluginListPosition.parse(_read(prefs)[scope]);
  }

  Future<void> save(String scope, PluginListPosition position) {
    final operation = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final data = _read(prefs)..remove(scope);
      data[scope] = position.toJson();
      while (data.length > 128) {
        data.remove(data.keys.first);
      }
      if (!await prefs.setString(_key, jsonEncode(data))) {
        throw StateError('保存发现浏览位置失败');
      }
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
