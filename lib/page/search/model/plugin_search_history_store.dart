import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

/// 直接读取上游搜索历史字段，保持插件/聚合搜索的归属和旧数据兼容。
class PluginSearchHistoryStore extends SearchHistoryStore {
  PluginSearchHistoryStore(this.cubit, this.source);

  final GlobalSettingCubit cubit;
  final String source;

  @override
  String get scope => 'plugin:$source';

  @override
  Future<List<String>> load() async => cubit.state.searchHistory
      .where((entry) => entry.source == source)
      .map((entry) => entry.keyword)
      .toSet()
      .toList();

  @override
  Future<void> record(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty || cubit.isClosed) return;
    final entry = SearchHistoryEntry(keyword: keyword, source: source);
    cubit.updateState((current) {
      final history = current.searchHistory.toList()
        ..remove(entry)
        ..insert(0, entry);
      return current.copyWith(searchHistory: history.take(300).toList());
    });
  }

  @override
  Future<void> clear() async {
    if (cubit.isClosed) return;
    cubit.updateState(
      (current) => current.copyWith(
        searchHistory: current.searchHistory
            .where((entry) => entry.source != source)
            .toList(),
      ),
    );
  }
}
