import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'ray_menu_geometry.dart';
import 'ray_menu_models.dart';
import 'ray_menu_surface.dart';

/// Controls a single mounted menu. The owner disposes this controller.
class RayMenuController extends ChangeNotifier {
  RayMenuState? _state;
  RayMenuItem? get selectedItem => _state?._selected?.item;
  int? get selectedRing => _state?._selected?.ring;
  void moveSelection(int step) => _state?._moveSelection(step);
  void moveRing(int step) => _state?._moveRing(step);
  void confirm() => _state?._confirm();
  void dismiss() => _state?.widget.onDismiss();
  void expand() => _state?._expand();

  /// Forward an existing pointer when the host owns pointer routing.
  /// Prefer [RayMenu.openingPointer] for overlays opened during pointer-down.
  void handlePointerEvent(PointerEvent event) => _state?._handlePointer(event);

  void _attach(RayMenuState state) {
    if (_state != null && _state != state) {
      throw StateError('A RayMenuController cannot control two menus.');
    }
    _state = state;
  }

  void _changed() => notifyListeners();

  @override
  void dispose() {
    _state = null;
    super.dispose();
  }
}

/// An already-open radial menu filling a bounded parent.
///
/// All rings are visible by default. Selection is controlled: [onSelected]
/// decides whether to remove the menu or replace [rings] for a menu jump.
class RayMenu extends StatefulWidget {
  const RayMenu({
    super.key,
    required this.rings,
    required this.onSelected,
    required this.onDismiss,
    this.controller,
    this.geometry = const RayMenuGeometry(),
    this.style = const RayMenuStyle(),
    this.center,
    this.openingPointer,
    this.openingPosition,
    this.expansion = RayMenuExpansion.all,
    this.holdDuration = const Duration(milliseconds: 350),
    this.keyboardEnabled = true,
    this.confirmKeys = const [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
    ],
    this.centerLabel = '',
    this.cancelLabel = 'Cancel',
    this.onEmptySelected,
  });

  final List<RayMenuRing> rings;
  final ValueChanged<RayMenuItem> onSelected;
  final VoidCallback onDismiss;
  final RayMenuController? controller;
  final RayMenuGeometry geometry;
  final RayMenuStyle style;

  /// Center in the menu's local coordinate system. Defaults to the center.
  final Offset? center;

  /// The pointer that opened this overlay before the overlay was mounted.
  final int? openingPointer;
  final Offset? openingPosition;
  final RayMenuExpansion expansion;
  final Duration holdDuration;
  final bool keyboardEnabled;
  final Iterable<LogicalKeyboardKey> confirmKeys;
  final String centerLabel;
  final String cancelLabel;

  /// Optional editor mode. Empty sectors become accessible add-item targets.
  final void Function(int ring, int slot)? onEmptySelected;

  @override
  State<RayMenu> createState() => RayMenuState();
}

