import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';

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
        ? (summary.currentWeek > 0 ? '上一窗口无记录' : '两周均无记录')
        : '${summary.deltaPercent >= 0 ? '+' : ''}${summary.deltaPercent}% 对比前 7 日';
    return ActionBubbleRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InsightMetrics(
            children: [
              InsightMetric(
                value: '${summary.currentWeek}',
                label: '近 7 日记录',
                highlight: true,
              ),
              InsightMetric(value: '${summary.previousWeek}', label: '前 7 日记录'),
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
                            label: '${day.key}：${day.count} 条记录',
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
              child: Text('${selected.key} · ${selected.count} 条记录'),
            ),
          const InsightFootnote(),
        ],
      ),
    );
  }
}

class ReadingStreakView extends StatelessWidget {
  const ReadingStreakView({super.key, required this.summary});
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
