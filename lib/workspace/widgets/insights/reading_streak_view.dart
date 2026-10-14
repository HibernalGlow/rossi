import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/workspace/widgets/insights/insight_sections.dart';
import 'package:zephyr/i18n/strings.g.dart';

class ReadingStreakView extends StatelessWidget {
  const ReadingStreakView({super.key, required this.summary});
  final ReadingStreakSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (bounds.maxWidth / (125 * scale)).floor().clamp(1, 2);
      return InsightSectionPager(
        labels: [t.workspace.summaryLabel, t.workspace.trendLabel],
        sections: [
          _StreakSummary(summary: summary),
          _StreakTimeline(summary: summary),
        ],
        full: _FullStreakView(summary: summary),
        fullHeight: (columns == 1 ? 430 : 330) * scale,
        detailTitle: t.workspace.streakReading,
        tinySummary: t.workspace.streakNowDays(n: summary.currentStreak),
        dataRevision: summary,
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
          label: t.workspace.streakDaysLine(label: label, value: value),
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
        metric(t.workspace.currentStreak, summary.currentStreak, true),
        const SizedBox(height: 6),
        metric(t.workspace.longestSample, summary.longestStreak, false),
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
                        message: t.workspace.streakPointLine(
                          date: point.date,
                          value: point.value,
                        ),
                        child: Semantics(
                          label: t.workspace.streakPointLine(
                            date: point.date,
                            value: point.value,
                          ),
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
            InsightFootnote(text: t.workspace.footnoteSampleStreak),
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
              label: t.workspace.currentStreakDays,
              highlight: true,
              glyph: AppGlyphs.fire,
            ),
            InsightMetric(
              value: '${summary.longestStreak}',
              label: t.workspace.longestSampleDays,
            ),
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
                        label: t.workspace.streakPointLine(
                          date: point.date,
                          value: point.value,
                        ),
                        child: Tooltip(
                          message: t.workspace.streakPointLine(
                            date: point.date,
                            value: point.value,
                          ),
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
        InsightFootnote(text: t.workspace.footnoteSampleStreakDays),
      ],
    );
  }
}
