import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/common/setting_entry.dart';
import 'package:zephyr/page/setting/common/setting_entry_list.dart';

/// 定位机制本身的下标，不是某份编号表的下标：
/// `SettingEntryList` 拿这份 children 去渲染，也拿同一份去算 index。
Widget _row(int i) {
  return settingEntry(
    'row_$i',
    SizedBox(
      height: i.isEven ? 60 : 120,
      child: ColoredBox(color: const Color(0xFF223344), child: Text('R$i')),
    ),
  );
}

List<Widget> _rows(int count) => [
  const Padding(padding: EdgeInsets.only(top: 8), child: Text('标题')),
  for (var i = 0; i < count; i++) _row(i),
  const SizedBox(height: 32),
];

Widget _host(List<Widget> children) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(400, 600)),
    child: MaterialApp(
      home: Scaffold(body: SettingEntryList(children: children)),
    ),
  );
}

void main() {
  tearDown(() => settingFocusRequest.value = null);

  group('id 解析', () {
    test('下标数的是整份列表，含未登记的装饰行', () {
      final children = _rows(6);
      // children[0] 是标题，所以 row_0 落在下标 1，不是 0。
      expect(indexOfSettingEntry(children, 'row_0'), 1);
      expect(indexOfSettingEntry(children, 'row_5'), 6);
      expect(indexOfSettingEntry(children, 'row_99'), -1);
    });

    test('裸 ValueKey 不算登记过的设置项', () {
      // 本仓已有把 ValueKey 当 widget 身份用的写法，只有 SettingEntryKey 可定位。
      final children = <Widget>[
        const Text('plain', key: ValueKey<String>('row_0')),
      ];
      expect(indexOfSettingEntry(children, 'row_0'), -1);
      expect(settingEntryIds(children), isEmpty);
    });

    test('阳性对照：重复 id 会被查出来', () {
      final children = <Widget>[_row(1), _row(1)];
      final ids = settingEntryIds(children);
      expect(ids.toSet().length, isNot(ids.length));
    });
  });

  group('按 id 滚进视口', () {
    testWidgets('远处的行请求后可见', (tester) async {
      await tester.pumpWidget(_host(_rows(40)));
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(ListView));
      final target = find.byKey(const SettingEntryKey('row_35'));
      // 懒加载的 SliverList 根本不会构建视口+cacheExtent 之外的行，
      // 所以「有 GlobalKey 就能 ensureVisible」这条路在这一格上是走不通的；
      // 也正因此才需要按 index 定位。
      expect(target, findsNothing, reason: '没请求前，远处那行压根不该被构建');

      settingFocusRequest.value = 'row_35';
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(target, findsOneWidget, reason: '滚过去之后它必须真的被构建出来');
      final rect = tester.getRect(target);
      expect(rect.overlaps(viewport), isTrue, reason: '构建出来还不够，要真的在视口里');
      expect(settingFocusRequest.value, isNull, reason: '认领完要清空');
    });

    testWidgets('不属于本页的 id 不认领、也不动', (tester) async {
      await tester.pumpWidget(_host(_rows(40)));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const SettingEntryKey('row_1')));

      settingFocusRequest.value = 'other_page.someRow';
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(settingFocusRequest.value, 'other_page.someRow', reason: '别人的请求要留着');
      expect(tester.getRect(find.byKey(const SettingEntryKey('row_1'))), before);
    });
  });
}
