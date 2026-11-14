import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

SpringLensPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<SpringLensPainter>()
    .single;

Widget _bar({
  required ValueChanged<int> onSelected,
  int selected = 0,
  Axis axis = Axis.horizontal,
  bool draggable = true,
}) => SpringLensBar(
  axis: axis,
  tabs: const [
    SpringLensTab(
      child: SizedBox(width: 40, height: 32, child: Center(child: Text('A'))),
    ),
    SpringLensTab(
      child: SizedBox(width: 40, height: 32, child: Center(child: Text('B'))),
    ),
    SpringLensTab(
      child: SizedBox(width: 40, height: 32, child: Center(child: Text('C'))),
    ),
  ],
  tabSizes: const [80, 80, 80],
  selectedIndex: selected,
  onSelected: onSelected,
  draggable: draggable,
  lensColor: Colors.blue,
  tintColor: Colors.white,
);

void main() {
  testWidgets('普通点击和取消均复位按压，下一次拖动正常提交一次', (tester) async {
    var selected = 0;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => _bar(
                selected: selected,
                onSelected: (value) => setState(() {
                  selected = value;
                  calls++;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final press = await tester.startGesture(tester.getCenter(find.text('B')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_painter(tester).lift, greaterThan(0));
    await press.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(calls, 1);
    expect(_painter(tester).lift, closeTo(0, 0.001));
    expect(_painter(tester).position, closeTo(1, 0.001));

    final cancel = await tester.startGesture(tester.getCenter(find.text('B')));
    await cancel.moveBy(const Offset(85, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await cancel.cancel();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(_painter(tester).lift, closeTo(0, 0.001));
    expect(_painter(tester).position, closeTo(1, 0.001));

    await tester.drag(find.text('B'), const Offset(85, 0));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(calls, 2);
    expect(_painter(tester).lift, closeTo(0, 0.001));
    expect(tester.takeException(), isNull);
  });

  for (final axis in Axis.values) {
    testWidgets('$axis：页签拖动不滚父容器，页签外拖动仍可滚动', (tester) async {
      final controller = ScrollController(initialScrollOffset: 480);
      addTearDown(controller.dispose);
      var selected = 0;
      final horizontal = axis == Axis.horizontal;
      final outside = SizedBox(
        key: const ValueKey('outside'),
        width: horizontal ? 600 : 80,
        height: horizontal ? 80 : 600,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: axis,
                  child: Flex(
                    direction: axis,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      outside,
                      StatefulBuilder(
                        builder: (context, setState) => _bar(
                          axis: axis,
                          selected: selected,
                          onSelected: (value) =>
                              setState(() => selected = value),
                        ),
                      ),
                      SizedBox(
                        width: horizontal ? 600 : 80,
                        height: horizontal ? 80 : 600,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 480);
      final first = tester.getCenter(find.text('A'));
      final gesture = await tester.startGesture(first);
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(
          horizontal ? const Offset(40, 0) : const Offset(0, 40),
        );
        await tester.pump(const Duration(milliseconds: 40));
        expect(controller.offset, 480, reason: '父容器在手指未松开时也不能滚动');
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(controller.offset, 480);

      // 从 C 往回拖：父容器位于中间，两种方向都实际有滚动空间。
      await tester.drag(
        find.text('C'),
        horizontal ? const Offset(-160, 0) : const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(controller.offset, 480);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      await tester.dragFrom(
        viewport.topLeft + const Offset(35, 35),
        horizontal ? const Offset(-90, 0) : const Offset(0, -90),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(480));
    });
  }

  testWidgets('横排页签上的竖拖交还竖向父容器并取消按压', (tester) async {
    final controller = ScrollController(initialScrollOffset: 480);
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 600),
                  _bar(onSelected: (_) => calls++),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('B'), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(480));
    expect(calls, 0);
    expect(_painter(tester).lift, closeTo(0, 0.001));
  });

  testWidgets('悬停不移动内容：画在哪儿、点到的就是哪儿', (tester) async {
    var left = 0;
    var right = 0;
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SpringLensBar(
                key: const ValueKey('bar'),
                tabSizes: const [200],
                selectedIndex: 0,
                onSelected: (_) {},
                tabs: [
                  SpringLensTab(
                    // 左右各半格、各上一种颜色：一格「往指针那边滑」时，
                    // 110 这一点的颜色和命中的那一半会立刻对不上。
                    child: SizedBox(
                      width: 200,
                      height: 40,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('left'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => left++,
                              child: const ColoredBox(color: Colors.red),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('right'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => right++,
                              child: const ColoredBox(color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(const ValueKey('bar')));
    final y = origin.dy + 20;

    // 鼠标停在格心右侧 60px —— 早先的视差会把整格内容再往右推半格多。
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(origin.dx + 160, y));
    await tester.pumpAndSettle();

    // x=110 画出来的必须是右半格，点下去也必须落在右半格。
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final color = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final local =
          Offset(110, 20) - (tester.getTopLeft(find.byKey(boundaryKey)));
      final index = (local.dy.floor() * image.width + local.dx.floor()) * 4;
      final result = Color.fromARGB(
        bytes.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
      image.dispose();
      return result;
    });
    expect(color?.toARGB32(), Colors.green.toARGB32(), reason: '悬停不许把内容挪走');

    await tester.tapAt(Offset(origin.dx + 110, y));
    await tester.pumpAndSettle();
    expect(right, 1);
    expect(left, 0);
    expect(tester.takeException(), isNull);
  });

  test('不等宽页签：整数位置严格匹配本格宽度，等宽页签不扩成整条栏', () {
    final uneven = LensSlots.sized(sizes: [30, 90, 60], crossSize: 28);
    final rect = lensRect(slots: uneven, position: 1, velocity: 0, lift: 0);
    expect(rect.center.dx, 75);
    expect(rect.width, 90);
    final uniform = LensSlots.sized(
      sizes: [30, 30],
    ).resolvedTo(const Size(400, 28))!;
    final small = lensRect(slots: uniform, position: 1, velocity: 0, lift: 0);
    expect(small.width, 30);
    expect(small.center.dx, 45);
    for (final x in [-1.0, 0.0, 15.0, 30.0, 75.0, 120.0, 180.0, 181.0]) {
      final before = uneven.positionAt(x - 0.0001);
      final after = uneven.positionAt(x + 0.0001);
      expect((after - before).abs(), lessThan(0.001), reason: '边缘或槽位交界不能跳跃');
    }
  });
}
