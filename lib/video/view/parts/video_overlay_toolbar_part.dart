part of '../video_control_overlay.dart';

/// 播放组始终居中，时间靠右；空间不足时设置成组换行。
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
      final transport = [
        for (final button in [children[1], children[0], children[2]])
          SizedBox(width: 48, child: button),
      ];
      final clock = children[3];
      final more = children.last;
      final settings = children.sublist(4, children.length - 1);
      const transportWidth = 148.0;
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
      final split = (settings.length / 2).ceil();
      final leftSettings = settings.take(split).toList();
      final rightSettings = [...settings.skip(split), more];
      double groupWidth(List<Widget> buttons) => buttons.fold<double>(
        0,
        (width, child) => width + _width(context, child) + 2,
      );
      final sideWidth = math.max(
        groupWidth(leftSettings),
        groupWidth(rightSettings) + clockWidth + 8,
      );
      Widget sizedGroup(List<Widget> buttons) => _group(context, [
        for (final button in buttons)
          SizedBox(width: _width(context, button), child: button),
      ]);
      if (constraints.maxWidth >= sideWidth * 2 + transportWidth + 16) {
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: sizedGroup(leftSettings),
              ),
            ),
            const SizedBox(width: 8),
            _group(context, transport),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  sizedGroup(rightSettings),
                  const SizedBox(width: 8),
                  SizedBox(width: clockWidth, child: clock),
                ],
              ),
            ),
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
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: more),
              ),
              const SizedBox(width: 8),
              _group(context, transport),
              const SizedBox(width: 8),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: clock),
              ),
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

/// 狭窄的右侧区域把时间分成两行，保留正常字号与完整时长。
class _VideoClock extends StatelessWidget {
  const _VideoClock({required this.current, required this.duration});
  final Duration current;
  final Duration duration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final currentText = formatVideoTime(current);
      final durationText = formatVideoTime(duration);
      final fullText = '$currentText / $durationText';
      final painter = TextPainter(
        text: TextSpan(text: fullText, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final stacked = painter.width > constraints.maxWidth;
      painter.dispose();
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          stacked ? '$currentText\n/ $durationText' : fullText,
          key: const ValueKey('video-progress-time'),
          textAlign: TextAlign.right,
          style: style,
        ),
      );
    },
  );
}