class RayMenuState extends State<RayMenu> with SingleTickerProviderStateMixin {
  late RayMenuLayout _layout;
  RayMenuPlacement _placement = const RayMenuPlacement(
    center: Offset.zero,
    scale: 1,
  );
  RayMenuSlot? _selected;
  final _focusNode = FocusNode(debugLabel: 'Ray menu');
  late final _animation = AnimationController(
    vsync: this,
    duration: widget.style.animationDuration,
  );
  late final _opacity = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
  );
  Timer? _hold;
  int? _openingPointer;
  int? _activePointer;
  Offset? _openingPosition;
  var _openingMoved = false;
  var _expanded = false;
  var _keyboardRing = 0;

  int get _visibleRings => widget.expansion == RayMenuExpansion.all || _expanded
      ? _layout.ringCount
      : 1;

  @override
  void initState() {
    super.initState();
    _rebuildLayout();
    widget.controller?._attach(this);
    _openingPointer = widget.openingPointer;
    _openingPosition = widget.openingPosition;
    _activePointer = _openingPointer;
    if (_openingPointer != null) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        _routeOpeningPointer,
      );
      _startHold();
    }
    if (widget.keyboardEnabled) _focusNode.requestFocus();
    _animation.forward();
  }

  void _rebuildLayout() {
    _layout = RayMenuLayout(rings: widget.rings, geometry: widget.geometry);
    _selected = null;
    _keyboardRing = 0;
  }

  @override
  void didUpdateWidget(RayMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this)
        oldWidget.controller?._state = null;
      widget.controller?._attach(this);
    }
    if (oldWidget.rings != widget.rings ||
        oldWidget.geometry != widget.geometry) {
      _hold?.cancel();
      _rebuildLayout();
    }
    if (oldWidget.expansion != widget.expansion) {
      _expanded = false;
      _selected = null;
      _hold?.cancel();
    }
  }

  void _startHold() {
    _hold?.cancel();
    if (widget.expansion == RayMenuExpansion.onHold && !_expanded) {
      _hold = Timer(widget.holdDuration, _expand);
    }
  }

  void _expand() {
    if (!mounted || _expanded) return;
    setState(() => _expanded = true);
  }

  void _unrouteOpeningPointer() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _routeOpeningPointer,
    );
    _openingPointer = null;
  }

  void _routeOpeningPointer(PointerEvent event) {
    if (event.pointer != _openingPointer) return;
    if (event is PointerMoveEvent &&
        _openingPosition != null &&
        (event.position - _openingPosition!).distance >= kTouchSlop) {
      _openingMoved = true;
    }
    if (event is PointerUpEvent && !_openingMoved) {
      // A quick right-click opens the menu, even if edge fitting shifted it.
      _hold?.cancel();
      _activePointer = null;
      _unrouteOpeningPointer();
      return;
    }
    _handlePointer(event);
    if (event is PointerUpEvent || event is PointerCancelEvent)
      _unrouteOpeningPointer();
  }

  void _handlePointer(PointerEvent event) {
    if (!mounted) return;
    if (event is PointerDownEvent) {
      if (_activePointer != null) return;
      _activePointer = event.pointer;
      _startHold();
    } else if (event is! PointerHoverEvent && event.pointer != _activePointer) {
      return;
    }
    if (event is PointerCancelEvent) {
      _hold?.cancel();
      _activePointer = null;
      widget.onDismiss();
      return;
    }
    if (event is PointerHoverEvent ||
        event is PointerMoveEvent ||
        event is PointerDownEvent ||
        event is PointerUpEvent) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final local = box.globalToLocal(event.position);
      _select(
        _layout.hitTest(
          _placement.toMenu(local),
          visibleRings: _visibleRings,
          includeEmpty: widget.onEmptySelected != null,
        ),
      );
    }
    if (event is PointerUpEvent) {
      _hold?.cancel();
      _activePointer = null;
      _confirm();
    }
  }

  void _select(RayMenuSlot? slot) {
    if (slot == _selected) return;
    setState(() {
      _selected = slot;
      if (slot != null) _keyboardRing = slot.ring;
    });
    widget.controller?._changed();
  }

  List<RayMenuSlot> _ringSlots(int ring) => _layout.slots
      .where((slot) => slot.ring == ring && slot.selectable)
      .toList();

  void _moveSelection(int step) {
    var candidates = _ringSlots(_keyboardRing);
    if (candidates.isEmpty) {
      for (var ring = 0; ring < _visibleRings; ring++) {
        candidates = _ringSlots(ring);
        if (candidates.isNotEmpty) break;
      }
    }
    if (candidates.isEmpty) return;
    final selected = _selected;
    final current = selected == null ? -1 : candidates.indexOf(selected);
    final index = current < 0
        ? (step > 0 ? 0 : candidates.length - 1)
        : (current + step) % candidates.length;
    _select(candidates[index]);
  }

  void _moveRing(int step) {
    if (step > 0) _expand();
    for (
      var ring = _keyboardRing + step;
      ring >= 0 && ring < _visibleRings;
      ring += step
    ) {
      final candidates = _ringSlots(ring);
      if (candidates.isEmpty) continue;
      final currentIndex = _selected?.index;
      _select(
        candidates.where((slot) => slot.index == currentIndex).firstOrNull ??
            candidates.first,
      );
      return;
    }
  }

  void _confirm() {
    final slot = _selected;
    if (slot?.selectable == true) {
      widget.onSelected(slot!.item!);
    } else if (slot != null &&
        slot.item == null &&
        widget.onEmptySelected != null) {
      widget.onEmptySelected!(slot.ring, slot.index);
    } else {
      widget.onDismiss();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _moveRing(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
    } else if (event is KeyDownEvent && widget.confirmKeys.contains(key)) {
      _confirm();
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _hold?.cancel();
    _unrouteOpeningPointer();
    if (widget.controller?._state == this) widget.controller?._state = null;
    _focusNode.dispose();
    _opacity.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    final surface = accessible
        ? RayMenuAccessibleList(
            layout: _layout,
            style: widget.style,
            selected: _selected,
            cancelLabel: widget.cancelLabel,
            onDismiss: widget.onDismiss,
            onSelected: (slot) {
              _select(slot);
              _confirm();
            },
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              if (!constraints.hasBoundedWidth ||
                  !constraints.hasBoundedHeight) {
                throw FlutterError(
                  'RayMenu needs bounded width and height (use SizedBox or an Overlay).',
                );
              }
              // Reserve the full radius even in hold mode so expansion never shifts the target.
              _placement = RayMenuPlacement.fit(
                size: constraints.biggest,
                radius: _layout.outerRadius,
                center: widget.center,
              );
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _handlePointer,
                onPointerHover: _handlePointer,
                onPointerMove: _handlePointer,
                onPointerUp: _handlePointer,
                onPointerCancel: _handlePointer,
                child: RayMenuSurface(
                  layout: _layout,
                  placement: _placement,
                  style: widget.style,
                  visibleRings: _visibleRings,
                  selected: _selected,
                  centerLabel: widget.centerLabel,
                  cancelLabel: widget.cancelLabel,
                  editEmpty: widget.onEmptySelected != null,
                  onSelected: (slot) {
                    _select(slot);
                    _confirm();
                  },
                ),
              );
            },
          );
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.keyboardEnabled,
      onKeyEvent: widget.keyboardEnabled ? _onKey : null,
      child: FadeTransition(opacity: _opacity, child: surface),
    );
  }
}
