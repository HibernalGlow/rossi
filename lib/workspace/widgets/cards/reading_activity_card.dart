import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/history_insight_activity.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/insights/activity_views.dart';

enum ReadingActivityKind { overview, calendar, rhythm, periods }

/// 四种视图共用既有历史流和卡片外壳，布局、收起和恢复继续交给工作台。
class ReadingActivityCard extends StatelessWidget {
  const ReadingActivityCard({
    super.key,
    required this.kind,
    required this.cardId,
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });
  final ReadingActivityKind kind;
  final String cardId;
  final String title;
  final Glyph icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  @override
  Widget build(BuildContext context) => CollapsibleCard(
    expressive: true,
    cardId: cardId,
    title: title,
    icon: icon,
    isExpanded: isExpanded,
    onToggle: onToggle,
    onMoveUp: onMoveUp,
    onMoveDown: onMoveDown,
    onHide: onHide,
    child: HistoryInsightsWindow(
      builder: (context, events) {
        final summary = buildReadingActivity(events);
        return switch (kind) {
          ReadingActivityKind.overview => ReadingOverviewView(summary: summary),
          ReadingActivityKind.calendar => ActivityCalendarView(
            summary: summary,
          ),
          ReadingActivityKind.rhythm => WeeklyRhythmView(summary: summary),
          ReadingActivityKind.periods => ReadingPeriodsView(summary: summary),
        };
      },
    ),
  );
}
