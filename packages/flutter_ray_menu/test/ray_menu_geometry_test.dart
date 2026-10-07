// 几何不变量：标签盒不许伸出圆盘外沿，也不许压到相邻那一圈的标签盒。
//
// 正对外的格子（0°/180°）里，盒子中心在 midRadius 上、宽度只按弦长给，于是
// 半宽直接顶过外沿（表现是「阅读方向切换」这类长标签被圆的边界裁掉几个字），
// 或者压进相邻一圈的同一个方向上（「打开设置」和「向左翻页」糊成一行）。
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读器出厂形状：三层、每层 8 格（4 格有内容），半径 40/120/180/240。
RayMenuLayout _readerLayout() => RayMenuLayout(
  rings: [
    for (var ring = 0; ring < 3; ring++)
      RayMenuRing(
        slotCount: 8,
        items: [
          for (var slot = 0; slot < 8; slot++)
            RayMenuItem(
              id: 'r$ring-s$slot',
              label: '阅读方向切换重置视图',
              slot: slot,
            ),
        ],
      ),
  ],
  geometry: const RayMenuGeometry(radius: 120, innerRadius: 40),
);

Rect _labelRect(RayMenuSlot slot) => Rect.fromCenter(
  center: slot.labelCenter,
  width: slot.labelSize.width,
  height: slot.labelSize.height,
);

RayMenuSlot _slotAt(RayMenuLayout layout, int ring, int index) =>
    layout.slots.firstWhere((slot) => slot.ring == ring && slot.index == index);

void main() {
  test('每一格的标签盒都在自己那圈的外沿之内', () {
    final layout = _readerLayout();
    for (final slot in layout.slots) {
      for (final dx in [-1.0, 1.0]) {
        for (final dy in [-1.0, 1.0]) {
          final corner =
              slot.labelCenter +
              Offset(
                dx * slot.labelSize.width / 2,
                dy * slot.labelSize.height / 2,
              );
          expect(
            corner.distance,
            lessThanOrEqualTo(slot.outerRadius + 0.5),
            reason:
                '第 ${slot.ring} 圈第 ${slot.index} 格'
                '（标签盒 ${slot.labelSize.width.round()}×${slot.labelSize.height.round()}）'
                '的角伸到 ${corner.distance.round()}，超出外沿 ${slot.outerRadius}',
          );
        }
      }
    }
  });

  test('相邻两圈在同一方向上的标签盒不许糊成一行', () {
    // 轴对齐的盒子在极坐标布局里做不到「任何角度都不相交」：45° 方向上盒子的径向
    // 占位是 (w+h)/2·0.707，比环带本身还宽，而那个角上本来就没有字（文本居中）。
    // 真正要守住的是正对外/正对上（0°/90°/180°/270°）—— 那里两圈的盒子会沿同一根
    // 轴排开，压到一起就是「打开设置向左翻页」糊成一行。判据用重叠面积占比：
    // 修之前水平方向能叠到近一半，斜角上只有角尖的几个百分点。
    final layout = _readerLayout();
    for (var ring = 0; ring + 1 < layout.ringCount; ring++) {
      for (var index = 0; index < 8; index++) {
        final a = _slotAt(layout, ring, index);
        final b = _slotAt(layout, ring + 1, index);
        final inner = _labelRect(a);
        final outer = _labelRect(b);
        final smaller = math.min(
          inner.width * inner.height,
          outer.width * outer.height,
        );
        final overlap = inner.intersect(outer);
        final ratio = overlap.width * overlap.height / smaller;
        final cardinal = index.isEven; // 出厂形状：每 45° 一格，偶数格在正方向上
        expect(
          ratio,
          cardinal ? lessThan(0.01) : lessThan(0.15),
          reason:
              '第 $ring 圈与第 ${ring + 1} 圈在第 $index 格'
              '（${(a.angle * 180 / math.pi).round()}°）重叠 '
              '${(ratio * 100).round()}%：$inner vs $outer',
        );
      }
    }
  });
}
