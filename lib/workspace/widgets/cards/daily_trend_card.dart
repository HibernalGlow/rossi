import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/insights/trend_views.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
      expressive: true,
      cardId: 'daily_trend',
      title: t.workspace.last7ReadingTrend,
      icon: AppGlyphs.trend,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        builder: (context, events) =>
            DailyTrendView(summary: buildDailyTrend(events)),
      ),
    );
  }
}
