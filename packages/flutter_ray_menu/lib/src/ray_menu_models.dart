import 'package:flutter/widgets.dart';

/// Stable slot numbers preserve muscle memory when entries are removed.
@immutable
class RayMenuItem {
  const RayMenuItem({
    required this.id,
    required this.label,
    required this.slot,
    this.enabled = true,
    this.icon,
  }) : assert(slot >= 0);

  final String id;
  final String label;
  final int slot;
  final bool enabled;
  final Widget? icon;
}

@immutable
class RayMenuRing {
  RayMenuRing({required List<RayMenuItem> items, this.slotCount = 8})
    : assert(slotCount > 0),
      items = List.unmodifiable(items) {
    final slots = <int>{};
    for (final item in items) {
      if (item.slot < 0 || !slots.add(item.slot)) {
        throw ArgumentError('Ring slots must be non-negative and unique.');
      }
    }
  }

  final List<RayMenuItem> items;

  /// Minimum count; a larger item.slot extends the ring automatically.
  final int slotCount;
}

enum RayMenuVariant { slice, bubble }

/// [all] is NeoView's flat, immediately visible set of rings.
/// [onHold] reveals the outer rings after holding a pointer in the menu.
enum RayMenuExpansion { all, onHold }

@immutable
class RayMenuStyle {
  const RayMenuStyle({
    this.surface = const Color(0xF222252D),
    this.segment = const Color(0xE630343F),
    this.border = const Color(0x665E6575),
    this.foreground = const Color(0xFFF2F3F7),
    this.muted = const Color(0xFFADB4C3),
    this.accent = const Color(0xFF83AAFF),
    this.selected = const Color(0xFF344D79),
    this.scrim = const Color(0x24000000),
    this.textStyle = const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    this.animationDuration = const Duration(milliseconds: 150),
  });

  final Color surface;
  final Color segment;
  final Color border;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color selected;
  final Color scrim;
  final TextStyle textStyle;
  final Duration animationDuration;
}
