import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:zephyr/widgets/radial/radial_focus_surface.dart';

/// flutter_ray_menu 的展示适配，确认、取消和键盘仍走原控制器。
class ExpressiveRayMenu extends StatefulWidget {
  const ExpressiveRayMenu({
    super.key,
    required this.rings,
    required this.geometry,
    required this.style,
    required this.onSelected,
    required this.onDismiss,
    this.controller,
    this.center,
    this.openingPointer,
    this.openingPosition,
    this.keyboardEnabled = true,
    this.centerLabel = '',
    this.cancelLabel = '',
    this.onEmptySelected,
  });

  final List<RayMenuRing> rings;
  final RayMenuGeometry geometry;
  final RayMenuStyle style;
  final ValueChanged<RayMenuItem> onSelected;
  final VoidCallback onDismiss;
  final RayMenuController? controller;
  final Offset? center;
  final int? openingPointer;
  final Offset? openingPosition;
  final bool keyboardEnabled;
  final String centerLabel;
  final String cancelLabel;
  final void Function(int ring, int slot)? onEmptySelected;

  @override
  State<ExpressiveRayMenu> createState() => _ExpressiveRayMenuState();
}

class _ExpressiveRayMenuState extends State<ExpressiveRayMenu> {
  final _surface = GlobalKey<RadialFocusSurfaceState>();
  @override
  Widget build(BuildContext context) => RayMenu(
    rings: widget.rings,
    geometry: widget.geometry,
    style: widget.style,
    controller: widget.controller,
    center: widget.center,
    openingPointer: widget.openingPointer,
    openingPosition: widget.openingPosition,
    keyboardEnabled: widget.keyboardEnabled,
    centerLabel: widget.centerLabel,
    cancelLabel: widget.cancelLabel,
    onSelected: (item) {
      HapticFeedback.lightImpact();
      widget.onSelected(item);
    },
    onDismiss: widget.onDismiss,
    onEmptySelected: widget.onEmptySelected == null
        ? null
        : (ring, slot) {
            HapticFeedback.lightImpact();
            widget.onEmptySelected!(ring, slot);
          },
    animate: false,
    surfaceBuilder: (context, data) =>
        RadialFocusSurface(key: _surface, data: data),
    visualHitTest: (point) => _surface.currentState?.hitTest(point),
    onPointerPosition: (point, event) =>
        _surface.currentState?.observe(point, event),
  );
}
