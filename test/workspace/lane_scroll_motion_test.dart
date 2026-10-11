import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/widgets/swimlane/workspace_lane_scroll_controller.dart';

Future<WorkspaceLaneScrollController> _mount(
  WidgetTester tester, {
  VoidCallback? onTap,
}) async {
  final controller = WorkspaceLaneScrollController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: controller,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 2400, height: 200),
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

double _velocity(WorkspaceLaneScrollController controller) =>
    (controller.position as ScrollPositionWithSingleContext).activity!.velocity;

void main() {
  testWidgets('回拉平滑起步，最终准确完整定位且不越过目标', (tester) async {
    final controller = await _mount(tester);
    controller.positionTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final firstStep = controller.offset;
    await tester.pump(const Duration(milliseconds: 16));
    final secondStep = controller.offset - firstStep;
    expect(firstStep, greaterThan(0));
    expect(secondStep, greaterThan(firstStep));
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.offset, inInclusiveRange(0, 800));
    }
    await tester.pumpAndSettle();
    expect(controller.offset, 800);
    expect(controller.isPositioning, isFalse);
  });

  testWidgets('重复目标不重启运动，更换目标承接速度', (tester) async {
    final controller = await _mount(tester);
    controller.positionTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final velocity = _velocity(controller);
    final before = controller.offset;
    controller.positionTo(800);
    expect(_velocity(controller), closeTo(velocity, .001));
    controller.positionTo(1200);
    expect(controller.offset, before);
    expect(_velocity(controller), closeTo(velocity, .001));
    await tester.pumpAndSettle();
    expect(controller.offset, 1200);
  });

  testWidgets('反向切换保留连续速度，边界内最终抵达新目标', (tester) async {
    final controller = await _mount(tester);
    controller.jumpTo(1800);
    controller.positionTo(2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final velocity = _velocity(controller);
    controller.positionTo(0);
    expect(_velocity(controller), closeTo(velocity, .001));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中断后没有旧动画补滚，超范围目标按视口约束', (tester) async {
    final controller = await _mount(tester);
    controller.positionTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final stopped = controller.offset;
    controller.jumpTo(stopped);
    await tester.pumpAndSettle();
    expect(controller.offset, stopped);
    expect(controller.isPositioning, isFalse);
    controller.positionTo(4000);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('定位动画中第一下点击也能执行内容', (tester) async {
    var taps = 0;
    final controller = await _mount(tester, onTap: () => taps++);
    controller.positionTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    expect(controller.isPositioning, isTrue);
    await tester.tapAt(tester.getCenter(find.byType(SingleChildScrollView)));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
