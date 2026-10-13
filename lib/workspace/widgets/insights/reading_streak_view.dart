import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/workspace/widgets/insights/insight_sections.dart';

class ReadingStreakView extends StatelessWidget {
  const ReadingStreakView({super.key, required this.summary});
  final ReadingStreakSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (bounds.maxWidth / (125 * scale)).floor().clamp(1, 2);
      return InsightSectionPager(
        labels: const ['摘要', '趋势'],
        sections: [
          _StreakSummary(summary: summary),
          _StreakTimeline(summary: summary),
        ],
        full: _FullStreakView(summary: summary),
        fullHeight: (columns == 1 ? 430 : 330) * scale,
        detailTitle: '连续阅读',
        tinySummary: '当前 ${summary.currentStreak} 天 · 展开查看',
      );
    },
  );
}

class _StreakSummary extends StatelessWidget {
  const _StreakSummary({required this.summary});
  final ReadingStreakSummary summary;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget metric(String label, int value, bool highlight) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: highlight
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Semantics(
          label: '$label：$value 天',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: label,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$value',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: highlight
                        ? theme.colorScheme.onPrimaryContainer
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        metric('当前连续', summary.currentStreak, true),
        const SizedBox(height: 6),
        metric('样本最长', summary.longestStreak, false),
      ],
    );
  }
}

class _StreakTimeline extends StatelessWidget {
  const _StreakTimeline({required this.summary});
  final ReadingStreakSummary summary;
  @override
  Widget build(BuildContext context) {
    final points = summary.points.length > 28
        ? summary.points.sublist(summary.points.length - 28)
        : summary.points;
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Tooltip(
                        message: '${point.date}：连续 ${point.value} 天',
                        child: Semantics(
                          label: '${point.date}：连续 ${point.value} 天',
                          child: InsightBar(
                            ratio: point.value / summary.maxValue,
                            highlighted:
                                summary.currentStreak > 0 &&
                                point == points.last,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    points.first.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    points.last.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
          if (bounds.maxHeight >=
              160 * MediaQuery.textScalerOf(context).scale(14) / 14)
            const InsightFootnote(text: '样本内连续日期 · 不代表完整阅读日志'),
        ],
      ),
    );
  }
}

class _FullStreakView extends StatelessWidget {
  const _FullStreakView({required this.summary});
  final ReadingStreakSummary summary;
  @override
  Widget build(BuildContext context) {
    final points = summary.points.length > 28
        ? summary.points.sublist(summary.points.length - 28)
        : summary.points;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightMetrics(
          children: [
            InsightMetric(
              value: '${summary.currentStreak}',
              label: '当前连续 · 天',
              highlight: true,
              glyph: AppGlyphs.fire,
            ),
            InsightMetric(value: '${summary.longestStreak}', label: '样本最长 · 天'),
          ],
        ),
        const SizedBox(height: 12),
        InsightBadge(text: '最近活跃 · ${summary.lastActiveDate ?? '暂无'}'),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Semantics(
                        label: '${point.date}：连续 ${point.value} 天',
                        child: Tooltip(
                          message: '${point.date}：连续 ${point.value} 天',
                          child: InsightBar(
                            ratio: point.value / summary.maxValue,
                            highlighted:
                                summary.currentStreak > 0 &&
                                point == points.last,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [Text(points.first.label), Text(points.last.label)],
          ),
        ],
        const InsightFootnote(text: '样本内有记录的连续日期 · 不代表完整阅读日志'),
      ],
    );
  }
}
