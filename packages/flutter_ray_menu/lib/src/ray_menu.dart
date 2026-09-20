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
  ///
  /// 宿主转交与 [RayMenu.openingPointer] 的全局路由可以同时存在：一次抬起被两条路
  /// 都送到时只会确认一次，动作不会执行两遍。
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
///
/// ## 指针手感（与 neoview 同一口径）
///
/// - **按下即开**：轮盘在指针按下的那一刻就被插进 Overlay，所以它的整个生命周期里
///   「按下」只可能是**新的一次**按下（唤出那一次在它挂载之前就发生了）。
/// - 按住拖动：高亮跟着指针走；**在某一格上松手就执行那一格**；松在中心空洞里 = 取消。
/// - 按下就松、中间没动过：那是「开出来」而不是「想取消」，**不执行也不关**。
/// - 轮盘开着时**再按一次右键 = 关掉**。
/// - 唤出那次手势的 move/up/cancel 有两条来路：本组件用 [RayMenu.openingPointer]
///   注册的全局路由，以及宿主用 [RayMenuController.handlePointerEvent] 的转交。
///   宿主在按下时的命中路径上（阅读器就是这样），比全局路由更稳 —— 全局路由要等
///   本组件挂载之后才注册，按下与抬起挨得极近时那一次抬起会漏掉。
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

  /// 这次手势是否已经「用掉」（确认过、取消过，或判定为「按下即松」）。
  ///
  /// 抬起可能从两条路进来 —— 组件的全局路由与宿主转交（
  /// [RayMenuController.handlePointerEvent]）—— 没有这个闩，同一个动作会执行两遍。
  var _confirmed = false;
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
    // 只有登记过才撤：`dispose` 与「抬起」都会走到这里，第二次撤会撞上
    // `PointerRouter.removeGlobalRoute` 的断言（它要求路由还在表里）。
    if (_openingPointer == null) return;
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
      // 这根指针这次手势就此结束：宿主转交进来同一个抬起时不该再确认一遍。
      _hold?.cancel();
      _activePointer = null;
      _confirmed = true;
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
      // 新的一次按下 = 「这一轮交互现在归这根指针」。同 id 要能重新接管：上一轮
      // 有可能整段都没被我们看见（抬起早于浮层挂载），那时 `_activePointer` 会一直
      // 挂着一根已经不存在的指针，把后面所有输入都挡掉。不同 id 的多指按下忽略。
      if (_activePointer != null && _activePointer != event.pointer) return;
      _activePointer = event.pointer;
      // 「再按一次右键」= 关掉它。宿主只把**新的**按下送到这里（唤出那一次按下是
      // 浮层挂载之前发生的，到不了浮层），所以这里看到的按下一定是「再来一次」。
      // 已经用掉的这次手势不能再确认，否则会在关掉之后又执行一次指针下的那一格。
      if (event.buttons & kSecondaryButton != 0) {
        _confirmed = true;
        widget.onDismiss();
        return;
      }
      _confirmed = false;
      _startHold();
    } else if (event is! PointerHoverEvent && event.pointer != _activePointer) {
      // 没有认领过的指针也要接下：宿主拥有指针路由时会用
      // [RayMenuController.handlePointerEvent] 把唤出那次手势转交进来，而那条路
      // 不一定带 `openingPointer`。丢掉它 = 「拖到某一格松手什么也不发生」。
      if (_activePointer != null) return;
      _activePointer = event.pointer;
    }
    if (event is PointerCancelEvent) {
      _hold?.cancel();
      _activePointer = null;
      _confirmed = true;
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
      // 同一次手势的抬起只确认一次：全局路由与宿主转交是两条并行的路，
      // 都送到这里时不能把同一个动作执行两遍。
      if (_confirmed) return;
      _confirmed = true;
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
