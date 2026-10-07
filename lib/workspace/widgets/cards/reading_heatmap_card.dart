import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 星期 × 小时阅读热力（neoview `ReadingHeatmapCard` 的同位物）。
///
/// 行的编号是**周日在第 0 行**（与 `weekdayIndex` 一致），不是 Dart 的「周一 = 1」。
/// 这一点在模型里已经定死了，卡片只按下标取格子；两边都改才不会错一行。
class ReadingHeatmapCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const ReadingHeatmapCard({
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
      cardId: 'reading_heatmap',
      title: '阅读热力',
      icon: Icons.calendar_month_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        skeletonHeight: 110,
        builder: (context, events) =>
            _Content(summary: buildReadingHeatmap(events)),
      ),
    );
  }
}

/// 左侧「周几」那一列的宽度。24 列格子平分剩下的宽度。
const double _labelWidth = 18;

/// 格子的最大边长。
///
/// 泳道很宽时不封顶的话，格子会跟着列宽长成大方砖，7 行能把整块面板吃掉。
/// 超过这个值就只压**高度**、宽度照旧铺满 —— 于是格子略扁，但右边不再空一片。
const double _maxCellSize = 28;

/// 格子高度：列宽，但不超过 [_maxCellSize]、也不小于一个可点的块。
double _cellHeight(double maxWidth) =>
    ((maxWidth - _labelWidth) / 24).clamp(4.0, _maxCellSize);

class _Content extends StatelessWidget {
  const _Content({required this.summary});

  final ReadingHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.topSlot != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                text: '高峰时段：',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text:
                        '${summary.topSlot!.weekdayLabel} ${summary.topSlot!.hourLabel}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            // 24 列一律用 Expanded 平分剩下的宽度：交给布局引擎分配才不会有
            // 亚像素累加挤出的半像素缝，也不会像固定边长那样在右侧留下一段空白。
            final cell = _cellHeight(constraints.maxWidth);
            return Column(
              children: [
                const _HourRow(),
                for (var weekday = 0; weekday < 7; weekday += 1)
                  _HeatRow(weekday: weekday, cell: cell, summary: summary),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const SizedBox(width: _labelWidth),
          for (var hour = 0; hour < 24; hour += 1)
            Expanded(
              // 只标 0/6/12/18：24 个数字在一根窄泳道里必然糊成一片。
              child: Text(
                hour % 6 == 0 ? '$hour' : '',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeatRow extends StatelessWidget {
  const _HeatRow({
    required this.weekday,
    required this.cell,
    required this.summary,
  });

  final int weekday;
  final double cell;
  final ReadingHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              weekdayLabels[weekday],
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var hour = 0; hour < 24; hour += 1)
            Expanded(
              child: _HeatCell(
                cell: summary.cells[weekday * 24 + hour],
                maxCount: summary.maxCount,
                size: cell,
              ),
            ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.cell,
    required this.maxCount,
    required this.size,
  });

  final ReadingHeatmapCell cell;
  final int maxCount;

  /// 格子**高度**；宽度由外层 `Expanded` 按列平分，所以宽泳道下格子可以略扁。
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensity = maxCount > 0 ? cell.count / maxCount : 0.0;
    // 空格子也要画出来：只有「一格里都没有」才能说明「那个时段从没读过」。
    final color = cell.count == 0
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : theme.colorScheme.primary.withValues(
            alpha: (0.18 + 0.82 * intensity).clamp(0.18, 1.0),
          );

    final box = SizedBox(
      height: size,
      child: Padding(
        padding: const EdgeInsets.all(0.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );

    // 一格一个 Tooltip 会是 168 个悬浮层；只在真有数据的格子上挂。
    if (cell.count == 0) return box;
    return Tooltip(
      message: '${cell.weekdayLabel} ${cell.hourLabel}：${cell.count} 次',
      child: box,
    );
  }
}
