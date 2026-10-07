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

/// 轮盘的 MD3 取色。按 M3「菜单」这一档来对：容器用 `surfaceContainer`，格子上浮一档
/// 用 `surfaceContainerHigh`，指针下那一格是**选中态**而不是「描个边」——
/// `secondaryContainer` 填充 + `onSecondaryContainer` 文字（M3 里 primary 留给按钮，
/// 菜单/列表的选中一律 secondary 系）。整张盘靠投影与色差分层，不再画一圈圈描边。
RayMenuStyle readerRayStyle(BuildContext context, {bool embedded = false}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return RayMenuStyle(
    surface: colors.surfaceContainer,
    segment: colors.surfaceContainerHigh,
    border: colors.outlineVariant,
    foreground: colors.onSurface,
    muted: colors.onSurfaceVariant,
    selected: colors.secondaryContainer,
    selectedForeground: colors.onSecondaryContainer,
    shadow: embedded ? null : colors.shadow.withValues(alpha: 0.28),
    scrim: embedded ? Colors.transparent : colors.scrim.withValues(alpha: 0.16),
    // 字号只能自己写：这一版 Flutter 的 `textTheme` token 只带颜色与字族，
    // `labelLarge?.fontSize` 实测是 null —— 直接沿用 token 会掉回环境默认字号，
    // 「按 MD3 排版」就成了空话。这里取 M3 的 labelMedium（12sp / w500）。
    textStyle: (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );
}
