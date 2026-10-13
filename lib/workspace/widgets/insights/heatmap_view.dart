import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/insights/compact_heatmap_view.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/insights/insight_header_controls.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';

class ReadingHeatmapView extends StatefulWidget {
  const ReadingHeatmapView({
    super.key,
    required this.summary,
    this.initialSelection,
  });
  final ReadingHeatmapSummary summary;
  final int? initialSelection;
  @override
  State<ReadingHeatmapView> createState() => _ReadingHeatmapViewState();
}

class _ReadingHeatmapViewState extends State<ReadingHeatmapView> {
  late int? _selected = widget.initialSelection;
  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final top = summary.topSlot;
    final cell = summary
        .cells[_selected ?? (top == null ? 0 : top.weekday * 24 + top.hour)];
    final colors = Theme.of(context).colorScheme;
    Color color(int count) => count == 0
        ? colors.surfaceContainerHighest
        : Color.lerp(
            colors.secondaryContainer,
            colors.primary,
            count / math.max(1, summary.maxCount),
          )!;
    Widget selector(
      String label,
      List<String> labels,
      ValueChanged<int> choose,
    ) => CommonPopupBox(
      targetBuilder: (open) => ElasticButton(
        child: FilledButton.tonal(
          onPressed: open,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: const StadiumBorder(),
          ),
          child: Text(label),
        ),
      ),
      popupBuilder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(360, MediaQuery.sizeOf(context).height * .6),
        ),
        child: CommonPopupMenu(
          items: [
            for (var index = 0; index < labels.length; index++)
              CommonPopupMenuItem(
                label: labels[index],
                onPressed: () => choose(index),
              ),
          ],
        ),
      ),
    );
    final full = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (top != null)
          InsightBadge(
            text: '高峰 · ${top.weekdayLabel} ${top.hourLabel}',
            glyph: AppGlyphs.calendar,
          ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: SizedBox(
              width: math.max(380, constraints.maxWidth),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 24),
                      for (var hour = 0; hour < 24; hour++)
                        Expanded(
                          child: Text(
                            hour % 6 == 0 ? '$hour' : '',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var day = 0; day < 7; day++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Text(weekdayLabels[day])),
                          for (var hour = 0; hour < 24; hour++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: () {
                                  final entry = summary.cells[day * 24 + hour];
                                  final active =
                                      cell.weekday == day && cell.hour == hour;
                                  return Tooltip(
                                    message:
                                        '${entry.weekdayLabel} ${entry.hourLabel}：${entry.count} 条记录',
                                    child: Semantics(
                                      label:
                                          '${entry.weekdayLabel} ${entry.hourLabel}：${entry.count} 条记录',
                                      selected: active,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _selected = day * 24 + hour,
                                        ),
                                        child: Container(
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: color(entry.count),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: active
                                                  ? colors.onSurface
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
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('少'),
            for (var i = 0; i <= 4; i++)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: i == 0
                      ? colors.surfaceContainerHighest
                      : Color.lerp(
                          colors.secondaryContainer,
                          colors.primary,
                          i / 4,
                        ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            const Text('多 · 描边为选中项'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            selector(
              cell.weekdayLabel,
              weekdayFullLabels,
              (day) => setState(() => _selected = day * 24 + cell.hour),
            ),
            selector(cell.hourLabel, [
              for (var i = 0; i < 24; i++) '${i.toString().padLeft(2, '0')}:00',
            ], (hour) => setState(() => _selected = cell.weekday * 24 + hour)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${cell.weekdayLabel} ${cell.hourLabel} · ${cell.count} 条记录',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const InsightFootnote(),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (!bounds.hasBoundedHeight ||
            (bounds.maxHeight >= 460 * scale &&
                bounds.maxWidth >= 380 * scale)) {
          return CardHeaderActions(
            revision: (summary, _selected, 'full'),
            actions: ActionBubbleRegion(
              child: InsightDetailButton(
                label: '',
                title: '阅读热力',
                detailBuilder: (_) => ReadingHeatmapView(
                  summary: summary,
                  initialSelection: _selected,
                ),
                iconOnly: true,
              ),
            ),
            child: full,
          );
        }
        return CompactHeatmapView(
          summary: summary,
          selected:
              _selected ?? (top == null ? 0 : top.weekday * 24 + top.hour),
          onSelect: (index) => setState(() => _selected = index),
          detailBuilder: (_) =>
              ReadingHeatmapView(summary: summary, initialSelection: _selected),
        );
      },
    );
  }
}
