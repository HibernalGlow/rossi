import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/insights/trend_views.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 连续阅读（neoview `ReadingStreakCard` 的同位物）。
///
/// 上面三个数是可以一眼读完的结论，下面那条走势是结论的**出处**：
/// 只显示「连续 5 天」而看不到中间断过几次，用户不会相信这个数。
class ReadingStreakCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const ReadingStreakCard({
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
      cardId: 'reading_streak',
      title: t.workspace.streakReading,
      icon: AppGlyphs.fire,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        builder: (context, events) =>
            ReadingStreakView(summary: buildReadingStreak(events)),
      ),
    );
  }
}
