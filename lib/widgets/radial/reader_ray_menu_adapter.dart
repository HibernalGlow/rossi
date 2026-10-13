import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/radial_action_icons.dart';

/// 阅读器文档适配仅留在应用内；flutter_ray_menu 不依赖 Rust、绑定表和本地化。
List<RayMenuRing> readerRayRings(
  List<RadialSlotPaint> slots, {
  bool editing = false,
  RadialDoc? doc,
  List<Map<String, dynamic>> bindings = const [],
  Map<String, dynamic>? Function(RadialSlotRef slot)? resolveBinding,
}) {
  final levels = slots.map((slot) => slot.level).toSet().toList()..sort();
  Widget iconFor(RadialSlotPaint slot) {
    final ref = slot.slot!;
    final binding = resolveBinding != null
        ? resolveBinding(ref)
        : bindings.where((row) => slotOfBinding(row) == ref).firstOrNull;
    return radialActionIcon(
      item: doc?.menu(slot.menuId)?.item(slot.itemId!),
      action: binding?['action'] as String? ?? slot.legacyAction,
      menuJump: slot.moveToMenuId != null,
      chained: (binding?['followUpActions'] as List? ?? const []).isNotEmpty,
    );
  }

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
                icon: iconFor(slot),
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

/// 轮盘的 MD3 取色。蜂窝按钮用 `surfaceContainerHigh` 独立表面，
/// 指针下的按钮用 `secondaryContainer` / `onSecondaryContainer` 表达选中。
/// 阅读浮层保留轻遮罩，嵌入编辑器时透明；不再绘制整块圆盘底板。
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
