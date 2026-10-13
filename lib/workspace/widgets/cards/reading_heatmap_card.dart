import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/insights/heatmap_view.dart';

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
      expressive: true,
      scrollContent: false,
      cardId: 'reading_heatmap',
      title: '阅读热力',
      icon: AppGlyphs.calendar,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        skeletonHeight: 110,
        builder: (context, events) =>
            ReadingHeatmapView(summary: buildReadingHeatmap(events)),
      ),
    );
  }
}
