import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// 搜索框只适配存储；图源、文件管理器继续使用各自已有的历史来源。
abstract class SearchHistoryStore {
  String get scope;
  Future<List<String>> load();
  Future<void> record(String query);
  Future<void> clear();

  static final Map<String, SearchHistoryStore> _localStores = {};

  /// 本地筛选没有上游历史模型，复用项目现有的 SharedPreferences。
  static SearchHistoryStore local(String scope) => _localStores.putIfAbsent(
    scope,
    () => PreferencesSearchHistoryStore(scope),
  );
}

class PreferencesSearchHistoryStore extends SearchHistoryStore {
  PreferencesSearchHistoryStore(this.scope, {this.limit = 50});

  @override
  final String scope;
  final int limit;
  String get _key => 'rossi.search_history.v1.$scope';
  Future<void> _pending = Future.value();

  @override
  Future<List<String>> load() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[]).take(limit).toList();
  }

  // 同一用途的多个卡片共用写队列，避免同时读旧列表后互相覆盖。
  Future<void> _write(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> record(String query) {
    final keyword = query.trim();
    if (keyword.isEmpty) return Future.value();
    return _write(() async {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_key) ?? <String>[];
      history
        ..removeWhere((entry) => entry == keyword)
        ..insert(0, keyword);
      await prefs.setStringList(_key, history.take(limit).toList());
    });
  }

  @override
  Future<void> clear() => _write(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  });
}

/// 用回调适配既有状态/数据库，不复制业务存储。
class CallbackSearchHistoryStore extends SearchHistoryStore {
  CallbackSearchHistoryStore({
    required this.scope,
    required this.read,
    required this.write,
    required this.reset,
  });

  @override
  final String scope;
  final FutureOr<List<String>> Function() read;
  final FutureOr<void> Function(String query) write;
  final FutureOr<void> Function() reset;

  @override
  Future<List<String>> load() async => read();
  @override
  Future<void> record(String query) async {
    if (query.trim().isNotEmpty) await write(query.trim());
  }

  @override
  Future<void> clear() async => reset();
}
