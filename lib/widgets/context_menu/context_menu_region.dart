/// 右键 / 长按菜单的**手势宿主**。
///
/// 全仓原来有三种写法（`ShelfEntryContextMenuRegion`、文件管理器条目那份、
/// 以及 `collapsible_card.dart` 里为了绕开 `TextField`/`InkWell` 抢次键而写的
/// `Listener` 版本）。这里收成一份，三档行为由参数选择：
///
/// - 普通（默认）：`GestureDetector.onSecondaryTapUp` + `onLongPressStart`；
/// - [robustSecondaryTap]：外面再套一层 `Listener` 直接观测次键，子控件在
///   手势竞技场里赢走次键时仍能弹（照搬 `_HeaderlessContextMenuRegion`）；
/// - [enableLongPress] = false：宿主整块被 `LongPressDraggable` 包住时用。
///
/// **不按平台分叉**：`defaultTargetPlatform` 说 desktop、用户却用触控笔长按的
/// 「带触摸屏的桌面」上，分叉会让菜单永远出不来。桌面长按弹菜单无害。
library;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.onOpen,
    this.enabled = true,
    this.enableLongPress = true,
    this.behavior = HitTestBehavior.deferToChild,
    this.robustSecondaryTap = false,
    this.hapticOnLongPress = false,
  });

  final Widget child;

  /// 菜单该弹的那一刻调用（右键 / 长按 / 次键抬起）。
  final void Function(BuildContext context, Offset globalPosition) onOpen;

  /// 全局开关关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得"有反应"，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  final bool enableLongPress;

  final HitTestBehavior behavior;

  /// 子控件（`TextField` / `InkWell` / 滚动视图）会抢走次键时打开。
  final bool robustSecondaryTap;

  /// 长按弹菜单时给一次轻震动（移动端体感）。
  final bool hapticOnLongPress;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  Offset? _secondaryDownPosition;
  DateTime? _lastOpenedAt;

  void _open(Offset globalPosition) {
    final now = DateTime.now();
    if (_lastOpenedAt != null &&
        now.difference(_lastOpenedAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastOpenedAt = now;
    widget.onOpen(context, globalPosition);
  }

  void _openFromLongPress(Offset globalPosition) {
    if (widget.hapticOnLongPress) {
      HapticFeedback.selectionClick();
    }
    _open(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final gestures = GestureDetector(
      behavior: widget.behavior,
      onSecondaryTapUp: (details) => _open(details.globalPosition),
      onLongPressStart: widget.enableLongPress
          ? (details) => _openFromLongPress(details.globalPosition)
          : null,
      child: widget.child,
    );

    if (!widget.robustSecondaryTap) return gestures;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          _secondaryDownPosition = event.position;
        } else {
          _secondaryDownPosition = null;
        }
      },
      onPointerUp: (event) {
        final down = _secondaryDownPosition;
        _secondaryDownPosition = null;
        if (down != null && (event.position - down).distance <= kTouchSlop) {
          _open(event.position);
        }
      },
      onPointerCancel: (_) => _secondaryDownPosition = null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _open(details.globalPosition),
        onLongPressStart: widget.enableLongPress
            ? (details) => _openFromLongPress(details.globalPosition)
            : null,
        child: widget.child,
      ),
    );
  }
}
