// Adapted from agmmnn/ray-menu (MIT), core/angle and wc/ray-menu-rendering,
// and NeoView's _getBand / _buildVisibleSlots. See THIRD_PARTY_NOTICES.md.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'ray_menu_models.dart';

@immutable
class RayMenuGeometry {
  const RayMenuGeometry({
    this.radius = 120,
    this.innerRadius = 40,
    this.ringWidth = 60,
    this.startAngle = -90,
    this.sweepAngle = 360,
    this.gap = 3,
    this.ringGap = 2,
    this.variant = RayMenuVariant.slice,
  }) : assert(radius > innerRadius && innerRadius >= 0),
       assert(ringWidth > 0),
       assert(sweepAngle > 0 && sweepAngle <= 360),
       assert(gap >= 0 && ringGap >= 0);

  final double radius;
  final double innerRadius;
  final double ringWidth;

  /// Degrees clockwise from the right. The first slot is centered here,
  /// matching the reader's persisted slot convention.
  final double startAngle;
  final double sweepAngle;
  final double gap;
  final double ringGap;
  final RayMenuVariant variant;
}

class RayMenuSlot {
  RayMenuSlot({
    required this.ring,
    required this.index,
    required this.item,
    required this.innerRadius,
    required this.outerRadius,
    required this.angle,
    required this.sweep,
    required RayMenuGeometry geometry,
  }) {
    final midRadius = (innerRadius + outerRadius) / 2;
    labelCenter = Offset(math.cos(angle), math.sin(angle)) * midRadius;
    final chord = 2 * midRadius * math.sin(math.min(sweep, math.pi) / 2);
    labelSize = Size(
      math.max(1, math.min(104, chord * 0.82)),
      math.max(1, math.min(48, outerRadius - innerRadius - 8)),
    );
    final radialGap = math.min(
      geometry.ringGap / 2,
      (outerRadius - innerRadius) / 4,
    );
    final inner = innerRadius + radialGap;
    final outer = outerRadius - radialGap;
    if (geometry.variant == RayMenuVariant.bubble) {
      final radius = math.min((outer - inner) / 2, chord * 0.44);
      path = Path()
        ..addOval(Rect.fromCircle(center: labelCenter, radius: radius));
      labelSize = Size.square(math.max(1, radius * 1.55));
    } else {
      final angularGap = math.min(geometry.gap * math.pi / 180, sweep / 3);
      final start = angle - sweep / 2 + angularGap / 2;
      final arc = sweep - angularGap;
      // SVG describeArc's outer clockwise + inner counter-clockwise arcs.
      path = Path()
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: outer),
          start,
          arc,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: inner),
          start + arc,
          -arc,
          false,
        )
        ..close();
    }
  }

  final int ring;
  final int index;
  final RayMenuItem? item;
  final double innerRadius;
  final double outerRadius;
  final double angle;
  final double sweep;
  late final Path path;
  late final Offset labelCenter;
  late Size labelSize;
  bool get selectable => item?.enabled == true;
}

/// One set of paths owns painting, labels, and pointer hit testing.
class RayMenuLayout {
  RayMenuLayout({required List<RayMenuRing> rings, required this.geometry}) {
    if (!geometry.radius.isFinite ||
        !geometry.innerRadius.isFinite ||
        !geometry.ringWidth.isFinite ||
        !geometry.startAngle.isFinite ||
        !geometry.sweepAngle.isFinite ||
        !geometry.gap.isFinite ||
        !geometry.ringGap.isFinite ||
        geometry.innerRadius < 0 ||
        geometry.radius <= geometry.innerRadius ||
        geometry.ringWidth <= 0 ||
        geometry.sweepAngle <= 0 ||
        geometry.sweepAngle > 360 ||
        geometry.gap < 0 ||
        geometry.ringGap < 0) {
      throw ArgumentError('Invalid radial menu geometry.');
    }
    final ids = <String>{};
    final slots = <RayMenuSlot>[];
    for (var ring = 0; ring < rings.length; ring++) {
      final entries = rings[ring];
      var count = entries.slotCount;
      for (final item in entries.items) {
        if (!ids.add(item.id)) throw ArgumentError('Item ids must be unique.');
        count = math.max(count, item.slot + 1);
      }
      if (count <= 0) throw ArgumentError('Ring slotCount must be positive.');
      final bySlot = {for (final item in entries.items) item.slot: item};
      final inner = ring == 0
          ? geometry.innerRadius
          : geometry.radius + (ring - 1) * geometry.ringWidth;
      final outer = geometry.radius + ring * geometry.ringWidth;
      final sweep = geometry.sweepAngle / count * math.pi / 180;
      for (var index = 0; index < count; index++) {
        slots.add(
          RayMenuSlot(
            ring: ring,
            index: index,
            item: bySlot[index],
            innerRadius: inner,
            outerRadius: outer,
            angle: geometry.startAngle * math.pi / 180 + index * sweep,
            sweep: sweep,
            geometry: geometry,
          ),
        );
      }
    }
    this.slots = List.unmodifiable(slots);
    ringCount = rings.length;
  }

  final RayMenuGeometry geometry;
  late final List<RayMenuSlot> slots;
  late final int ringCount;
  double get outerRadius => ringCount == 0
      ? geometry.radius
      : geometry.radius + (ringCount - 1) * geometry.ringWidth;

  RayMenuSlot? hitTest(
    Offset offset, {
    int? visibleRings,
    bool includeEmpty = false,
  }) {
    for (final slot in slots) {
      if (slot.ring >= (visibleRings ?? ringCount)) break;
      if ((slot.selectable || includeEmpty) && slot.path.contains(offset))
        return slot;
    }
    return null;
  }
}

@immutable
class RayMenuPlacement {
  const RayMenuPlacement({required this.center, required this.scale});

  factory RayMenuPlacement.fit({
    required Size size,
    required double radius,
    Offset? center,
    double padding = 8,
  }) {
    final available = math.max(0.0, size.shortestSide - 2 * padding);
    final scale = math.min(1.0, available / (2 * radius));
    final extent = radius * scale;
    final desired = center ?? size.center(Offset.zero);
    final xMargin = math.min(size.width / 2, extent + padding);
    final yMargin = math.min(size.height / 2, extent + padding);
    return RayMenuPlacement(
      center: Offset(
        desired.dx.clamp(xMargin, size.width - xMargin),
        desired.dy.clamp(yMargin, size.height - yMargin),
      ),
      scale: scale,
    );
  }

  final Offset center;
  final double scale;
  Offset toMenu(Offset local) => scale == 0
      ? const Offset(double.infinity, double.infinity)
      : (local - center) / scale;
  Offset toLocal(Offset menu) => center + menu * scale;
}
