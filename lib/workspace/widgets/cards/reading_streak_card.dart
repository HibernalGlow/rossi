import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 连续阅读（neoview `ReadingStreakCard` 的同位物）。
///
/// 上面三个数是可以一眼读完的结论，下面那条走势是结论的**出处**：
/// 只显示「连续 5 天」而看不到中间断过几次，用户不会相信这个数。
class ReadingStreakCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const ReadingStreakCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'reading_streak',
      title: '连续阅读',
      icon: Icons.local_fire_department_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        builder: (context, events) =>
            _Content(summary: buildReadingStreak(events)),
      ),
    );
  }
}

/// 走势里最多画多少根（与 neoview 一样取最近 28 个**有访问的日子**）。
const int _visiblePoints = 28;

class _Content extends StatelessWidget {
  const _Content({required this.summary});

  final ReadingStreakSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = summary.points.length > _visiblePoints
        ? summary.points.sublist(summary.points.length - _visiblePoints)
        : summary.points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Metric(label: '当前连续', value: '${summary.currentStreak} 天'),
            _Metric(label: '最长连续', value: '${summary.longestStreak} 天'),
            _Metric(label: '最近活跃', value: summary.lastActiveDate ?? '暂无'),
          ],
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: Tooltip(
                        message: '${point.date}：连续 ${point.value} 天',
                        child: InsightBar(
                          ratio: point.value / summary.maxValue,
                          // 只有最后一根真的是当前连胜时才描实色。
                          highlighted: point == points.last,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                points.first.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                points.last.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
