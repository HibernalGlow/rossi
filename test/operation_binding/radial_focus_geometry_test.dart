import 'package:flutter/widgets.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/widgets/radial/radial_focus_geometry.dart';

RadialFocusGeometry geometry({
  int count = 8,
  Size size = const Size(360, 640),
  double textScale = 1,
  bool editEmpty = false,
}) {
  final rings = [
    for (var ring = 0; ring < 3; ring++)
      RayMenuRing(
        slotCount: count,
        items: [
          for (var slot = 0; slot < count; slot++)
            if (slot != 1)
              RayMenuItem(
                id: '$ring:$slot',
                label: '操作 $slot',
                slot: slot,
                enabled: slot != 2,
              ),
        ],
      ),
  ];
  final layout = RayMenuLayout(rings: rings, geometry: const RayMenuGeometry());
  return RadialFocusGeometry(
    RayMenuPresentation(
      layout: layout,
      placement: RayMenuPlacement.fit(
        size: size,
        radius: layout.outerRadius,
        center: const Offset(5, 5),
      ),
      size: size,
      style: const RayMenuStyle(),
      visibleRings: 3,
      selected: null,
      centerLabel: '',
      editEmpty: editEmpty,
      onSelected: (_) {},
    ),
    textScale: textScale,
  );
}

void main() {
  for (final count in [1, 2, 8, 24, 64]) {
    for (final textScale in [1.0, 2.0]) {
      test('$count 槽位，字号 $textScale：所有可用按钮可聚焦及准确命中', () {
        final g = geometry(count: count, textScale: textScale);
        final viewport = Offset.zero & g.presentation.size;
        for (final slot in g.centers.keys.where((s) => s.selectable)) {
          final focus = g.origin + g.centers[slot]! * g.overviewScale;
          final pan = g.panFor(focus);
          final rect = g.rectFor(slot, focus: focus, pan: pan, strength: 1);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(viewport.contains(rect.center), isTrue);
          expect(
            g.hitTest(rect.center, focus: focus, pan: pan, strength: 1),
            same(slot),
          );
          // 平移不能把聚焦按钮从指针下推出去。
          expect(
            g.hitTest(focus, focus: focus, pan: pan, strength: 1),
            same(slot),
          );
          expect(rect.center.dx.isFinite && rect.center.dy.isFinite, isTrue);
          for (final other in g.centers.keys) {
            final visible = g.rectFor(
              other,
              focus: focus,
              pan: pan,
              strength: 1,
            );
            expect(visible.left, greaterThanOrEqualTo(0));
            expect(visible.right, lessThanOrEqualTo(viewport.right));
            expect(visible.top, greaterThanOrEqualTo(0));
            expect(visible.bottom, lessThanOrEqualTo(viewport.bottom));
          }
        }
      });
    }
  }

  test('有限平移不会累积，极端指针位置也有界', () {
    final g = geometry();
    final focus = g.presentation.size.bottomRight(Offset.zero);
    expect(g.panFor(focus), g.panFor(focus));
    final outside = g.panFor(const Offset(100000, -100000));
    expect(outside.dx.abs(), lessThanOrEqualTo(48));
    expect(outside.dy.abs(), lessThanOrEqualTo(48));
  });

  test('空槽仅供编辑，禁用项和视口外都不能执行', () {
    for (final editing in [false, true]) {
      final g = geometry(editEmpty: editing);
      for (final index in [1, 2]) {
        if (!editing && index == 1) {
          expect(g.centers.keys.where((s) => s.item == null), isEmpty);
          continue;
        }
        final slot = g.centers.keys.firstWhere(
          (s) => s.ring == 0 && s.index == index,
        );
        final focus = g.origin + g.centers[slot]! * g.overviewScale;
        expect(
          g.hitTest(focus, focus: focus, pan: g.panFor(focus), strength: 1),
          index == 1 && editing ? same(slot) : isNull,
        );
      }
      expect(
        g.hitTest(
          const Offset(-1, -1),
          focus: g.origin,
          pan: Offset.zero,
          strength: 0,
        ),
        isNull,
      );
    }
  });

  test('阅读布局填满中心，空槽不会留下同心环空洞', () {
    final g = geometry(count: 8);
    expect(g.centers.length, 21);
    final center = g.centers.values.reduce(
      (a, b) => a.distance < b.distance ? a : b,
    );
    expect(center.distance, lessThan(g.buttonSize / 2));
    expect(g.centers.values.any((p) => p.distance < g.buttonSize / 2), isTrue);
  });

  test('宽屏默认概览保留每个按钮尺寸，聚焦交接连续', () {
    final g = geometry(count: 8, size: const Size(640, 640));
    for (final slot in g.centers.keys) {
      final rect = g.rectFor(
        slot,
        focus: g.origin,
        pan: Offset.zero,
        strength: 0,
      );
      expect(rect.width, greaterThan(g.buttonSize * .8));
    }
    final a = g.centers.keys.first;
    final b = g.centers.keys.elementAt(1);
    final midpoint =
        g.origin + (g.centers[a]! + g.centers[b]!) * g.overviewScale / 2;
    final before = midpoint - const Offset(.01, 0);
    final after = midpoint + const Offset(.01, 0);
    for (final slot in g.centers.keys) {
      final left = g.rectFor(
        slot,
        focus: before,
        pan: g.panFor(before),
        strength: 1,
      );
      final right = g.rectFor(
        slot,
        focus: after,
        pan: g.panFor(after),
        strength: 1,
      );
      expect((left.width - right.width).abs(), lessThan(.1));
      expect((left.center - right.center).distance, lessThan(.1));
    }
  });
}
