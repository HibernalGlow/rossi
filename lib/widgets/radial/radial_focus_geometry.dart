import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';

/// 按条目身份填满蜂窝格点，中心也放按钮；槽位编号仅用于原有绑定与编辑。
class RadialFocusGeometry {
  RadialFocusGeometry(this.presentation, {this.textScale = 1}) {
    final shown = presentation.layout.slots
        .where(
          (slot) =>
              slot.ring < presentation.visibleRings &&
              (slot.item != null || presentation.editEmpty),
        )
        .toList();
    final points = _packedPoints(shown.length);
    final angle =
        (presentation.layout.geometry.startAngle + 90) * math.pi / 180;
    final spacing = buttonSize + 12 * textScale.clamp(1, 1.6);
    final centroid = points.isEmpty
        ? Offset.zero
        : points.reduce((a, b) => a + b) / points.length.toDouble();
    for (var index = 0; index < shown.length; index++) {
      final point = (points[index] - centroid) * spacing;
      centers[shown[index]] = Offset(
        point.dx * math.cos(angle) - point.dy * math.sin(angle),
        point.dx * math.sin(angle) + point.dy * math.cos(angle),
      );
    }
    extent =
        centers.values.fold(
          0.0,
          (max, point) => math.max(max, point.distance),
        ) +
        buttonSize / 2 +
        12;
    overviewScale = math.min(
      1.0,
      math.max(1.0, contentSize.shortestSide - buttonSize * 1.12 - 24) /
          (2 * extent),
    );
    final margin = extent * overviewScale + 12;
    final desired = presentation.placement.center;
    origin = Offset(
      desired.dx.clamp(
        math.min(margin, contentSize.width / 2),
        math.max(contentSize.width / 2, contentSize.width - margin),
      ),
      desired.dy.clamp(
        math.min(margin, contentSize.height / 2),
        math.max(contentSize.height / 2, contentSize.height - margin),
      ),
    );
  }

  // 从中心填满六角格点；同一距离的外围点均匀取样，少量操作也不会偏在一侧。
  List<Offset> _packedPoints(int count) {
    if (count == 0) return const [];
    var shell = 0;
    while (1 + 3 * shell * (shell + 1) < count) {
      shell++;
    }
    final bands = <int, List<Offset>>{};
    for (var q = -shell; q <= shell; q++) {
      for (var r = -shell; r <= shell; r++) {
        if ((q + r).abs() > shell) continue;
        final distance = q * q + r * r + q * r;
        (bands[distance] ??= []).add(Offset(q + r / 2, r * math.sqrt(3) / 2));
      }
    }
    final distances = bands.keys.toList()..sort();
    final packed = <Offset>[];
    for (final distance in distances) {
      final band = bands[distance]!;
      double clockwise(Offset p) =>
          (math.atan2(p.dy, p.dx) + math.pi / 2 + math.pi * 2) % (math.pi * 2);
      band.sort((a, b) => clockwise(a).compareTo(clockwise(b)));
      final take = math.min(count - packed.length, band.length);
      for (var i = 0; i < take; i++) {
        packed.add(band[i * band.length ~/ take]);
      }
      if (packed.length == count) break;
    }
    return packed;
  }

  final RayMenuPresentation presentation;
  final double textScale;
  final centers = <RayMenuSlot, Offset>{};
  late final double extent;
  late final double overviewScale;
  late final Offset origin;
  double get buttonSize =>
      (presentation.layout.geometry.radius * .6).clamp(56, 112) *
      textScale.clamp(1, 1.6);
  double get footerHeight => 40 * textScale.clamp(1, 1.6);
  Size get contentSize => Size(
    presentation.size.width,
    math.max(1, presentation.size.height - footerHeight),
  );
  Offset? _lastFocus;
  Offset? _lastPan;
  double? _lastStrength;
  Map<RayMenuSlot, Rect> _rects = const {};

  Offset panFor(Offset focus) {
    // 有限位移由指针位置决定，静止的鼠标不会累积出持续漂移。
    final limit = math.min(48.0, extent * overviewScale * .16);
    final delta = focus - origin;
    return Offset(
      (-delta.dx / math.max(1, contentSize.width / 2)).clamp(-1, 1) * limit,
      (-delta.dy / math.max(1, contentSize.height / 2)).clamp(-1, 1) * limit,
    );
  }

