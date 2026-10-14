import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/heatmap_buckets.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/insights/insight_header_controls.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 有界卡片保留完整矩阵，按宽度汇总时段；逐小时查询留在展开视图。
class CompactHeatmapView extends StatelessWidget {
  const CompactHeatmapView({
    super.key,
    required this.summary,
    required this.selected,
    required this.onSelect,
    required this.detailBuilder,
  });
  final ReadingHeatmapSummary summary;
  final int selected;
  final ValueChanged<int> onSelect;
  final WidgetBuilder detailBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final theme = Theme.of(context);
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final top = summary.topSlot;
      final effectiveWidth = bounds.maxWidth / scale;
      final hours = effectiveWidth >= 560
          ? 1
          : effectiveWidth >= 320
          ? 2
          : 6;
      final columns = 24 ~/ hours;
      final buckets = heatmapBuckets(summary, hours);
      final maxCount = buckets.fold(
        1,
        (value, cell) => math.max(value, cell.count),
      );
      final selectedDay = selected ~/ 24;
      final selectedColumn = selected % 24 ~/ hours;
      final chosen = buckets[selectedDay * columns + selectedColumn];
      final tiny = bounds.maxHeight < 158 * scale || bounds.maxWidth < 140;
      final actions = ActionBubbleRegion(
        child: tiny
            ? InsightDetailButton(
                label: '',
                title: t.workspace.readingHeat,
                description: t.workspace.compactHeatmapExpand(
                  day: chosen.label,
                ),
                detailBuilder: detailBuilder,
                iconOnly: true,
              )
            : LayoutBuilder(
                builder: (context, headerBounds) => InsightDetailButton(
                  label: t.workspace.hoursPerCell(hours: hours),
                  title: t.workspace.readingHeat,
                  description: t.workspace.compactHeatmapExpandHours(
                    day: chosen.label,
                    hours: hours,
                  ),
                  detailBuilder: detailBuilder,
                  compact: true,
                  iconOnly: headerBounds.maxWidth < 100,
                ),
              ),
      );
      // 七行放不下时只显示结论；展开操作始终属于标题栏。
      if (tiny) {
        return CardHeaderActions(
          revision: (summary, selected, hours, tiny),
          actions: actions,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              top == null
                  ? t.workspace.noHeatRecords
                  : t.workspace.heatPeakShort(
                      weekday: top.weekdayLabel,
                      hour: top.hourLabel,
                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      Color color(int count) => count == 0
          ? theme.colorScheme.surfaceContainerHighest
          : Color.lerp(
              theme.colorScheme.secondaryContainer,
              theme.colorScheme.primary,
              count / maxCount,
            )!;
      return CardHeaderActions(
        revision: (summary, selected, hours, tiny),
        actions: actions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: 24 * scale),
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: Text(
                      hours == 6
                          ? ['夜', '晨', t.workspace.noon, '晚'][column]
                          : column * hours % 6 == 0
                          ? '${column * hours}'
                          : '',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                children: [
                  for (var day = 0; day < 7; day++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 24 * scale,
                            child: Center(
                              child: Text(
                                weekdayLabels[day],
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          ),
                          for (var column = 0; column < columns; column++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: () {
                                  final bucket =
                                      buckets[day * columns + column];
                                  final active =
                                      day == selectedDay &&
                                      column == selectedColumn;
                                  return Tooltip(
                                    message: bucket.label,
                                    child: Semantics(
                                      label: bucket.label,
                                      selected: active,
                                      button: true,
                                      child: GestureDetector(
                                        onTap: () =>
                                            onSelect(day * 24 + column * hours),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: color(bucket.count),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: active
                                                  ? theme.colorScheme.onSurface
                                                  : Colors.transparent,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
