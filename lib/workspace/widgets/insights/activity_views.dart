import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insight_activity.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/i18n/strings.g.dart';

class ReadingOverviewView extends StatelessWidget {
  const ReadingOverviewView({super.key, required this.summary});
  final ReadingActivitySummary summary;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InsightMetrics(
        children: [
          InsightMetric(
            value: '${summary.records}',
            label: t.workspace.last28Records,
            highlight: true,
            glyph: AppGlyphs.openBook,
          ),
          InsightMetric(
            value: '${summary.activeDays} / 28',
            label: t.workspace.activeDays,
            glyph: AppGlyphs.calendar,
          ),
          InsightMetric(
            value: '${summary.sources}',
            label: t.workspace.readingSources,
            glyph: AppGlyphs.pieChart,
          ),
        ],
      ),
      InsightFootnote(text: t.workspace.footnoteLast500),
    ],
  );
}

class ActivityCalendarView extends StatefulWidget {
  const ActivityCalendarView({super.key, required this.summary});
  final ReadingActivitySummary summary;
  @override
  State<ActivityCalendarView> createState() => _ActivityCalendarViewState();
}

class _ActivityCalendarViewState extends State<ActivityCalendarView> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final colors = Theme.of(context).colorScheme;
    final selected =
        summary.days.where((day) => day.key == _selected).firstOrNull ??
        summary.days.last;
    return ActionBubbleRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InsightBadge(
                text: t.workspace.activeDaysCount(n: summary.activeDays),
                glyph: AppGlyphs.fire,
              ),
              InsightBadge(text: t.workspace.last28Days),
            ],
          ),
          const SizedBox(height: 14),
          // 四行七列是连续四个七日窗口，日期写在格内，不伪装成完整自然月。
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: SizedBox(
                width: constraints.maxWidth < 392 ? 392 : constraints.maxWidth,
                child: Column(
                  children: [
                    for (var row = 0; row < 4; row++)
                      Row(
                        children: [
                          for (var column = 0; column < 7; column++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: () {
                                  final day = summary.days[row * 7 + column];
                                  final active = day.key == selected.key;
                                  final fill = day.count == 0
                                      ? colors.surfaceContainerHighest
                                      : Color.lerp(
                                          colors.surfaceContainerHighest,
                                          colors.primary,
                                          .15 +
                                              .85 * day.count / summary.maxDay,
                                        )!;
                                  final foreground = day.count == 0
                                      ? colors.onSurfaceVariant
                                      : fill.computeLuminance() > .179
                                      ? Colors.black
                                      : Colors.white;
                                  return InsightSelectable(
                                    label: t.workspace.dayRecordLine(
                                      key: day.key,
                                      count: day.count,
                                    ),
                                    selected: active,
                                    onSelected: () =>
                                        setState(() => _selected = day.key),
                                    child: Container(
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: fill,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: active
                                              ? colors.primary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Text(
                                        '${int.parse(day.key.substring(8))}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: foreground,
                                              fontWeight: active
                                                  ? FontWeight.w800
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  );
                                }(),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t.workspace.selectedLastReadLines(
              key: selected.key,
              count: selected.count,
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          InsightFootnote(text: t.workspace.heatmapFourRowsHint),
        ],
      ),
    );
  }
}

class WeeklyRhythmView extends StatelessWidget {
  const WeeklyRhythmView({super.key, required this.summary});
  final ReadingActivitySummary summary;
  static const labels = ['一', '二', '三', '四', '五', '六', '日'];
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightBadge(
          text: summary.records == 0
              ? t.workspace.last28NoRecords
              : t.workspace.busiestWeekdayLabel(
                  day: labels[summary.busiestWeekday],
                ),
          glyph: AppGlyphs.trend,
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < 7; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Semantics(
              label: t.workspace.weekdayRecordLine(
                day: labels[index],
                count: summary.weekdays[index],
              ),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text(labels[index])),
                  Expanded(
                    child: InsightSpringValue(
                      value: summary.weekdays[index] / summary.maxWeekday,
                      builder: (ratio) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Container(
                              height: 16,
                              color: colors.surfaceContainerHighest,
                            ),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              child: Container(
                                height: 16,
                                color: index == summary.busiestWeekday
                                    ? colors.primary
                                    : colors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${summary.weekdays[index]}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
        InsightFootnote(text: t.workspace.footnoteWeekday28),
      ],
    );
  }
}

class ReadingPeriodsView extends StatelessWidget {
  const ReadingPeriodsView({super.key, required this.summary});
  final ReadingActivitySummary summary;
  static List<String> get labels => [
    t.workspace.lateNight,
    t.workspace.morning,
    t.workspace.earlyAfternoon,
    t.workspace.eveningNight,
  ];
  static const hours = [
    '00:00–06:00',
    '06:00–12:00',
    '12:00–18:00',
    '18:00–24:00',
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InsightBadge(
        text: summary.records == 0
            ? t.workspace.last28NoRecords
            : t.workspace.busiestPeriodLabel(
                period: labels[summary.busiestPeriod],
              ),
        glyph: AppGlyphs.clock,
      ),
      const SizedBox(height: 14),
      InsightMetrics(
        children: [
          for (var index = 0; index < 4; index++)
            InsightMetric(
              value:
                  '${summary.records == 0 ? 0 : (summary.periods[index] * 100 / summary.records).round()}%',
              label: t.workspace.periodDetailLine(
                label: labels[index],
                count: summary.periods[index],
                hours: hours[index],
              ),
              highlight: summary.records > 0 && index == summary.busiestPeriod,
            ),
        ],
      ),
      InsightFootnote(text: t.workspace.footnotePeriod28),
    ],
  );
}
