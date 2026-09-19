// 阅读时的**轮盘浮层**（neoview `ReaderRadialMenuOverlay` + `neoview-ray-menu` 的对应物）。
//
// 手感照 neoview：一条输入（出厂是**右键按下**与 `Enter`）开出轮盘 → 指针移动时高亮
// 跟随 → 松手在某一格上就执行那一格；松在中心空洞里 = 取消；`Esc` = 取消；
// 方向键在格间移动、`Space`/`Enter` 确认。刚开出不到 180ms 就松手且什么都没选中时
// **不关**（neoview 里那条 `_openedAt` 守卫的同一件事：手快的人不该被当成想取消）。
//
// ## 为什么这里没有「这一格是什么动作」的判断
//
// 浮层只做三件事：把落点交给核心问「哪一格」（[OperationBindingStore.radialSlotHit]）、
// 把那一格的 `radial` 输入交给**同一个解析器**问「什么动作」
// （[OperationBindingStore.resolveAction]）、把动作 id 交给执行体
// （[ReaderActionDispatcher.dispatch]）。轮盘因此与键盘、点击共用一张绑定表：
// 设置页改完不用重启，追加动作（`followUpActions`）也自动可用。
// 解析不到时才回落到条目上遗留的直连动作（[RadialSlotHit.legacyAction]）——
// 顺序与 neoview 的 `if (!dispatch(...) && legacyAction) execute(...)` 一致。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/radial_wheel_painter.dart';

/// 轮盘浮层的出入口（同一时刻只开一个）。
abstract final class ReaderRadialMenu {
  static OverlayEntry? _entry;
  static _ReaderRadialMenuViewState? _current;

  static bool get isOpen => _entry != null;

