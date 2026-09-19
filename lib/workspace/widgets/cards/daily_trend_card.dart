import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 近 7 日阅读趋势（neoview `DailyTrendCard` 的同位物）。
///
/// 一根柱子一天，含今天；右上角是相对**上一个 7 天窗口**的变化。
/// 之所以给两件事都留一行字：柱子只说「哪几天多」，百分比才说「最近整体在涨还是在跌」。
class DailyTrendCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const DailyTrendCard({
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
      cardId: 'daily_trend',
      title: '近 7 日阅读趋势',
      icon: Icons.trending_up_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        builder: (context, events) =>
            _Content(summary: buildDailyTrend(events)),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.summary});

  final DailyTrendSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = summary.deltaPercent >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '本周共 ${summary.currentWeek} 次访问',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${up ? '+' : ''}${summary.deltaPercent}% 对比上周',
              style: theme.textTheme.labelMedium?.copyWith(
                color: up ? theme.colorScheme.primary : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 82,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final day in summary.days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: '${day.key}：${day.count} 次',
                      child: Column(
                        children: [
                          Expanded(
                            child: InsightBar(
                              ratio: day.count / summary.maxCount,
                              // 只有「就是最高那天」才描实色，全 0 时不该有一根是实的。
                              highlighted:
                                  day.count > 0 &&
                                  day.count == summary.maxCount,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            day.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
