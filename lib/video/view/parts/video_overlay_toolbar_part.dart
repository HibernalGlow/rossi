part of '../video_control_overlay.dart';

/// 把播放操作和时间作为一组，设置作为另一组；更多永远留在播放操作旁。
class _AdaptiveVideoToolbar extends StatelessWidget {
  const _AdaptiveVideoToolbar({
    required this.children,
    required this.clockText,
  });

  final List<Widget> children;
  final String clockText;

  double _width(BuildContext context, Widget child) {
    if (child is! _TextButton || child.icon != null) return 48;
    final painter = TextPainter(
      text: TextSpan(
        text: child.label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.max(64.0, painter.width + 32);
    painter.dispose();
    return width;
  }

  Widget _group(BuildContext context, List<Widget> buttons) => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(28),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(width: 2),
          buttons[index],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final transport = children.take(3).toList();
      final clock = children[3];
      final more = children.last;
      final settings = children.sublist(4, children.length - 1);
      final settingWidth = settings.fold<double>(
        0,
        (width, child) => width + _width(context, child) + 2,
      );
      final clockPainter = TextPainter(
        text: TextSpan(
          text: clockText,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final clockWidth = clockPainter.width + 16;
      clockPainter.dispose();
      if (constraints.maxWidth >= 192 + 4 + clockWidth + settingWidth + 16) {
        return Row(
          children: [
            _group(context, transport),
            Expanded(child: Center(child: clock)),
            _group(context, [
              for (final setting in settings)
                SizedBox(width: _width(context, setting), child: setting),
              SizedBox(width: 48, child: more),
            ]),
          ],
        );
      }
      // 每颗按钮按文字所需宽度排列，不让图标或短标签拉伸成一整块。
      final groups = <List<Widget>>[[]];
      var usedWidth = 0.0;
      for (final setting in settings) {
        final width = math.min(constraints.maxWidth, _width(context, setting));
        if (groups.last.isNotEmpty &&
            usedWidth + width + 2 > constraints.maxWidth) {
          groups.add([]);
          usedWidth = 0;
        }
        groups.last.add(SizedBox(width: width, child: setting));
        usedWidth += width + 2;
      }
      if (groups.length > 1 &&
          groups.last.length == 1 &&
          groups[groups.length - 2].length > 2) {
        groups.last.insert(0, groups[groups.length - 2].removeLast());
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _group(context, transport),
              Expanded(
                child: FittedBox(fit: BoxFit.scaleDown, child: clock),
              ),
              more,
            ],
          ),
          for (final group in groups) ...[
            const SizedBox(height: 6),
            Center(child: _group(context, group)),
          ],
        ],
      );
    },
  );
}