  /// 在 [globalCenter]（**全局**坐标）处开出轮盘。
  ///
  /// [configJson] 是轮盘文档（形状），[bindingsArrayJson] 是绑定表（条目的动作）。
  /// 两者分开传是刻意的：浮层不需要知道「谁绑了什么」，它只需要问引擎。
  static void show(
    BuildContext context, {
    required Offset globalCenter,
    required String configJson,
    required String bindingsArrayJson,
    required ReaderActionDispatcher dispatcher,
  }) {
    dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _ReaderRadialMenuView(
        globalCenter: globalCenter,
        configJson: configJson,
        bindingsArrayJson: bindingsArrayJson,
        dispatcher: dispatcher,
        onClose: () {
          if (entry.mounted) entry.remove();
          if (identical(_entry, entry)) _entry = null;
        },
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// 把一次「松手」转交给浮层，返回是否被消费。
  ///
  /// 存在的理由：Flutter 对**进行中的指针**复用按下时的命中结果，所以用「按下」开出
  /// 浮层的那次手势，其抬起事件到不了刚插入的浮层，而是回到阅读器。于是阅读器在
  /// 抬起处把它转交回来 —— 按住拖到某一格再松手，才是轮盘该有的手感。
  static bool commitAt(Offset globalPosition) =>
      _current?.commitAt(globalPosition) ?? false;

  static void dismiss() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _ReaderRadialMenuView extends StatefulWidget {
  const _ReaderRadialMenuView({
    required this.globalCenter,
    required this.configJson,
    required this.bindingsArrayJson,
    required this.dispatcher,
    required this.onClose,
  });

  final Offset globalCenter;
  final String configJson;
  final String bindingsArrayJson;
  final ReaderActionDispatcher dispatcher;
  final VoidCallback onClose;

  @override
  State<_ReaderRadialMenuView> createState() => _ReaderRadialMenuViewState();
}

class _ReaderRadialMenuViewState extends State<_ReaderRadialMenuView> {
  /// 与 neoview 的 `_openedAt` 守卫同一件事：刚开出来就松手、且什么都没选中，
  /// 那是「按得太快」而不是「想取消」。
  static const Duration _ignoreInstantRelease = Duration(milliseconds: 180);

  late RadialDoc _doc;
  String _menuId = '';
  var _slots = const <RadialSlotPaint>[];
  RadialSlotPaint? _hovered;
  DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _doc = parseRadialDoc(widget.configJson) ?? RadialDoc({});
    _reload();
    ReaderRadialMenu._current = this;
  }

  @override
  void dispose() {
    if (identical(ReaderRadialMenu._current, this)) {
      ReaderRadialMenu._current = null;
    }
    super.dispose();
  }

  /// 从核心取这一轮的画法。**标签也在里面**，所以浮层不需要自己查动作名 ——
  /// 「显示的文字」与「松手执行的动作」因此必然同一口径。
  void _reload() {
    final menu = _doc.menu(_menuId) ?? _doc.activeMenu;
    _menuId = menu?.id ?? '';
    _slots = OperationBindingStore.radialLayout(
      configJson: _doc.encode(),
      menuId: _menuId,
    );
  }

  double get _naturalRadius =>
      _slots.fold<double>(0, (max, slot) => slot.outerRadius > max ? slot.outerRadius : max);

  // ── 落点 → 槽 ──────────────────────────────────────────────────────────────

  RadialSlotHit? _hitAt(Offset globalPosition) => OperationBindingStore.radialSlotHit(
    configJson: _doc.encode(),
    menuId: _menuId,
    dx: globalPosition.dx - widget.globalCenter.dx,
    dy: globalPosition.dy - widget.globalCenter.dy,
  );

  void _onMove(PointerEvent event) {
    final hit = _hitAt(event.position);
    final next = hit == null
        ? null
        : _slots
              .where((slot) => slot.level == hit.level && slot.index == hit.index)
              .firstOrNull;
    if (next?.itemId == _hovered?.itemId && next?.level == _hovered?.level) return;
    setState(() => _hovered = next);
  }

  void _onUp(PointerUpEvent event) {
    _commit(_hitAt(event.position));
  }

  /// 供 [ReaderRadialMenu.commitAt] 转交那次「到不了的抬起」。
  bool commitAt(Offset globalPosition) {
    _commit(_hitAt(globalPosition));
    return true;
  }

  void _commit(RadialSlotHit? hit) {
    if (hit == null) {
      final instant = DateTime.now().difference(_openedAt) < _ignoreInstantRelease;
      if (instant) return;
      widget.onClose();
      return;
    }
    final moveTo = hit.moveToMenuId;
    if (moveTo != null && moveTo.isNotEmpty && _doc.menu(moveTo) != null) {
      // 「跳转轮盘」：原地换成目标轮盘，不关浮层（neoview 的 `ray-moveto` 同一手感）。
      // 只换本次会话里的显示，不写设置 —— 用户点一下不该顺手改掉他的默认轮盘。
      setState(() {
        _menuId = moveTo;
        _hovered = null;
        _openedAt = DateTime.now();
        _reload();
      });
      return;
    }
    final actionId =
        OperationBindingStore.resolveAction(
          bindingsArrayJson: widget.bindingsArrayJson,
          inputJson: radialInputJson(menuId: hit.menuId, itemId: hit.itemId),
        ) ??
        hit.legacyAction;
    // 先关掉再执行：动作可能推入路由（打开设置、全屏），浮层挡在后面会留下一层收不掉的遮罩。
    widget.onClose();
    if (actionId == null) return;
    widget.dispatcher.dispatch(actionId, fromKeyboard: false);
  }

  // ── 键盘 ───────────────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      _confirmHovered();
      return KeyEventResult.handled;
    }
    if (_moveCursor(key)) return KeyEventResult.handled;
    // 轮盘开着时别的键不该溜到阅读器里去（否则「开着轮盘又翻了页」）。
    return KeyEventResult.handled;
  }

