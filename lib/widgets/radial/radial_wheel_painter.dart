// 轮盘的**画法** —— 运行时浮层与设置页预览共用这一份。
//
// 为什么单独一个文件：预览和运行时必须是同一个轮盘。两处各写一遍弧线与文字摆放，
// 「设置页里长这样、读起来长那样」就成了常态 bug。所以两边都只喂同一份
// [RadialSlotPaint]（核心算出来的数字，见 `OperationBindingStore.radialLayout`）
// 给同一个 painter。
//
// 文字也从那份数字里来（`slot.label`）：显示文字住在轮盘文档的条目上，
// 而不是在绘制处按动作 id 现查 —— 否则「文档里的名字」与「画出来的名字」会有两处权威。
//
// 角度口径：核心给的是**度**，屏幕坐标系（x 右、y 下），`-90°` 是正上方。
// Flutter 的 `drawArc` 恰好同一口径（0 弧度在 3 点、顺时针为正），所以直接换弧度、
// 不做任何翻转 —— 一旦在这里「顺手加个负号」，就会出现镜像的轮盘。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';

/// 一个轮盘的绘制器。
class RadialWheelPainter extends CustomPainter {
  RadialWheelPainter({
    required this.slots,
    required this.colors,
    this.hoveredItem,
    this.scale = 1.0,
    this.centerLabel,
    this.textScaleFactor = 1.0,
  });

  /// 核心给的槽位布局（含空格；外半径最大的那一层决定整个轮盘占多大）。
  final List<RadialSlotPaint> slots;

  final ColorScheme colors;

  /// 当前高亮的槽（`itemId`；运行时跟随指针，预览传 `null`）。
  final String? hoveredItem;

  /// 整体缩放：几何是逻辑像素（默认 r120），小屏要能塞进去。
  final double scale;

  /// 中心空洞里的文字（运行时是提示语，预览是轮盘名）。
  final String? centerLabel;

  final double textScaleFactor;

  /// 轮盘外缘半径（缩放后），外壳用它定位与留白。
  double get paintedRadius => naturalRadius * scale;

  /// 核心几何里的外半径（未缩放）。
  double get naturalRadius =>
      slots.fold<double>(0, (max, slot) => math.max(max, slot.outerRadius));

  /// 中心空洞半径（缩放后）：落在这里 = 松手取消。
  double get paintedHoleRadius =>
      (slots.isEmpty
          ? 0.0
          : slots
                .map((slot) => slot.innerRadius)
                .reduce((min, value) => math.min(min, value))) *
      scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.outlineVariant.withValues(alpha: 0.7);
    final hoveredFill = Paint()
      ..color = colors.primary.withValues(alpha: 0.22);
    final filledFill = Paint()
      ..color = colors.surfaceContainerHighest.withValues(alpha: 0.55);
    final emptyFill = Paint()
      ..color = colors.surface.withValues(alpha: 0.35);

    for (final slot in slots) {
      final path = _sectorPath(slot);
      final label = slot.label ?? '';
      final hovered = slot.itemId != null && slot.itemId == hoveredItem;
      canvas.drawPath(path, hovered ? hoveredFill : (label.isEmpty ? emptyFill : filledFill));
      canvas.drawPath(path, hairline);
      if (label.isEmpty) {
        _paintPlus(canvas, slot);
      } else {
        _paintLabel(canvas, slot, label, hovered: hovered, dim: slot.disabled);
      }
    }

    // 环带边界与中心：截图里那几圈细线，让「第几层」在视觉上成立。
    for (final radius in _ringRadii()) {
      canvas.drawCircle(Offset.zero, radius, hairline);
    }
    final hole = paintedHoleRadius;
    canvas.drawCircle(
      Offset.zero,
      hole,
      Paint()..color = colors.surface.withValues(alpha: 0.9),
    );
    canvas.drawCircle(Offset.zero, hole, hairline);
    final text = centerLabel;
    if (text != null && text.isNotEmpty) {
      _paintCenterLabel(canvas, text, hole);
    }

    canvas.restore();
  }

  /// 一个槽的扇环路径（内外两段弧 + 两条半径边）。
  Path _sectorPath(RadialSlotPaint slot) {
    final start = slot.startDeg * math.pi / 180.0;
    final sweep = (slot.endDeg - slot.startDeg) * math.pi / 180.0;
    final outer = slot.outerRadius * scale;
    final inner = slot.innerRadius * scale;
    final outerRect = Rect.fromCircle(center: Offset.zero, radius: outer);
    final innerRect = Rect.fromCircle(center: Offset.zero, radius: inner);
    return Path()
      ..arcTo(outerRect, start, sweep, false)
      ..arcTo(innerRect, start + sweep, -sweep, false)
      ..close();
  }

  Set<double> _ringRadii() => {
    for (final slot in slots) ...[
      slot.innerRadius * scale,
      slot.outerRadius * scale,
    ],
  };

  /// 槽的中心点（角度取中线，半径取环带正中）。
  Offset _slotCenter(RadialSlotPaint slot) {
    final angle = slot.midDeg * math.pi / 180.0;
    final radius = (slot.innerRadius + slot.outerRadius) / 2.0 * scale;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  /// 空槽画一个 `+`（截图里那些待添加的位置）。
  void _paintPlus(Canvas canvas, RadialSlotPaint slot) {
    final center = _slotCenter(slot);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.65);
    const arm = 4.0;
    canvas.drawLine(
      center - const Offset(arm, 0),
      center + const Offset(arm, 0),
      paint,
    );
    canvas.drawLine(
      center - const Offset(0, arm),
      center + const Offset(0, arm),
      paint,
    );
  }

  void _paintLabel(
    Canvas canvas,
    RadialSlotPaint slot,
    String label, {
    required bool hovered,
    bool dim = false,
  }) {
    // 文字宽度以环带宽度的八成为限：宁可省略号，也不要跨到隔壁槽里去。
    final available = math.max(
      28.0,
      (slot.outerRadius - slot.innerRadius) * scale * 0.85,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 11 * textScaleFactor,
          height: 1.15,
          fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
          color: hovered
              ? colors.onSurface
              : (dim
                    ? colors.onSurfaceVariant.withValues(alpha: 0.5)
                    : colors.onSurfaceVariant),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: available);
    painter.paint(
      canvas,
      _slotCenter(slot) - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintCenterLabel(Canvas canvas, String text, double hole) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10 * textScaleFactor,
          color: colors.onSurfaceVariant,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: hole * 1.7);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  }

  @override
  bool shouldRepaint(RadialWheelPainter old) =>
      old.hoveredItem != hoveredItem ||
      old.scale != scale ||
      old.centerLabel != centerLabel ||
      old.slots.length != slots.length;
}

/// 轮盘的最大可画直径（浮层与预览都按这个留白，超出就整体缩放）。
const double kRadialWheelMaxDiameter = 420.0;

/// 把核心的几何缩放进一个盒子：返回 `scale`，让轮盘既不溢出也不浪费空间。
double radialFitScale({
  required Size box,
  required double radius,
  double maxDiameter = kRadialWheelMaxDiameter,
}) {
  if (radius <= 0) return 1.0;
  final needed = radius * 2;
  final limit = math.min(math.min(box.width, box.height), maxDiameter);
  final fitted = limit / needed;
  return fitted > 1.0 ? 1.0 : fitted;
}
