import 'package:flutter/widgets.dart';

typedef DiscoverToolbarAction = Future<void> Function(BuildContext anchor);

/// 每个标签单独登记正文提供的工具；分屏和切换不会操作另一个标签。
class DiscoverTabToolbarController extends ChangeNotifier {
  Object? _owner;
  DiscoverToolbarAction? _presentation;
  bool _disposed = false;

  DiscoverToolbarAction? get presentation => _presentation;

  void register(Object owner, DiscoverToolbarAction action) {
    if (_disposed) return;
    _owner = owner;
    _presentation = action;
    notifyListeners();
  }

  void unregister(Object owner) {
    if (_disposed || !identical(_owner, owner)) return;
    _owner = null;
    _presentation = null;
    // 正文可能在构建/卸载相离开，工具栏在下一帧更新。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _presentation = null;
    super.dispose();
  }
}

class DiscoverTabToolbarScope extends InheritedWidget {
  const DiscoverTabToolbarScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final DiscoverTabToolbarController controller;

  static DiscoverTabToolbarController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiscoverTabToolbarScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DiscoverTabToolbarScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
