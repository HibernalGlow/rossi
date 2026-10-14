import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/i18n/strings.g.dart';

export 'package:zephyr/workspace/widgets/insights/reading_streak_view.dart'
    show ReadingStreakView;

class DailyTrendView extends StatefulWidget {
  const DailyTrendView({super.key, required this.summary});
  final DailyTrendSummary summary;
  @override
  State<DailyTrendView> createState() => _DailyTrendViewState();
}

class _DailyTrendViewState extends State<DailyTrendView> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final selected = summary.days
        .where((day) => day.key == _selected)
        .firstOrNull;
    final delta = summary.previousWeek == 0
        ? (summary.currentWeek > 0
              ? t.workspace.prevWindowNoRecord
              : t.workspace.bothWeeksNoRecord)
        : '${summary.deltaPercent >= 0 ? '+' : ''}${summary.deltaPercent}% 对比前 7 日';
    return ActionBubbleRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InsightMetrics(
            children: [
              InsightMetric(
                value: '${summary.currentWeek}',
                label: t.workspace.last7Records,
                highlight: true,
              ),
              InsightMetric(
                value: '${summary.previousWeek}',
                label: t.workspace.last7DaysRecords,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InsightBadge(text: delta, glyph: AppGlyphs.trend),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: SizedBox(
                width: constraints.maxWidth < 364 ? 364 : constraints.maxWidth,
                height: 124,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in summary.days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InsightSelectable(
                            label: t.workspace.dayRecordLine(
                              key: day.key,
                              count: day.count,
                            ),
                            selected: day.key == _selected,
                            onSelected: () =>
                                setState(() => _selected = day.key),
                            child: Column(
                              children: [
                                Text(
                                  '${day.count}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 5),
                                Expanded(
                                  child: InsightBar(
                                    ratio: day.count / summary.maxCount,
                                    highlighted:
                                        day.key == _selected ||
                                        (day.count > 0 &&
                                            day.count == summary.maxCount),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  day.label,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                t.workspace.dayRecordLine(
                  key: selected.key,
                  count: selected.count,
                ),
              ),
            ),
          InsightFootnote(),
        ],
      ),
    );
  }
}
