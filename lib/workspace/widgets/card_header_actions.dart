import 'package:material_ui/material_ui.dart';

/// 正文将当前分段和展开操作交给外壳标题栏，保持内容状态由原控件持有。
class CardHeaderActionsHost extends StatefulWidget {
  const CardHeaderActionsHost({super.key, required this.builder});
  final Widget Function(BuildContext context, Widget? actions) builder;

  @override
  State<CardHeaderActionsHost> createState() => _CardHeaderActionsHostState();
}

class _CardHeaderActionsHostState extends State<CardHeaderActionsHost> {
  late final _controller = _HeaderController()..addListener(_update);
  void _update() => setState(() {});

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HeaderScope(
    controller: _controller,
    child: Builder(
      builder: (context) => widget.builder(context, _controller.actions),
    ),
  );
}

class CardHeaderActions extends StatefulWidget {
  const CardHeaderActions({
    super.key,
    required this.actions,
    required this.revision,
    required this.child,
  });
  final Widget actions;
  final Object revision;
  final Widget child;

  static bool hasHost(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_HeaderScope>() != null;

  @override
  State<CardHeaderActions> createState() => _CardHeaderActionsState();
}

class _CardHeaderActionsState extends State<CardHeaderActions> {
  _HeaderController? _controller;
  bool _publishScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context
        .dependOnInheritedWidgetOfExactType<_HeaderScope>()
        ?.controller;
    if (_controller != controller) _controller?.clear(this);
    _controller = controller;
    _publish();
  }

  @override
  void didUpdateWidget(CardHeaderActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publish();
  }

  // 高度判定发生在 LayoutBuilder 中，帧尾才更新标题。
  // 发布前重读当前绑定，避免销毁或重挂载后的旧回调抢占标题。
  void _publish() {
    if (_publishScheduled || _controller == null) return;
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (!mounted) return;
      _controller?.publish(this, widget.revision, widget.actions);
    });
  }

  @override
  void dispose() {
    _controller?.clear(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HeaderScope extends InheritedWidget {
  const _HeaderScope({required this.controller, required super.child});
  final _HeaderController controller;
  @override
  bool updateShouldNotify(_HeaderScope oldWidget) =>
      controller != oldWidget.controller;
}

class _HeaderController extends ChangeNotifier {
  Object? _owner;
  Object? _revision;
  Widget? actions;
  bool _disposed = false;

  void publish(Object owner, Object revision, Widget actions) {
    if (_disposed) return;
    final changed = _owner != owner || _revision != revision;
    _owner = owner;
    _revision = revision;
    this.actions = actions;
    if (changed) notifyListeners();
  }

  void clear(Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _owner != owner) return;
      _owner = _revision = null;
      actions = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
