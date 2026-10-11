import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

/// 阅读器内当前视频的控制条。每个阅读器单独登记，避免泳道之间串用播放器。
class ReaderVideoControls {
  const ReaderVideoControls({
    required this.owner,
    required this.isCurrent,
    required this.builder,
    required this.pinned,
    required this.visible,
    required this.panelsOpen,
  });

  final Object owner;
  final bool Function() isCurrent;
  final Widget Function(bool embedded, bool visible) builder;
  final bool pinned;
  final bool visible;
  final ValueListenable<bool> panelsOpen;
}

class ReaderVideoControlsSlot extends ValueNotifier<ReaderVideoControls?> {
  ReaderVideoControlsSlot() : super(null);

  bool _disposed = false;

  // 页面可能在 build/didUpdateWidget 中登记；延后通知兄弟节点，避开构建期间 setState。
  void publish(ReaderVideoControls controls) {
    scheduleMicrotask(() {
      if (!_disposed && controls.isCurrent()) value = controls;
    });
  }

  void release(Object owner) {
    scheduleMicrotask(() {
      if (!_disposed && identical(value?.owner, owner)) value = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 底栏和视频页共用的局部作用域。设置改变只更新界面，不重新打开播放会话。
class ReaderVideoControlsHost extends StatefulWidget {
  const ReaderVideoControlsHost({
    super.key,
    required this.child,
    required this.onToggleControls,
  });

  final Widget child;
  final VoidCallback onToggleControls;

  @override
  State<ReaderVideoControlsHost> createState() =>
      _ReaderVideoControlsHostState();
}

class _ReaderVideoControlsHostState extends State<ReaderVideoControlsHost> {
  final ReaderVideoControlsSlot _slot = ReaderVideoControlsSlot();

  @override
  void dispose() {
    _slot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: VideoSettingsStore.integrateControlsWithBottomBar,
    child: widget.child,
    builder: (context, enabled, child) => ReaderVideoControlsScope(
      enabled: enabled,
      slot: _slot,
      onToggleControls: widget.onToggleControls,
      child: child!,
    ),
  );
}

class ReaderVideoControlsScope extends InheritedWidget {
  const ReaderVideoControlsScope({
    super.key,
    required this.enabled,
    required this.slot,
    required this.onToggleControls,
    required super.child,
  });

  final bool enabled;
  final ReaderVideoControlsSlot slot;
  final VoidCallback onToggleControls;

  static ReaderVideoControlsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderVideoControlsScope>();

  @override
  bool updateShouldNotify(ReaderVideoControlsScope oldWidget) =>
      enabled != oldWidget.enabled || slot != oldWidget.slot;
}
