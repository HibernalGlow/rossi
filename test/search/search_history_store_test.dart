import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/search/model/plugin_search_history_store.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

class _MemorySettings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'local history persists complete syntax, trims, deduplicates and bounds',
    () async {
      final store = PreferencesSearchHistoryStore('test', limit: 3);
      await store.record('  artist:"name with spaces" -draft  ');
      await store.record('');
      await store.record('two');
      await store.record('three');
      await store.record('two');
      expect(await PreferencesSearchHistoryStore('test', limit: 3).load(), [
        'two',
        'three',
        'artist:"name with spaces" -draft',
      ]);
      await store.record('four');
      expect(await store.load(), ['four', 'two', 'three']);
    },
  );

  test('concurrent cards share a queue; clear is scoped and ordered', () async {
    final a = SearchHistoryStore.local('shelf-a');
    final b = SearchHistoryStore.local('shelf-b');
    expect(identical(a, SearchHistoryStore.local('shelf-a')), isTrue);
    await Future.wait([a.record('one'), a.record('two'), b.record('other')]);
    expect(await a.load(), ['two', 'one']);
    await Future.wait([a.clear(), a.record('after-clear')]);
    expect(await a.load(), ['after-clear']);
    expect(await b.load(), ['other']);
  });

  test(
    'plugin adapter reuses global history and preserves source ownership',
    () async {
      final cubit = _MemorySettings();
      addTearDown(cubit.close);
      final a = PluginSearchHistoryStore(cubit, 'plugin-a');
      final b = PluginSearchHistoryStore(cubit, 'plugin-b');
      final aggregate = PluginSearchHistoryStore(cubit, kAggregateSearchSource);
      await Future.wait([
        a.record('same'),
        b.record('same'),
        aggregate.record('all'),
      ]);
      expect(await a.load(), ['same']);
      expect(await aggregate.load(), ['all']);
      expect(cubit.state.searchHistory, hasLength(3));
      await a.clear();
      expect(await b.load(), ['same']);
      expect(await aggregate.load(), ['all']);
    },
  );

  test(
    'legacy unclassified history is preserved separately from plugin suggestions',
    () async {
      final cubit = _MemorySettings();
      addTearDown(cubit.close);
      cubit.updateState(
        (state) => state.copyWith(
          searchHistory: const [
            SearchHistoryEntry(keyword: 'old'),
            SearchHistoryEntry(keyword: 'other', source: 'plugin-b'),
          ],
        ),
      );
      final a = PluginSearchHistoryStore(cubit, 'plugin-a');
      expect(await a.load(), isEmpty);
      expect(await PluginSearchHistoryStore(cubit, '').load(), ['old']);
      await a.record('new');
      expect(cubit.state.searchHistory.last.source, 'plugin-b');
      expect(cubit.state.searchHistory[1].source, isEmpty);
      await a.clear();
      expect(await PluginSearchHistoryStore(cubit, '').load(), ['old']);
    },
  );
}
