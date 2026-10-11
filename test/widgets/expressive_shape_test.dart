import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

ExpressiveMorphBorder buttonBorder(WidgetTester tester) =>
    tester
            .widget<IconButton>(find.byType(IconButton).first)
            .style!
            .shape!
            .resolve({})
        as ExpressiveMorphBorder;

void main() {
  test('目录中每种轮廓的完整形变路径有限、闭合、始终在按钮区域内', () {
    const rect = Rect.fromLTWH(17, 29, 56, 56);
    for (final shape in ExpressiveButtonShape.values) {
      for (var step = 0; step <= 20; step++) {
        final phase = step / 10;
        final path = expressiveButtonBorder(
          shape,
          phase,
          56,
        ).getOuterPath(rect);
        final reason = '$shape phase=$phase';
        final metric = path.computeMetrics().single;
        expect(metric.isClosed, isTrue, reason: reason);
        expect(metric.length.isFinite, isTrue, reason: reason);
        expect(metric.length, greaterThan(0), reason: reason);
        // Path.getBounds 包含贝塞尔控制点，不能作为实际曲线边界。
        for (var sample = 0; sample < 100; sample++) {
          final point = metric
              .getTangentForOffset(metric.length * sample / 100)!
              .position;
          expect(
            point.dx.isFinite && point.dy.isFinite,
            isTrue,
            reason: reason,
          );
          expect(
            rect.inflate(.01).contains(point),
            isTrue,
            reason: '$reason $point',
          );
        }
      }
    }
  });

  test('按压到展开经过中间轮廓时，外形连续且没有重新缩放', () {
    const rect = Rect.fromLTWH(0, 0, 56, 56);
    for (final shape in ExpressiveButtonShape.values) {
      final before = expressiveButtonBorder(
        shape,
        .999999,
        56,
      ).getOuterPath(rect);
      final after = expressiveButtonBorder(
        shape,
        1.000001,
        56,
      ).getOuterPath(rect);
      // 两次曲线匹配的分段不同，PathMetric 的近似周长不可直接比较；
      // 检查实际填充区域，防止连接点换形或旋转。
      for (var x = .37; x < 56; x += 2) {
        for (var y = .61; y < 56; y += 2) {
          final point = Offset(x, y);
          if (before.contains(point) != after.contains(point)) {
            // Path.contains 的曲线分段精度会在轮廓边缘产生细微差异。
            final metric = before.computeMetrics().single;
            var nearest = double.infinity;
            for (var i = 0; i < 2000; i++) {
              final edge = metric
                  .getTangentForOffset(metric.length * i / 2000)!
                  .position;
              final distance = (edge - point).distance;
              if (distance < nearest) nearest = distance;
            }
            expect(nearest, lessThan(.2), reason: '$shape at $point');
          }
        }
      }
    }
  });

  testWidgets('按压连续变形，中途松开从当前进度返回且布局不跳动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ExpressiveIconButton(
              glyph: AppGlyphs.download,
              tooltip: '下载',
              shape: ExpressiveButtonShape.arrow,
              size: 56,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final finder = find.byType(IconButton);
    final initialSize = tester.getSize(finder);
    expect(buttonBorder(tester).progress, 0);
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final held = buttonBorder(tester).progress;
    expect(held, greaterThan(0));
    expect(held, lessThan(1));
    await gesture.up();
    await tester.pump();
    expect(buttonBorder(tester).progress, closeTo(held, .001));
    await tester.pump(const Duration(milliseconds: 90));
    expect(buttonBorder(tester).progress, lessThan(held));
    await tester.pumpAndSettle();
    expect(buttonBorder(tester).progress, 0);
    expect(tester.getSize(finder), initialSize);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('菜单开合使用独立形变终点，减少动画=$reduced', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: Center(
                child: ShelfMenuButton(
                  glyph: AppGlyphs.menu,
                  tooltip: '书签操作',
                  shape: ExpressiveButtonShape.cookie6Sided,
                  menuChildren: [ShelfMenuItem(label: '创建', onPressed: () {})],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('书签操作'));
      if (reduced) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
      final open = buttonBorder(tester);
      expect(open.from, ExpressiveButtonShape.flower);
      expect(open.to, ExpressiveButtonShape.circle);
      expect(open.progress, 1);
      await tester.tap(find.text('创建'), warnIfMissed: true);
      await tester.pumpAndSettle();
      final closed = buttonBorder(tester);
      expect(closed.from, ExpressiveButtonShape.cookie6Sided);
      expect(closed.progress, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
