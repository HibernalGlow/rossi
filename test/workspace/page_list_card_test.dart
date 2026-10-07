import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_card.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_row_anchor.dart';

void main() {
  setUp(() {
    ReaderSessionCoordinator.instance.detachSession('test-comic');
  });

  tearDown(() {
    ReaderSessionCoordinator.instance.detachSession('test-comic');
  });

  testWidgets('PageListCard 在空会话下正常渲染且无断言失败', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: PageListCard(
              isExpanded: true,
              onToggle: _noop,
              isStandalone: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('打开书本后显示页面导航'), findsOneWidget);
  });

  testWidgets(
    'PageListCard 在活跃会话下正常渲染 active content (listWidget) 且无 shape/borderRadius 断言失败',
    (tester) async {
      _attachSession(currentSlot: 0, totalSlots: 2);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 600,
              child: PageListCard(
                isExpanded: true,
                onToggle: _noop,
                isStandalone: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  // ── 卡片这一层：跟随进度落在哪儿 ──────────────────────────────────────
  //
  // 断言一律量「当前页离可视区中心还差几像素」，不量滚动偏移：偏移该落在哪儿取决于
  // 行高，而行高正是这次出错的根源 —— 三种模式写死的 136 / 72 / 38 与实测真值
  // 162.9 / 56 / 32 全都不符，误差还随页码线性放大。翻到第 151 页时当前页被推到
  // 可视区下方一千四百多像素，在旧代码里它连「被建出来」都不会发生。
  group('跟随阅读进度：当前页落在正中', () {
    testWidgets('开面板时当前页已在第 151 页 —— 建好就把这一行居中', (tester) async {
      await _pumpCard(tester, currentSlot: 150);
      expect(_deltaFromCenter(tester, _Probe.grid), lessThan(10.0));
    });

    testWidgets('翻到远处的第 248 页后，当前页回到正中', (tester) async {
      await _pumpCard(tester, currentSlot: 0);
      ReaderSessionCoordinator.instance.updateProgress(
        currentSlot: 247,
        totalSlots: 300,
      );
      await tester.pumpAndSettle();
      expect(_deltaFromCenter(tester, _Probe.grid), lessThan(10.0));
    });

    testWidgets('三种视图模式下都居中（换模式不会停在旧偏移上）', (tester) async {
      await _pumpCard(tester, currentSlot: 0);
      ReaderSessionCoordinator.instance.updateProgress(
        currentSlot: 150,
        totalSlots: 300,
      );
      await tester.pumpAndSettle();
      expect(_deltaFromCenter(tester, _Probe.grid), lessThan(10.0));

      await tester.tap(find.byTooltip('视图模式'));
      await tester.pumpAndSettle();
      expect(_deltaFromCenter(tester, _Probe.details), lessThan(10.0));

      await tester.tap(find.byTooltip('视图模式'));
      await tester.pumpAndSettle();
      expect(_deltaFromCenter(tester, _Probe.compact), lessThan(10.0));
    });

    testWidgets('最后一页居中不了时夹紧，整行仍在可视区内', (tester) async {
      await _pumpCard(tester, currentSlot: 299);
      final view = tester.getRect(find.byType(GridView).first);
      final row = _rowRect(tester, _Probe.grid);
      expect(row.bottom, lessThanOrEqualTo(view.bottom + 1.0));
      expect(row.top, greaterThanOrEqualTo(view.top - 1.0));
    });

    testWidgets('对照：关掉「跟随阅读进度」后，翻页不再移动画面', (tester) async {
      await _pumpCard(tester, currentSlot: 0);
      await tester.tap(find.byTooltip('正在跟随阅读进度'));
      await tester.pumpAndSettle();

      ReaderSessionCoordinator.instance.updateProgress(
        currentSlot: 150,
        totalSlots: 300,
      );
      await tester.pumpAndSettle();

      // 上面几条的「居中」确实来自跟随这条路：关掉以后画面就停在原处。
      expect(_gridPosition(tester).pixels, lessThan(200.0));
      expect(find.text('当前'), findsNothing);
    });
  });

  // ── 量行这一层：PageListRowAnchor 的几何口径 ──────────────────────────
  //
  // 这里的列表是按卡片三种模式的真实参数搭的副本（同一个 crossAxisCount /
  // childAspectRatio / 行高 / padding）。卡片那组覆盖不到「目标行还没建出来时
  // 按量出的行距外推」这种细节，所以这一组单独盯着偏移本身；卡片接线由上面负责。
  group('PageListRowAnchor：从渲染树量出的偏移', () {
    testWidgets('缩略图网格：目标行还没建出来时，按量出的行距外推后仍然居中', (tester) async {
      final controller = ScrollController();
      await _pumpReplica(
        tester,
        controller: controller,
        list: _thumbnailGrid(controller),
      );

      final anchor = PageListRowAnchor.measure(
        controller.position,
        itemIndex: 150,
        itemsPerRow: 3,
      );
      // 344 宽、每行 3 列、0.68 宽高比：真值行距 162.86，不是从前写死的 136。
      expect(anchor!.rowExtent, closeTo(162.86, 0.5));
      controller.jumpTo(anchor.centeredOffset);
      await tester.pumpAndSettle();
      expect(_replicaDelta(tester, GridView, 150), lessThan(8.0));

      // 阳性对照：老公式（行号 × 136 − 100）落在 6700，那一行压根没进可视区，
      // 说明上面这把尺子量得到违规，不是恰好通过。
      controller.jumpTo(50 * 136 - 100);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(150)), findsNothing);
    });

    testWidgets('详细模式：行距由 ListTile 决定，量出来是 56 而不是 72', (tester) async {
      final controller = ScrollController();
      await _pumpReplica(
        tester,
        controller: controller,
        list: _detailRows(controller),
      );

      final anchor = PageListRowAnchor.measure(
        controller.position,
        itemIndex: 150,
        itemsPerRow: 1,
      );
      expect(anchor!.rowExtent, closeTo(56.0, 0.5));
      controller.jumpTo(anchor.centeredOffset);
      await tester.pumpAndSettle();
      expect(_replicaDelta(tester, ListView, 150), lessThan(8.0));
    });

    testWidgets('紧凑列表：32 高的行居中', (tester) async {
      final controller = ScrollController();
      await _pumpReplica(
        tester,
        controller: controller,
        list: _compactRows(controller),
      );

      final anchor = PageListRowAnchor.measure(
        controller.position,
        itemIndex: 150,
        itemsPerRow: 1,
      );
      expect(anchor!.rowExtent, closeTo(32.0, 0.5));
      controller.jumpTo(anchor.centeredOffset);
      await tester.pumpAndSettle();
      expect(_replicaDelta(tester, ListView, 150), lessThan(8.0));
    });

    testWidgets('末尾夹不住居中时不越过内容末尾', (tester) async {
      final controller = ScrollController();
      await _pumpReplica(
        tester,
        controller: controller,
        list: _thumbnailGrid(controller),
      );

      final anchor = PageListRowAnchor.measure(
        controller.position,
        itemIndex: 299,
        itemsPerRow: 3,
      );
      controller.jumpTo(anchor!.centeredOffset);
      await tester.pumpAndSettle();
      expect(
        controller.position.pixels,
        closeTo(controller.position.maxScrollExtent, 1.0),
      );
      final view = tester.getRect(find.byType(GridView).first);
      final row = tester.getRect(find.byKey(const ValueKey(299)).first);
      expect(row.bottom, lessThanOrEqualTo(view.bottom + 1.0));
      expect(row.top, greaterThanOrEqualTo(view.top - 1.0));
    });
  });
}