  void _confirmHovered() {
    final hovered = _hovered;
    if (hovered == null) {
      widget.onClose();
      return;
    }
    _commit(
      RadialSlotHit(
        menuId: hovered.menuId,
        level: hovered.level,
        index: hovered.index,
        itemId: hovered.itemId ?? '',
        legacyAction: hovered.legacyAction,
        moveToMenuId: hovered.moveToMenuId,
      ),
    );
  }

  /// 方向键：左右在同一环里绕圈，上下换环（夹在最外层）。空格子也跳，
  /// 于是「按四下回到原点」而不会卡在一格空的上面。
  bool _moveCursor(LogicalKeyboardKey key) {
    if (_slots.isEmpty) return false;
    const left = [LogicalKeyboardKey.arrowLeft];
    const right = [LogicalKeyboardKey.arrowRight];
    const up = [LogicalKeyboardKey.arrowUp];
    const down = [LogicalKeyboardKey.arrowDown];
    if (![...left, ...right, ...up, ...down].contains(key)) return false;
    final current = _hovered;
    final levels = {_slots.map((slot) => slot.level).reduce((a, b) => a > b ? a : b)};
    final maxLevel = levels.first;
    var level = current?.level ?? 1;
    var index = current?.index ?? 0;
    if (key == LogicalKeyboardKey.arrowUp) {
      level = (level - 1).clamp(1, maxLevel);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      level = (level + 1).clamp(1, maxLevel);
    } else {
      final ring = _slots.where((slot) => slot.level == level).toList();
      if (ring.isEmpty) return true;
      final step = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      final start = index;
      for (var attempt = 0; attempt < ring.length; attempt++) {
        index = (index + step + ring.length) % ring.length;
        if (index == start && attempt > 0) break;
        final candidate = ring.firstWhere(
          (slot) => slot.index == index,
          orElse: () => ring.first,
        );
        if (candidate.selectable) {
          setState(() => _hovered = candidate);
          return true;
        }
      }
      return true;
    }
    final ring = _slots.where((slot) => slot.level == level).toList();
    if (ring.isEmpty) return true;
    final candidate = ring.firstWhere(
      (slot) => slot.index == index,
      orElse: () => ring.firstWhere((slot) => slot.selectable, orElse: () => ring.first),
    );
    setState(() => _hovered = candidate);
    return true;
  }

  // ── 版式 ───────────────────────────────────────────────────────────────────

  /// 中心空洞里的那句话（neoview 的 `Move to choose` / `Release to run` /
  /// `Release to switch wheel`）。
  String get _centerHint {
    final hovered = _hovered;
    if (hovered?.moveToMenuId != null) {
      return t.reader.radialMenuHintSwitch;
    }
    return hovered == null
        ? t.reader.radialMenuHintMove
        : t.reader.radialMenuHintRelease;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = MediaQuery.sizeOf(context);
    final scale = radialFitScale(box: box, radius: _naturalRadius);
    final diameter = _naturalRadius * scale * 2;
    // 贴边时把圆心往里挪，保证轮盘完整可见（neoview 的 `detectEdgeConstraints`）。
    final margin = diameter / 2 + 8;
    final center = Offset(
      widget.globalCenter.dx.clamp(margin, box.width - margin),
      widget.globalCenter.dy.clamp(margin, box.height - margin),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: (_) => widget.onClose(),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: colors.scrim.withValues(alpha: 0.24)),
            ),
            Positioned(
              left: center.dx - diameter / 2,
              top: center.dy - diameter / 2,
              width: diameter,
              height: diameter,
              child: CustomPaint(
                size: Size(diameter, diameter),
                painter: RadialWheelPainter(
                  slots: _slots,
                  colors: colors,
                  hoveredItem: _hovered?.itemId,
                  scale: scale,
                  centerLabel: _centerHint,
                  textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `Iterable.firstOrNull` 在本仓的 Flutter 上可用，但为了读起来直白这里显式引一次。
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
