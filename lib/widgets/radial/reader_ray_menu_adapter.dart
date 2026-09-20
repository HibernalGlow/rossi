import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';

/// 阅读器文档适配仅留在应用内；flutter_ray_menu 不依赖 Rust、绑定表和本地化。
List<RayMenuRing> readerRayRings(
  List<RadialSlotPaint> slots, {
  bool editing = false,
}) {
  final levels = slots.map((slot) => slot.level).toSet().toList()..sort();
  return [
    for (final level in levels)
      RayMenuRing(
        slotCount: slots.where((slot) => slot.level == level).length,
        items: [
          for (final slot in slots.where((slot) => slot.level == level))
            if (slot.itemId != null)
              RayMenuItem(
                id: slot.itemId!,
                label: slot.label ?? slot.itemId!,
                slot: slot.index,
                enabled: editing || (slot.selectable && !slot.disabled),
              ),
        ],
      ),
  ];
}

RayMenuGeometry readerRayGeometry(RadialDoc doc) => RayMenuGeometry(
  radius: doc.radius,
  innerRadius: doc.innerRadius,
  startAngle: doc.startAngle,
  sweepAngle: doc.sweepAngle,
  variant: doc.variant == 'bubble'
      ? RayMenuVariant.bubble
      : RayMenuVariant.slice,
);

RayMenuStyle readerRayStyle(BuildContext context, {bool embedded = false}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return RayMenuStyle(
    surface: colors.surfaceContainerHigh,
    segment: colors.surfaceContainerHighest,
    border: colors.outlineVariant,
    foreground: colors.onSurface,
    muted: colors.onSurfaceVariant,
    accent: colors.primary,
    selected: colors.primaryContainer,
    scrim: embedded ? Colors.transparent : colors.scrim.withValues(alpha: 0.24),
    textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
  );
}
