import 'package:flutter/widgets.dart';
import 'package:flutter_ray_menu/src/ray_menu_geometry.dart';
import 'package:flutter_ray_menu/src/ray_menu_models.dart';

/// 宿主只替换展示与变形后的命中区，指针生命周期和键盘导航仍由 RayMenu 维护。
class RayMenuPresentation {
  const RayMenuPresentation({
    required this.layout,
    required this.placement,
    required this.size,
    required this.style,
    required this.visibleRings,
    required this.selected,
    required this.centerLabel,
    required this.editEmpty,
    required this.onSelected,
  });

  final RayMenuLayout layout;
  final RayMenuPlacement placement;
  final Size size;
  final RayMenuStyle style;
  final int visibleRings;
  final RayMenuSlot? selected;
  final String centerLabel;
  final bool editEmpty;
  final ValueChanged<RayMenuSlot> onSelected;
}

typedef RayMenuSurfaceBuilder =
    Widget Function(BuildContext context, RayMenuPresentation presentation);
typedef RayMenuVisualHitTest = RayMenuSlot? Function(Offset localPosition);
typedef RayMenuPointerObserver =
    void Function(Offset localPosition, PointerEvent event);
