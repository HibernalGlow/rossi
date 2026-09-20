import 'package:flutter/widgets.dart';
import 'ray_menu.dart';
import 'ray_menu_geometry.dart';
import 'ray_menu_models.dart';

class RayMenuHandle {
  RayMenuHandle._();
  final controller = RayMenuController();
  OverlayEntry? _entry;
  bool get isOpen => _entry != null;

  void close() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
    controller.dispose();
  }
}

/// Inserts a menu above the app. Selection closes it before invoking the host.
/// The host should call handle.close() when the owning page is disposed.
RayMenuHandle showRayMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<RayMenuRing> rings,
  required ValueChanged<RayMenuItem> onSelected,
  RayMenuGeometry geometry = const RayMenuGeometry(),
  RayMenuStyle style = const RayMenuStyle(),
  RayMenuExpansion expansion = RayMenuExpansion.all,
  int? openingPointer,
  String centerLabel = '',
  String cancelLabel = 'Cancel',
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final handle = RayMenuHandle._();
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  handle._entry = OverlayEntry(
    builder: (context) {
      final box = overlay.context.findRenderObject()! as RenderBox;
      return themes.wrap(
        RayMenu(
          controller: handle.controller,
          rings: rings,
          geometry: geometry,
          style: style,
          expansion: expansion,
          center: box.globalToLocal(globalPosition),
          openingPointer: openingPointer,
          openingPosition: globalPosition,
          centerLabel: centerLabel,
          cancelLabel: cancelLabel,
          onDismiss: handle.close,
          onSelected: (item) {
            handle.close();
            onSelected(item);
          },
        ),
      );
    },
  );
  overlay.insert(handle._entry!);
  return handle;
}
