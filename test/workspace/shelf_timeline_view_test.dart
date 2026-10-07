// 时间线视图的判据：分段数、行数、段头文案、以及**行还是不是共用那一套**。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/shelf_timeline_view_test.dart
//
// 分组算得对不对由 `shelf_timeline_check.dart`（纯 Dart，四个时区跑过）负责；
// 这里只管只有真树才验得到的三件事：
//
//   1. **段头与行的数量对得上** —— 摊平成一维 cell 列表之后，「一天一段」
//      这件事很容易在拼接处多数或少数一格，而界面看起来完全正常；
//   2. **行仍然走 `LibraryEntrySurface`** —— 时间线要是自己画一行，
//      封面/标题/副标题/行尾动作立刻会与列表档长歪（三家共用一份行契约的口径）；
//   3. **右键壳子仍然套在每一行上** —— 时间线里漏掉 `wrapRow`，
//      用户就没法在时间线上取消收藏 / 移除记录，而这不会报错。
//
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_surface.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_timeline_view.dart';

/// 只用来标记「这一行被 `wrapRow` 套过壳」的探针。
///
/// 写在测试里而不是产品代码里：真实世界用的是
/// `ShelfEntryContextMenuRegion`，那一份要 ObjectBox 才搭得起来，
/// 而这里要验的只是「壳子套没套、套在哪」。
class _Probe extends StatelessWidget {
  const _Probe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

LibraryEntry _entry(String key, String title) {
  return LibraryEntry(key: key, title: title, subtitle: '副标题');
}

Widget _harness(ShelfTimelineView view) {
  return MaterialApp(home: Scaffold(body: SizedBox(width: 420, child: view)));
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  final todayLate = DateTime(now.year, now.month, now.day, 21);
  final yesterday = today.subtract(const Duration(days: 1));
  final longAgo = today.subtract(const Duration(days: 400));

  testWidgets('三段：今天两条、昨天一条、400 天前一条', (tester) async {
    final entries = [
      _entry('a', '今天的第一本'),
      _entry('b', '今天的第二本'),
      _entry('c', '昨天的那本'),
      _entry('d', '四百天前那本'),
    ];
    final times = {
      'a': today,
      'b': todayLate,
      'c': yesterday,
      'd': longAgo,
    };

    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: entries,
          timeOf: (entry) => times[entry.key]!,
          onTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 行：四条，一条不多一条不少。
    expect(find.byType(LibraryEntrySurface), findsNWidgets(4));
    // 段头：今天 / 昨天 / 「M年M月M日」或「M月M日」—— 三组。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'^\d{1,2}月\d{1,2}日$|^\d{4}年\d{1,2}月\d{1,2}日$')
                .hasMatch(widget.data!),
      ),
      findsOneWidget,
      reason: '400 天前那一组要有自己的日期段头',
    );
  });

  testWidgets('行内容仍然由共用的行契约渲染，标题与副标题都画得出来', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: [_entry('a', '时间线里的标题')],
          timeOf: (_) => today,
          onTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('时间线里的标题'), findsOneWidget);
    expect(find.text('副标题'), findsOneWidget);
    // 左轨那块 CustomPaint 必须在：它是「这一条挂在某一天的节点上」的唯一视觉线索。
    expect(
      find.byWidgetPredicate((widget) => widget is CustomPaint),
      findsWidgets,
    );
  });

  testWidgets('wrapRow 给时间线每一行都套上壳子', (tester) async {
    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: [_entry('a', '一本'), _entry('b', '两本')],
          timeOf: (_) => today,
          onTap: (_) {},
          wrapRow: (context, entry, row) =>
              _Probe(key: ValueKey(entry.key), child: row),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(_Probe), findsNWidgets(2));
    // 壳子必须**包住**行，而不是排在行旁边 —— 否则右键手势吃不到条目。
    expect(
      find.descendant(
        of: find.byType(_Probe),
        matching: find.byType(LibraryEntrySurface),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('点一行交出的是那一条目', (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: [_entry('a', '第一本'), _entry('b', '第二本')],
          timeOf: (_) => today,
          onTap: (entry) => seen.add(entry.key),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二本'));
    await tester.pumpAndSettle();
    expect(seen, <String>['b']);
  });

  testWidgets('enabled=false 时行不接点击', (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: [_entry('a', '第一本')],
          timeOf: (_) => today,
          enabled: false,
          onTap: (entry) => seen.add(entry.key),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一本'));
    await tester.pumpAndSettle();
    expect(seen, isEmpty);
  });

  testWidgets('空列表：卡片内给固定高度，standalone 撑满', (tester) async {
    await tester.pumpWidget(
      _harness(
        ShelfTimelineView(
          entries: const [],
          timeOf: (_) => today,
          onTap: (_) {},
          emptyText: '暂无阅读历史',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无阅读历史'), findsOneWidget);
    expect(find.byType(LibraryEntrySurface), findsNothing);
    // 阳性对照：条目非空时同一把尺子量得到行 —— 见上面的用例，
    // 所以这里的 findsNothing 不是「压根没画」。
  });
}