  Rect rectFor(
    RayMenuSlot slot, {
    required Offset focus,
    required Offset pan,
    required double strength,
  }) {
    if (focus != _lastFocus || pan != _lastPan || strength != _lastStrength) {
      _lastFocus = focus;
      _lastPan = pan;
      _lastStrength = strength;
      final projected = {
        for (final slot in centers.keys)
          slot: _project(slot, focus: focus, pan: pan, strength: strength),
      };
      final visible = centers.keys
          .where((s) => s.item != null || presentation.editEmpty)
          .toList();
      final widths = {for (final slot in visible) slot: projected[slot]!.width};
      final attention = {
        for (final slot in visible)
          slot:
              1 /
              math.pow(
                1 +
                    ((focus - origin) / overviewScale - centers[slot]!)
                            .distanceSquared /
                        (buttonSize * buttonSize),
                4,
              ),
      };
      for (var i = 0; i < visible.length; i++) {
        final a = visible[i];
        for (var j = i + 1; j < visible.length; j++) {
          final b = visible[j];
          final delta = projected[a]!.center - projected[b]!.center;
          final available = 2 * math.max(delta.dx.abs(), delta.dy.abs()) - 4;
          final excess = widths[a]! + widths[b]! - available;
          if (excess <= 0) continue;
          // 仅压缩重叠部分，不按权重重分整个宽度，避免外围按钮缩成小点。
          // 权重连续变化，鼠标越过两个图标的中线时也不会交换大小而跳变。
          final share =
              .5 +
              (attention[a]! / (attention[a]! + attention[b]!) - .5) *
                  strength.clamp(0.0, 1.0);
          final shrinkA = math.min(widths[a]! - .5, excess * (1 - share));
          final shrinkB = math.min(widths[b]! - .5, excess - shrinkA);
          widths[a] = math.max(.5, widths[a]! - (excess - shrinkB));
          widths[b] = math.max(.5, widths[b]! - shrinkB);
        }
      }
      for (final slot in visible) {
        projected[slot] = Rect.fromCenter(
          center: projected[slot]!.center,
          width: widths[slot]!,
          height: widths[slot]!,
        );
      }
      _rects = projected;
    }
    return _rects[slot]!;
  }

  Rect _project(
    RayMenuSlot slot, {
    required Offset focus,
    required Offset pan,
    required double strength,
  }) {
    final center = centers[slot]!;
    // 聚焦处固定在指针下；平移渐变地作用于外围，避免密集图标被推离鼠标。
    final focusInMenu = (focus - origin) / overviewScale;
    final delta = center - focusInMenu;
    final distance = delta.distance;
    final field = 110 * textScale.clamp(1, 1.6);
    final gain = (1.12 - overviewScale) * strength.clamp(0.0, 1.0);
    final projected =
        overviewScale * distance + gain * field * math.atan(distance / field);
    final lensPosition = distance < .001
        ? focus
        : focus + delta / distance * projected;
    final desiredPosition =
        lensPosition + pan * (1 - 1 / (1 + math.pow(distance / field, 2)));
    final scale = overviewScale + gain / (1 + math.pow(distance / field, 2));
    final half = buttonSize * scale / 2 + 4;
    final overviewPosition = origin + center * overviewScale;
    final position = Offset(
      _boundedAxis(
        overviewPosition.dx,
        desiredPosition.dx,
        half,
        contentSize.width - half,
      ),
      _boundedAxis(
        overviewPosition.dy,
        desiredPosition.dy,
        half,
        contentSize.height - half,
      ),
    );
    return Rect.fromCenter(
      center: position,
      width: buttonSize * scale,
      height: buttonSize * scale,
    );
  }

  // 边缘采用连续阻尼：给所有按钮留出完整表面，不把多个按钮硬夹到同一个坐标。
  double _boundedAxis(double base, double desired, double min, double max) {
    if (min >= max) return (min + max) / 2;
    base = base.clamp(min, max);
    final delta = desired - base;
    final room = delta >= 0 ? max - base : base - min;
    return room == 0 ? base : base + room * delta / (room + delta.abs());
  }

  double cornerRadius(Rect rect) =>
      presentation.layout.geometry.variant == RayMenuVariant.bubble
      ? rect.width / 2
      : rect.width / 3;

  RayMenuSlot? hitTest(
    Offset point, {
    required Offset focus,
    required Offset pan,
    required double strength,
  }) {
    if (!(Offset.zero & contentSize).contains(point)) return null;
    RayMenuSlot? found;
    var nearest = double.infinity;
    for (final slot in centers.keys) {
      if (!slot.selectable && !(presentation.editEmpty && slot.item == null)) {
        continue;
      }
      final rect = rectFor(slot, focus: focus, pan: pan, strength: strength);
      // 胶囊的画法、语义框与实际落点使用同一份变形几何。
      if (!RRect.fromRectAndRadius(
        rect,
        Radius.circular(cornerRadius(rect)),
      ).contains(point)) {
        continue;
      }
      final distance = (rect.center - point).distanceSquared;
      if (distance < nearest) {
        nearest = distance;
        found = slot;
      }
    }
    return found;
  }
}
