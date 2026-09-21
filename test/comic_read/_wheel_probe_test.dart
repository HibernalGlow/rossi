// 临时探针：只为看清「滚轮被谁吃掉」的机制，验证完即删。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置面板的真实形状：`TabBar` + `TabBarView`（横向 PageView）+ 每页一套纵向滚动。
class _TabPage extends StatelessWidget {
  const _TabPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        for (int i = 0; i < 40; i++)
          SizedBox(height: 60, child: Text('$label-$i')),
      ],
    ),
  );
}

class _Guard extends StatelessWidget {
  const _Guard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent) {
        GestureBinding.instance.pointerSignalResolver.register(event, _swallow);
      }
    },
    child: child,
  );

  static void _swallow(PointerSignalEvent event) {}
}

Axis _axisOf(ScrollPosition p) =>
    p.axisDirection == AxisDirection.up || p.axisDirection == AxisDirection.down
    ? Axis.vertical
    : Axis.horizontal;

ScrollPosition _pos(WidgetTester tester, Axis axis) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .map((s) => s.position)
    .firstWhere((p) => _axisOf(p) == axis);

Future<TabController> _pump(WidgetTester tester, {required bool guard}) async {
  late TabController controller;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) {
              controller = DefaultTabController.of(context);
              return Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'TAB-A'),
                      Tab(text: 'TAB-B'),
                      Tab(text: 'TAB-C'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final label in ['A', 'B', 'C'])
                          if (guard)
                            _Guard(child: _TabPage(label))
                          else
                            _TabPage(label),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _wheel(
  WidgetTester tester,
  Offset delta, {
  bool shift = false,
}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  final target = tester.getCenter(find.byType(SingleChildScrollView).first);
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendEventToBinding(pointer.hover(target));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pumpAndSettle();
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
}

void main() {
  testWidgets('探针：滚到底之后各种滚轮增量分别落到谁身上', (tester) async {
    final controller = await _pump(tester, guard: false);
    final vertical = _pos(tester, Axis.vertical);
    final horizontal = _pos(tester, Axis.horizontal);

    // ① 列表中间：纵向滚轮应当滚内容
    final before = vertical.pixels;
    await _wheel(tester, const Offset(0, 120));
    debugPrint('① 中间纵向滚轮：vertical ${before} → ${vertical.pixels}');
    debugPrint('   横向 pixels=${horizontal.pixels} index=${controller.index}');

    // ② 滚到底，再滚一次纯纵向
    vertical.jumpTo(vertical.maxScrollExtent);
    await tester.pumpAndSettle();
    await _wheel(tester, const Offset(0, 120));
    debugPrint(
      '② 到底后纯纵向：vertical=${vertical.pixels}/${vertical.maxScrollExtent}',
    );
    debugPrint('   横向 pixels=${horizontal.pixels} index=${controller.index}');

    // ③ 到底后带横向分量（触控板斜着划 / 带侧滚的鼠标）
    await _wheel(tester, const Offset(120, 120));
    debugPrint(
      '③ 到底后斜向(dx=120,dy=120)：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );

    // ④ 到底后纯横向
    await _wheel(tester, const Offset(120, 0));
    debugPrint(
      '④ 到底后纯横向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );

    // ⑤ 到底后 Shift+纵向（框架的翻转轴）
    await _wheel(tester, const Offset(0, 120), shift: true);
    debugPrint(
      '⑤ 到底后 Shift+纵向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );
  });

  testWidgets('探针：加了一层「滚轮边界」之后同样四种增量', (tester) async {
    final controller = await _pump(tester, guard: true);
    final vertical = _pos(tester, Axis.vertical);
    final horizontal = _pos(tester, Axis.horizontal);

    final before = vertical.pixels;
    await _wheel(tester, const Offset(0, 120));
    debugPrint('① 中间纵向滚轮：vertical ${before} → ${vertical.pixels}');

    vertical.jumpTo(vertical.maxScrollExtent);
    await tester.pumpAndSettle();

    await _wheel(tester, const Offset(0, 120));
    debugPrint(
      '② 到底后纯纵向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );
    await _wheel(tester, const Offset(120, 120));
    debugPrint(
      '③ 到底后斜向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );
    await _wheel(tester, const Offset(120, 0));
    debugPrint(
      '④ 到底后纯横向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );
    await _wheel(tester, const Offset(0, 120), shift: true);
    debugPrint(
      '⑤ 到底后 Shift+纵向：横向 pixels=${horizontal.pixels} index=${controller.index}',
    );
  });
}
