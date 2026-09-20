// 阅读轮盘：flutter_ray_menu 管理多层显示与指针命中，条目继续经过统一动作绑定解析器。

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/reader_ray_menu_adapter.dart';

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
    int? openingPointer,
  }) {
    dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _ReaderRadialMenuView(
        openingPointer: openingPointer,
        globalCenter: globalCenter,
        configJson: configJson,
        bindingsArrayJson: bindingsArrayJson,
        dispatcher: dispatcher,
        onClose: () {
          if (identical(_entry, entry)) dismiss();
        },
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  static bool confirm() {
    if (!isOpen || _current == null) return false;
    _current!._controller.confirm();
    return true;
  }

  static void dismiss() {
    final entry = _entry;
    _entry = null;
    _current = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }
}

class _ReaderRadialMenuView extends StatefulWidget {
  const _ReaderRadialMenuView({
    this.openingPointer,
    required this.globalCenter,
    required this.configJson,
    required this.bindingsArrayJson,
    required this.dispatcher,
    required this.onClose,
  });

  final int? openingPointer;
  final Offset globalCenter;
  final String configJson;
  final String bindingsArrayJson;
  final ReaderActionDispatcher dispatcher;
  final VoidCallback onClose;

  @override
  State<_ReaderRadialMenuView> createState() => _ReaderRadialMenuViewState();
}

class _ReaderRadialMenuViewState extends State<_ReaderRadialMenuView> {
  final _focusNode = FocusNode(debugLabel: 'Reader radial menu');
  final _controller = RayMenuController();
  late RadialDoc _doc;
  String _menuId = '';
  late List<RadialSlotPaint> _slots;
  late List<RayMenuRing> _rings;

  @override
  void initState() {
    super.initState();
    _doc = parseRadialDoc(widget.configJson) ?? RadialDoc({});
    _reload();
    ReaderRadialMenu._current = this;

    // 根 Overlay 与阅读器共享焦点作用域；已有焦点时 autofocus 不会抢占。
    // 请求在节点挂载后生效，移除时由焦点历史恢复阅读器。
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    if (identical(ReaderRadialMenu._current, this)) {
      ReaderRadialMenu._current = null;
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reload() {
    final menu = _doc.menu(_menuId) ?? _doc.activeMenu;
    _menuId = menu?.id ?? '';
    _slots = OperationBindingStore.radialLayout(
      configJson: _doc.encode(),
      menuId: _menuId,
    );
    _rings = readerRayRings(_slots);
  }

  void _commit(RadialSlotPaint slot) {
    final moveTo = slot.moveToMenuId;
    if (moveTo != null && _doc.menu(moveTo) != null) {
      setState(() {
        _menuId = moveTo;
        _reload();
      });
      return;
    }
    widget.onClose();
    final handled = widget.dispatcher.dispatchInput(
      radialInputJson(menuId: slot.menuId, itemId: slot.itemId!),
      widget.bindingsArrayJson,
      fromKeyboard: false,
    );
    if (!handled && slot.legacyAction != null) {
      widget.dispatcher.dispatch(slot.legacyAction!, fromKeyboard: false);
    }
  }

  // ── 键盘 ───────────────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _controller.moveSelection(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _controller.moveRing(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    final inputJson = keyboardInputJsonOf(event);
    final binding = inputJson == null
        ? null
        : OperationBindingStore.resolveBinding(
            bindingsArrayJson: widget.bindingsArrayJson,
            inputJson: inputJson,
          );
    if (binding != null &&
        (binding['action'] == BindingAction.confirmRadialMenu ||
            binding['action'] == BindingAction.openRadialMenu)) {
      dispatchBindingActions(
        binding,
        execute: (action) {
          // 已打开时再次按唤出键（Neo 默认 Enter）也确认当前槽。
          if (action == BindingAction.openRadialMenu) {
            return ReaderRadialMenu.confirm();
          }
          return widget.dispatcher.dispatch(action, fromKeyboard: true);
        },
      );
    }
    // 轮盘开着时别的键不该溜到阅读器里去（否则「开着轮盘又翻了页」）。
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = context.findRenderObject()! as RenderBox;
          return RayMenu(
            controller: _controller,
            rings: _rings,
            center: box.globalToLocal(widget.globalCenter),
            openingPointer: widget.openingPointer,
            openingPosition: widget.globalCenter,
            geometry: readerRayGeometry(_doc),
            style: readerRayStyle(context),
            centerLabel: t.reader.radialMenuHintMove,
            cancelLabel: t.common.cancel,
            keyboardEnabled: false,
            onSelected: (item) =>
                _commit(_slots.firstWhere((slot) => slot.itemId == item.id)),
            onDismiss: widget.onClose,
          );
        },
      ),
    );
  }
}
