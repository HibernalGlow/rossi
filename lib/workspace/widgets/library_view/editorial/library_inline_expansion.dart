import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';

/// 首帧创建业务宿主并开始加载。收起保留状态，避免再次展开时重新请求。
class LibraryInlineExpansion extends StatelessWidget {
  const LibraryInlineExpansion({
    super.key,
    required this.visible,
    required this.child,
  });
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: visible ? 1 : 0),
    duration: ExpressiveMotion.duration(
      context,
      const Duration(milliseconds: 240),
    ),
    curve: ExpressiveMotion.spatialCurve,
    child: child,
    builder: (_, value, child) => IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: TickerMode(
          enabled: visible,
          child: Offstage(
            offstage: value == 0,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 已展开的详情离开视口时仍保留阅读、章节选择与请求状态。
class LibraryDetailRetention extends StatefulWidget {
  const LibraryDetailRetention({
    super.key,
    required this.keep,
    required this.child,
  });
  final bool keep;
  final Widget child;
  @override
  State<LibraryDetailRetention> createState() => _LibraryDetailRetentionState();
}

class _LibraryDetailRetentionState extends State<LibraryDetailRetention>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;
  @override
  void didUpdateWidget(LibraryDetailRetention oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
