import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';

/// 搜索历史的**存储形状**与两种视图。
///
/// 判的是「老库里那份纯 `List<String>` 还读得出来」这一条：它跑在
/// `UserSetting.globalSetting` 的读取路径上，读不出来就是开屏就崩，而不是
/// 「历史看着不对」。分组本身是纯函数，一并在这里钉住先后顺序。
void main() {
  group('旧数据兼容', () {
    test('老版本那份纯 List<String> 还能读，归属记成未分类', () {
      final state = GlobalSettingState.fromJson(const <String, dynamic>{
        'searchHistory': ['よろず', 'artist:"puk"'],
      });

      expect(state.searchHistory, const [
        SearchHistoryEntry(keyword: 'よろず'),
        SearchHistoryEntry(keyword: 'artist:"puk"'),
      ]);
      expect(
        state.searchHistory.every((entry) => entry.source.isEmpty),
        isTrue,
      );
    });

    test('脏数据不炸：null / 不是列表 / 空词 / 数字', () {
      expect(searchHistoryFromJson(null), isEmpty);
      expect(searchHistoryFromJson('nope'), isEmpty);
      expect(
        searchHistoryFromJson(const [
          '',
          7,
          {'keyword': 'ok'},
        ]).map((entry) => entry.keyword),
        ['ok'],
      );
    });

    test('带归属的能原样往返（设置导出与云端同步走的就是这条路）', () {
      final original = const [
        SearchHistoryEntry(keyword: 'PUK', source: kAggregateSearchSource),
        SearchHistoryEntry(
          keyword: 'PUK',
          source: 'a16835e9-d405-4e01-8019-08e30ba6cde2',
        ),
      ];
      final state = const GlobalSettingState().copyWith(
        searchHistory: original,
      );

      expect(
        GlobalSettingState.fromJson(state.toJson()).searchHistory,
        original,
      );
    });
  });

  group('分组开关', () {
    test('出厂是关的：保住改造前那条混排时间线', () {
      expect(const GlobalSettingState().searchHistoryGroupBySource, isFalse);
      // 老数据里没这个键 ⇒ 同样落在默认值上，升级后不该自己变成分组视图。
      expect(
        GlobalSettingState.fromJson(
          const <String, dynamic>{},
        ).searchHistoryGroupBySource,
        isFalse,
      );
    });
  });

  group('两种视图', () {
    test('同一个词在两个插件下各算一条，删一条不误伤另一条', () {
      const inA = SearchHistoryEntry(keyword: '馬轰', source: 'plugin-a');
      const inB = SearchHistoryEntry(keyword: '馬轰', source: 'plugin-b');

      final afterDelete = List.of([inA, inB])
        ..removeWhere((entry) => entry == inB);

      expect(afterDelete, [inA]);
    });

    test('分桶后：桶的先后 = 该插件最近一次搜索的先后', () {
      final groups = groupSearchHistoryBySource(const [
        SearchHistoryEntry(keyword: 'x', source: 'plugin-b'),
        SearchHistoryEntry(keyword: 'y', source: 'plugin-a'),
        SearchHistoryEntry(keyword: 'z', source: 'plugin-b'),
      ]);

      expect(groups.map((group) => group.source), ['plugin-b', 'plugin-a']);
      expect(groups.first.keywords, ['x', 'z']);
    });

    test('聚合成一条时间线：同一个词只留最近那条，但留的是记录不是词', () {
      // 留记录是为了长按删除时还知道该删哪个来源 —— 只带词会把另一个插件下
      // 的同名记录一起删掉。
      final distinct = distinctSearchHistoryByKeyword(const [
        SearchHistoryEntry(keyword: 'cos', source: 'plugin-b'),
        SearchHistoryEntry(keyword: 'cos', source: 'plugin-a'),
        SearchHistoryEntry(keyword: 'stirrup', source: 'plugin-a'),
      ]);

      expect(distinct, const [
        SearchHistoryEntry(keyword: 'cos', source: 'plugin-b'),
        SearchHistoryEntry(keyword: 'stirrup', source: 'plugin-a'),
      ]);
    });
  });
}
