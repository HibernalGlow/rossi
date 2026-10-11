import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_panels.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_tabs.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';

class _ShelfProbe extends StatefulWidget {
  const _ShelfProbe(this.id);
  final int id;

  @override
  State<_ShelfProbe> createState() => _ShelfProbeState();
}

class _ShelfProbeState extends State<_ShelfProbe> {
  final ScrollController controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: controller,
    itemExtent: 60,
    itemCount: 40,
    itemBuilder: (_, index) => Text('shelf ${widget.id}:$index'),
  );
}

void main() {
  testWidgets('实际书架页签共用泳道过渡，跨页跳转懒加载并保留列表滚动位置', (tester) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  BookshelfTabs(
                    labels: const ['收藏', '历史', '下载'],
                    selectedIndex: selected,
                    onSelected: (value) => setState(() => selected = value),
                  ),
                  Expanded(
                    child: BookshelfPanels(
                      selectedIndex: selected,
                      onSelected: (value) => setState(() => selected = value),
                      children: const [
                        _ShelfProbe(0),
                        _ShelfProbe(1),
                        _ShelfProbe(2),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    Finder shelf(int id, {bool hidden = false}) => find.byWidgetPredicate(
      (w) => w is _ShelfProbe && w.id == id,
      skipOffstage: !hidden,
    );
    double alpha(int id) => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: shelf(id), matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    expect(find.byType(RetainedPanelSwitcher), findsOneWidget);
    expect(shelf(1, hidden: true), findsNothing);
    final original = tester.state<_ShelfProbeState>(shelf(0));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final scroll = original.controller.offset;
    expect(scroll, greaterThan(0));
    expect(selected, 0, reason: '垂直滚动不切换收藏/历史/下载');
    await tester.tap(find.text('下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(selected, 2);
    expect(alpha(0), inExclusiveRange(0, 1));
    expect(alpha(2), inExclusiveRange(0, 1));
    expect(shelf(1, hidden: true), findsNothing, reason: '跨页切换不加载中间列表');
    final outgoing = alpha(0);
    final incoming = alpha(2);
    update(() => selected = 1);
    await tester.pump();
    expect(alpha(0), closeTo(outgoing, .0001));
    expect(alpha(2), closeTo(incoming, .0001));
    await tester.pumpAndSettle();
    expect(shelf(1), findsOneWidget);
    await tester.drag(find.byType(BookshelfPanels), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(selected, 0);
    expect(tester.state(shelf(0)), same(original));
    expect(original.controller.offset, scroll);
    await tester.drag(find.byType(BookshelfPanels), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(selected, 0, reason: '首尾边界不产生无效索引');
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL 书架横向手势按阅读方向切换', (tester) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => BookshelfPanels(
                selectedIndex: selected,
                onSelected: (value) => setState(() => selected = value),
                children: const [Text('a'), Text('b'), Text('c')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(BookshelfPanels), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(selected, 2);
    await tester.drag(find.byType(BookshelfPanels), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}