enum _Probe { grid, details, compact }

void _noop() {}

List<Doc> _docs(int count) => List<Doc>.generate(
  count,
  (i) => Doc(
    originalName: 'page${i + 1}.jpg',
    path: 'p$i',
    fileServer: 's1',
    id: '$i',
  ),
);

void _attachSession({required int currentSlot, required int totalSlots}) {
  ReaderSessionCoordinator.instance.attachSession(
    comicId: 'test-comic',
    from: 'test',
    title: '测试漫画',
    epInfo: NormalComicEpInfo(epName: '第 1 话', docs: _docs(totalSlots)),
    currentSlot: currentSlot,
    totalSlots: totalSlots,
    jumpToSlot: (_) async {},
  );
}

/// 在 360×600 的独立面板尺寸下把卡片搭起来（右侧「页面导航」泳道就是这个量级）。
Future<void> _pumpCard(WidgetTester tester, {required int currentSlot}) async {
  _attachSession(currentSlot: currentSlot, totalSlots: 300);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: const SizedBox(
          width: 360,
          height: 600,
          child: PageListCard(
            isExpanded: true,
            onToggle: _noop,
            isStandalone: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _gridPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// 当前页那一行的矩形；这一行没被建出来时直接判定失败（= 它已经不在可视区里）。
Rect _rowRect(WidgetTester tester, _Probe probe) {
  final Finder badge = switch (probe) {
    _Probe.compact => find.byIcon(Icons.check_circle_rounded),
    _ => find.text('当前'),
  };
  final Finder row = find.ancestor(
    of: badge,
    matching: find.byType(probe == _Probe.details ? ListTile : InkWell),
  );
  expect(
    row,
    findsOneWidget,
    reason: '$probe 模式下没找到当前页那一行：它已经滚出可视区了',
  );
  return tester.getRect(row.first);
}

/// 当前页那一行的中心，离可视区中心还差几像素（取绝对值，偏上偏下都算没对准）。
double _deltaFromCenter(WidgetTester tester, _Probe probe) {
  final Type listType = probe == _Probe.grid ? GridView : ListView;
  final view = tester.getRect(find.byType(listType).first);
  final row = _rowRect(tester, probe);
  return (row.center.dy - view.center.dy).abs();
}

// ── 副本列表：只喂 PageListRowAnchor，不经过卡片 ─────────────────────────

Widget _thumbnailGrid(ScrollController controller) => GridView.builder(
  controller: controller,
  padding: const EdgeInsets.all(6),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    childAspectRatio: 0.68,
    crossAxisSpacing: 6,
    mainAxisSpacing: 6,
  ),
  itemCount: 300,
  itemBuilder: (context, i) => Container(key: ValueKey(i)),
);

Widget _detailRows(ScrollController controller) => ListView.builder(
  controller: controller,
  padding: const EdgeInsets.all(4),
  itemCount: 300,
  itemBuilder: (context, i) => Container(
    key: ValueKey(i),
    margin: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: const SizedBox(width: 42, height: 56),
      title: Text('#${i + 1}'),
    ),
  ),
);

Widget _compactRows(ScrollController controller) => ListView.builder(
  controller: controller,
  padding: const EdgeInsets.all(4),
  itemCount: 300,
  itemBuilder: (context, i) => Container(key: ValueKey(i), height: 32),
);

Future<void> _pumpReplica(
  WidgetTester tester, {
  required ScrollController controller,
  required Widget list,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 344, height: 492, child: list)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(controller.hasClients, isTrue);
}

double _replicaDelta(WidgetTester tester, Type listType, int index) {
  final view = tester.getRect(find.byType(listType).first);
  final row = tester.getRect(find.byKey(ValueKey(index)).first);
  return (row.center.dy - view.center.dy).abs();
}
