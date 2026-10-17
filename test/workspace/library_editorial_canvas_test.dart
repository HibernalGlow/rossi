import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_list.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/i18n/strings.g.dart';

List<LibraryEntry> entries(int count) => List.generate(
  count,
  (i) => LibraryEntry(
    key: '$i',
    title: '作品 $i',
    subtitle: '第 $i 章',
    section: i < 10 ? '在读' : '未读',
    itemCount: i == 4 ? 1000000 : i + 1,
    media:
        (_, {required width, required height, required radius, required fit}) =>
            Container(
              width: width,
              height: height,
              color: Colors.teal.shade200,
            ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('面积变化有界、分区保持输入顺序、不会用后项回填前面的空位', () {
    final data = entries(40);
    for (var columns = 1; columns < 9; columns++) {
      final rows = libraryCanvasRows(
        entries: data,
        columns: columns,
        presentation: const LibraryPresentation(
          sections: true,
          weight: LibraryWeight.count,
        ),
      );
      expect(
        rows.expand((r) => r.indices),
        orderedEquals(List.generate(40, (i) => i)),
      );
      for (final row in rows) {
        expect(row.spans.fold(0, (a, b) => a + b), lessThanOrEqualTo(columns));
        expect(row.spans.every((s) => s >= 1 && s <= 2), isTrue);
        expect(row.indices.map((i) => data[i].section).toSet().length, 1);
      }
    }
  });

  testWidgets('滚到中间原位展开，前方卡片保持位置，关闭恢复', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rossi.library.presentation.test': jsonEncode(
        const LibraryPresentation(hero: false, asymmetric: false).toJson(),
      ),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: LibraryEditorialCanvas(
              scope: 'test',
              entries: entries(50),
              standalone: true,
              onTap: (_) {},
              legacyBuilder: (_) => const Text('传统视图'),
              detailBuilder: (_, entry, close) => SizedBox(
                height: 280,
                child: Column(
                  children: [
                    Text('详情 ${entry.key}'),
                    TextButton(onPressed: close, child: const Text('关闭详情')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    final scrollPosition = tester.state<ScrollableState>(scroll).position;
    scrollPosition.jumpTo(1500);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('作品 20')).dy;
    final position = tester.state<ScrollableState>(scroll).position;
    final offset = position.pixels;
    await tester.tap(find.text('作品 20'));
    await tester.pumpAndSettle();
    expect(find.text('详情 20'), findsOneWidget);
    expect(position.pixels, offset);
    expect(tester.getTopLeft(find.text('作品 20')).dy, closeTo(before, .1));
    final canvas = tester.state<LibraryEditorialCanvasState>(
      find.byType(LibraryEditorialCanvas),
    );
    expect(canvas.closeDetails(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('详情 20'), findsNothing);
    expect(position.pixels, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多本独立展开，打开下方作品仍保留上方详情与新封面位置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rossi.library.presentation.switch': jsonEncode(
        const LibraryPresentation(hero: false, asymmetric: false).toJson(),
      ),
    });
    final data = entries(50);
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: LibraryEditorialCanvas(
              key: key,
              scope: 'switch',
              entries: data,
              standalone: true,
              onTap: (_) {},
              legacyBuilder: (_) => const SizedBox(),
              detailBuilder: (_, entry, close) =>
                  SizedBox(height: 100, child: Text('详情 ${entry.key}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.toggleDetails(data.first);
    await tester.pumpAndSettle();
    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    final position = tester.state<ScrollableState>(scroll).position;
    position.jumpTo(250);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.text('作品 3')).dy;
    await tester.tap(find.text('作品 3'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('作品 3')).dy, closeTo(top, 1));
    expect(find.text('详情 0'), findsOneWidget);
    expect(find.text('详情 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in LibraryViewMode.values) {
    testWidgets('原有 $mode 模式点击在所属行展开，不发起导航', (tester) async {
      SharedPreferences.setMockInitialValues({
        'rossi.library.presentation.legacy': jsonEncode(
          const LibraryPresentation(editorial: false).toJson(),
        ),
      });
      var navigated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryEntryList(
              editorialScope: 'legacy',
              mode: mode,
              entries: entries(3),
              standalone: true,
              onTap: (_) => navigated++,
              detailBuilder: (_, entry, close) => Text('详情 ${entry.key}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('作品 0'));
      await tester.pumpAndSettle();
      expect(find.text('详情 0'), findsOneWidget);
      expect(navigated, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('主视觉、分区和不对称可组合；文件打开与信息展开分开', (tester) async {
    var opened = 0;
    final canvasKey = GlobalKey<LibraryEditorialCanvasState>();
    final data = [LibraryEntry(key: 'book', title: '文件', onRead: () async {})];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [LibraryPresentationButton(canvasKey: canvasKey)],
          ),
          body: LibraryEditorialCanvas(
            key: canvasKey,
            scope: 'files',
            entries: data,
            standalone: true,
            tapOpensDetail: false,
            onTap: (_) => opened++,
            legacyBuilder: (_) => const Text('传统视图'),
            detailBuilder: (_, entry, close) =>
                const SizedBox(height: 100, child: Text('文件信息')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openLayoutTab() async {
      final dock = find.byKey(const ValueKey('wall-settings-tabs'));
      await tester.ensureVisible(dock);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: dock,
          matching: find.text(t.workspace.wallTabLayout),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    // 组合开关收进「布局」页签，先切过去。
    await openLayoutTab();
    await tester.ensureVisible(find.widgetWithText(FilterChip, '内容分区'));
    await tester.tap(find.widgetWithText(FilterChip, '内容分区'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '主视觉'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '不对称'))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件').first);
    expect(opened, 1);
    expect(find.text('文件信息'), findsNothing);
    await tester.tap(find.byTooltip('展开信息').first);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('文件信息'), findsOneWidget);
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    await openLayoutTab();
    await tester.ensureVisible(find.widgetWithText(FilterChip, '主视觉'));
    await tester.tap(find.widgetWithText(FilterChip, '主视觉'));
    await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
    await tester.pumpAndSettle();
    expect(find.text('文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [220.0, 320.0, 600.0, 1100.0]) {
    testWidgets('面板宽度 $width 不溢出，48dp 操作入口仍可点击', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryEditorialCanvas(
              scope: 'responsive',
              entries: [
                for (final entry in entries(4))
                  LibraryEntry(
                    key: entry.key,
                    title: entry.title,
                    media: entry.media,
                    onRead: () async {},
                  ),
              ],
              standalone: true,
              onTap: (_) {},
              legacyBuilder: (_) => const SizedBox(),
              detailBuilder: (_, entry, close) => const SizedBox(height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byTooltip('展开信息').first).width,
        greaterThanOrEqualTo(48),
      );
    });
  }

  testWidgets('时间线在展墙模式下覆盖当前分组，关闭后恢复原有分组', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rossi.library.presentation.timeline-wall': jsonEncode(
        const LibraryPresentation(
          editorial: true,
          sections: true,
          hero: false,
          asymmetric: false,
          // 这一段只核对分组：空隙小组件会拿条目分区名当文案，掺进来
          // 「插件甲」就不再是段头独有的字样了。
          gapFill: LibraryGapFill.off,
        ).toJson(),
      ),
    });
    final now = DateTime(2026, 4, 21, 14, 0);
    final times = <String, DateTime>{
      'a': DateTime(2026, 4, 21, 10, 0),
      'b': DateTime(2026, 4, 21, 9, 0),
      'c': DateTime(2026, 4, 20, 18, 0),
    };
    final data = [
      LibraryEntry(key: 'a', title: '作品 A', section: '插件甲'),
      LibraryEntry(key: 'b', title: '作品 B', section: '插件乙'),
      LibraryEntry(key: 'c', title: '作品 C', section: '插件甲'),
    ];

    Widget buildWall({required bool timeline}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: LibraryEditorialCanvas(
              scope: 'timeline-wall',
              entries: data,
              timeline: timeline,
              timelineTimeOf: (entry) => times[entry.key],
              now: now,
              standalone: true,
              onTap: (_) {},
              legacyBuilder: (_) => const Text('传统视图'),
              detailBuilder: (_, entry, close) => Text('详情 ${entry.key}'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWall(timeline: false));
    await tester.pumpAndSettle();
    expect(find.text('插件甲'), findsWidgets);
    expect(find.text('插件乙'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('昨天'), findsNothing);

    await tester.pumpWidget(buildWall(timeline: true));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('插件甲'), findsNothing);
    expect(find.text('插件乙'), findsNothing);

    await tester.pumpWidget(buildWall(timeline: false));
    await tester.pumpAndSettle();
    expect(find.text('插件甲'), findsWidgets);
    expect(find.text('插件乙'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('昨天'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
