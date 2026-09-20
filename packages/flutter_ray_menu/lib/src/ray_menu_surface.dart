import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'ray_menu_geometry.dart';
import 'ray_menu_models.dart';

class RayMenuSurface extends StatelessWidget {
  const RayMenuSurface({
    super.key,
    required this.layout,
    required this.placement,
    required this.style,
    required this.visibleRings,
    required this.selected,
    required this.centerLabel,
    required this.cancelLabel,
    required this.editEmpty,
    required this.onSelected,
  });
  final RayMenuLayout layout;
  final RayMenuPlacement placement;
  final RayMenuStyle style;
  final int visibleRings;
  final RayMenuSlot? selected;
  final String centerLabel;
  final String cancelLabel;
  final bool editEmpty;
  final ValueChanged<RayMenuSlot> onSelected;

  @override
  Widget build(BuildContext context) {
    final radius = layout.outerRadius;
    final slots = layout.slots.where((slot) => slot.ring < visibleRings);
    final centerDiameter = math.max(0.0, layout.geometry.innerRadius * 2 - 12);
    return ColoredBox(
      color: style.scrim,
      child: Stack(
        children: [
          Positioned(
            left: placement.center.dx - radius * placement.scale,
            top: placement.center.dy - radius * placement.scale,
            width: radius * 2 * placement.scale,
            height: radius * 2 * placement.scale,
            child: FittedBox(
              child: SizedBox.square(
                dimension: radius * 2,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RayPainter(
                          layout,
                          style,
                          visibleRings,
                          selected,
                        ),
                      ),
                    ),
                    for (final slot in slots)
                      if (slot.item != null || editEmpty)
                        Positioned(
                          left:
                              radius +
                              slot.labelCenter.dx -
                              slot.labelSize.width / 2,
                          top:
                              radius +
                              slot.labelCenter.dy -
                              slot.labelSize.height / 2,
                          width: slot.labelSize.width,
                          height: slot.labelSize.height,
                          child: Semantics(
                            key: ValueKey(
                              slot.item == null
                                  ? 'ray-empty:${slot.ring}:${slot.index}'
                                  : 'ray-item:${slot.item!.id}',
                            ),
                            label: slot.item?.label ?? '+',
                            button: true,
                            enabled:
                                slot.selectable ||
                                (slot.item == null && editEmpty),
                            selected: selected == slot,
                            onTap:
                                slot.selectable ||
                                    (slot.item == null && editEmpty)
                                ? () => onSelected(slot)
                                : null,
                            child: ExcludeSemantics(
                              child: _RayLabel(
                                slot: slot,
                                style: style,
                                selected: selected == slot,
                              ),
                            ),
                          ),
                        ),
                    if (centerDiameter > 0)
                      Positioned(
                        left: radius - centerDiameter / 2,
                        top: radius - centerDiameter / 2,
                        width: centerDiameter,
                        height: centerDiameter,
                        child: Center(
                          child: Text(
                            selected?.item?.label ?? centerLabel,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: style.textStyle.copyWith(
                              color: selected == null
                                  ? style.muted
                                  : style.foreground,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RayLabel extends StatelessWidget {
  const _RayLabel({
    required this.slot,
    required this.style,
    required this.selected,
  });
  final RayMenuSlot slot;
  final RayMenuStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = slot.selectable
        ? (selected ? style.accent : style.foreground)
        : style.muted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slot.item?.icon != null && slot.labelSize.height >= 38)
              IconTheme(
                data: IconThemeData(size: 16, color: color),
                child: slot.item!.icon!,
              ),
            Flexible(
              child: Text(
                slot.item?.label ?? '+',
                textAlign: TextAlign.center,
                maxLines: slot.item?.icon == null ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: style.textStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RayPainter extends CustomPainter {
  _RayPainter(this.layout, this.style, this.visibleRings, this.selected);
  final RayMenuLayout layout;
  final RayMenuStyle style;
  final int visibleRings;
  final RayMenuSlot? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    for (final slot in layout.slots) {
      if (slot.ring >= visibleRings) break;
      final active = slot == selected;
      canvas.drawPath(
        slot.path,
        Paint()
          ..color = active
              ? style.selected
              : slot.item == null
              ? style.surface.withValues(alpha: 0.4)
              : slot.selectable
              ? style.segment
              : style.segment.withValues(alpha: 0.45),
      );
      canvas.drawPath(
        slot.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.5 : 0.75
          ..color = active ? style.accent : style.border,
      );
    }
    if (layout.geometry.innerRadius > 2) {
      canvas.drawCircle(
        Offset.zero,
        layout.geometry.innerRadius - 2,
        Paint()..color = style.surface,
      );
      canvas.drawCircle(
        Offset.zero,
        layout.geometry.innerRadius - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = style.border,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RayPainter old) =>
      layout != old.layout ||
      style != old.style ||
      visibleRings != old.visibleRings ||
      selected != old.selected;
}

/// Standard widgets expose actions when assistive navigation cannot use a wheel.
class RayMenuAccessibleList extends StatelessWidget {
  const RayMenuAccessibleList({
    super.key,
    required this.layout,
    required this.style,
    required this.selected,
    required this.cancelLabel,
    required this.onSelected,
    required this.onDismiss,
  });
  final RayMenuLayout layout;
  final RayMenuStyle style;
  final RayMenuSlot? selected;
  final String cancelLabel;
  final ValueChanged<RayMenuSlot> onSelected;
  final VoidCallback onDismiss;

  Widget _button(String label, VoidCallback? action, {bool selected = false}) =>
      Semantics(
        button: true,
        enabled: action != null,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: action,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              label,
              style: style.textStyle.copyWith(
                fontSize: 16,
                color: action == null ? style.muted : style.foreground,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: style.surface,
    child: ListView(
      children: [
        _button(cancelLabel, onDismiss),
        for (final slot in layout.slots)
          if (slot.item != null)
            _button(
              slot.item!.label,
              slot.selectable ? () => onSelected(slot) : null,
              selected: slot == selected,
            ),
      ],
    ),
  );
}
