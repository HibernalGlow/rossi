import 'dart:math' as math;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';

class SourceMixView extends StatelessWidget {
  const SourceMixView({
    super.key,
    required this.summary,
    required this.sourceLabel,
  });
  final SourceBreakdownSummary summary;
  final String Function(String key) sourceLabel;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = [
      colors.primary,
      colors.secondary,
      colors.tertiary,
      colors.primaryContainer,
      colors.secondaryContainer,
      colors.tertiaryContainer,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = InsightMetric(
              value: '${summary.total}',
              label: '样本记录 · ${summary.items.length} 个来源',
              highlight: true,
            );
            final ring = SizedBox(
              width: 126,
              height: 126,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: CustomPaint(
                      size: const Size.square(126),
                      painter: _SourceRing(
                        summary: summary,
                        palette: palette,
                        track: colors.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: M3EShapeContainer(
                      kind: M3EShapeKind.cookie6Sided,
                      color: colors.secondaryContainer,
                      child: Center(
                        child: Text(
                          '${summary.items.length}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 330) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metrics,
                  const SizedBox(height: 12),
                  Center(child: ring),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: metrics),
                const SizedBox(width: 18),
                ring,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < summary.items.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: () {
              final item = summary.items[index];
              final ratio = summary.total == 0
                  ? 0.0
                  : item.count / summary.total;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: palette[index % palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              sourceLabel(item.source),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      Text('${item.count} 条 · ${item.percent}%'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InsightSpringValue(
                    value: ratio,
                    builder: (value) => M3EProgressIndicator.linear(
                      value: value,
                      color: palette[index % palette.length],
                      trackColor: colors.surfaceContainerHighest,
                      semanticsLabel: sourceLabel(item.source),
                      semanticsValue: '${item.count} 条 · ${item.percent}%',
                    ),
                  ),
                ],
              );
            }(),
          ),
        const InsightFootnote(),
      ],
    );
  }
}

class _SourceRing extends CustomPainter {
  const _SourceRing({
    required this.summary,
    required this.palette,
    required this.track,
  });
  final SourceBreakdownSummary summary;
  final List<Color> palette;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (summary.total == 0) return;
    var start = -math.pi / 2;
    for (var index = 0; index < summary.items.length; index++) {
      final sweep = summary.items[index].count / summary.total * math.pi * 2;
      final gap = math.min(.06, sweep * .25);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        paint..color = palette[index % palette.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SourceRing oldDelegate) =>
      oldDelegate.summary != summary ||
      oldDelegate.track != track ||
      oldDelegate.palette != palette;
}
