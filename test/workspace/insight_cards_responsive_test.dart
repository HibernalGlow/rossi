import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/history_insight_activity.dart';
import 'package:zephyr/workspace/model/heatmap_buckets.dart';
import 'package:zephyr/workspace/widgets/insights/insight_sections.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/grid/grid.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/insights/activity_views.dart';
import 'package:zephyr/workspace/widgets/insights/trend_views.dart';
import 'package:zephyr/workspace/widgets/insights/heatmap_view.dart';
import 'package:zephyr/workspace/widgets/insights/source_mix_view.dart';

final now = DateTime(2026, 10, 13, 23, 59);
final samples = [
  for (var day = 0; day < 40; day++)
    for (var count = 0; count <= day % 5; count++)
      HistoryInsightEvent(
        at: DateTime(2026, 10, 13 - day, (count * 6) % 24),
        source: count.isEven ? 'local' : 'online',
        comicId: count.isEven ? '/Comic.cbz' : 'comic',
      ),
];
Widget shell(Widget child) => CollapsibleCard(
  cardId: 'test',
  title: '阅读洞察',
  icon: AppGlyphs.trend,
  isExpanded: true,
  onToggle: () {},
  expressive: true,
  scrollContent: child is! ReadingStreakView && child is! ReadingHeatmapView,
  margin: EdgeInsets.zero,
  child: child,
);
Widget host(Widget child, {double scale = 1, bool animations = false}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: !animations,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );
Map<String, Widget Function()> views() {
  final activity = buildReadingActivity(samples, now: now);
  return {
    'overview': () => ReadingOverviewView(summary: activity),
    'calendar': () => ActivityCalendarView(summary: activity),
    'rhythm': () => WeeklyRhythmView(summary: activity),
    'periods': () => ReadingPeriodsView(summary: activity),
    'trend': () => DailyTrendView(summary: buildDailyTrend(samples, now: now)),
    'streak': () =>
        ReadingStreakView(summary: buildReadingStreak(samples, now: now)),
    'heatmap': () => ReadingHeatmapView(summary: buildReadingHeatmap(samples)),
    'sources': () => SourceMixView(
      summary: buildSourceBreakdown(samples),
      sourceLabel: (source) => source == '本地' ? source : '很长的图源名称与阅读来源测试',
    ),
  };
}

void main() {
  test('热力时段汇总保留七个星期和全部记录', () {
    final heatmap = buildReadingHeatmap(samples);
    for (final hours in [1, 2, 6]) {
      final buckets = heatmapBuckets(heatmap, hours);
      expect(buckets.length, 7 * 24 ~/ hours);
      expect(buckets.map((bucket) => bucket.weekday).toSet().length, 7);
      expect(
        buckets.fold(0, (sum, bucket) => sum + bucket.count),
        heatmap.cells.fold(0, (sum, cell) => sum + cell.count),
      );
      for (final bucket in buckets) {
        expect(
          bucket.count,
          heatmap.cells
              .where(
                (cell) =>
                    cell.weekday == bucket.weekday &&
                    cell.hour >= bucket.firstHour &&
                    cell.hour < bucket.firstHour + hours,
              )
              .fold(0, (sum, cell) => sum + cell.count),
        );
      }
    }
  });
  testWidgets('连续阅读按语义上下切段，切换和调整宽度不滚动、不改外框', (tester) async {
    Widget card(double width) => host(
      SizedBox(
        width: width,
        height: 288,
        child: shell(
          ReadingStreakView(summary: buildReadingStreak(samples, now: now)),
        ),
      ),
      animations: true,
    );
    await tester.pumpWidget(card(400));
    await tester.pumpAndSettle();
    expect(find.byTooltip('摘要 · 1/2 · 展开连续阅读'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    final rect = tester.getRect(find.byType(CollapsibleCard));
    for (final control in [
      find.byTooltip('上一段'),
      find.byType(InsightDetailButton),
      find.byTooltip('下一段'),
    ]) {
      expect(
        tester.getCenter(control).dy,
        closeTo(tester.getCenter(find.text('阅读洞察')).dy, 1),
      );
      expect(
        tester.getRect(control).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CardHeaderActions)).top),
      );
    }
    await tester.tap(find.byTooltip('下一段'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(find.byType(CollapsibleCard)), rect);
    await tester.pumpAndSettle();
    expect(find.byTooltip('趋势 · 2/2 · 展开连续阅读'), findsOneWidget);
    await tester.pumpWidget(card(240));
    await tester.pumpAndSettle();
    expect(find.byTooltip('趋势 · 2/2 · 展开连续阅读'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(InsightDetailButton)).dy,
      closeTo(tester.getCenter(find.text('阅读洞察')).dy, 1),
    );
    await tester.tap(find.byType(InsightDetailButton));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一段'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('摘要 · 1/2 · 展开连续阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('小热力图保留完整七行，极小卡片通过统一弹层展开详情', (tester) async {
    Widget card(Size size) => host(
      SizedBox(
        width: size.width,
        height: size.height,
        child: shell(ReadingHeatmapView(summary: buildReadingHeatmap(samples))),
      ),
    );
    await tester.pumpWidget(card(const Size(240, 384)));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('6 小时/格'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(InsightDetailButton)).dy,
      closeTo(tester.getCenter(find.text('阅读洞察')).dy, 1),
    );
    expect(
      tester.getRect(find.byType(InsightDetailButton)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CardHeaderActions)).top),
    );
    for (final day in weekdayLabels) {
      expect(find.text(day), findsOneWidget);
    }
    await tester.pumpWidget(card(const Size(240, 192)));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    final rect = tester.getRect(find.byType(CollapsibleCard));
    await tester.tap(find.byType(InsightDetailButton));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(find.byType(ReadingHeatmapView), findsNWidgets(2));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(CollapsibleCard)), rect);
    expect(tester.takeException(), isNull);
  });
  testWidgets('移除、替换正文和销毁卡片会清理标题操作', (tester) async {
    final summary = buildReadingStreak(samples, now: now);
    Widget card(Widget child) =>
        host(SizedBox(width: 240, height: 288, child: shell(child)));
    await tester.pumpWidget(card(ReadingStreakView(summary: summary)));
    // 注册尚未完成时直接替换正文，旧发布不能重新挂回标题。
    await tester.pumpWidget(card(const Text('加载中')));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsNothing);
    await tester.pumpWidget(card(ReadingStreakView(summary: summary)));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsOneWidget);
    await tester.pumpWidget(card(const Text('没有记录')));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsNothing);
    await tester.pumpWidget(card(ReadingStreakView(summary: summary)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final entry in views().entries) {
    testWidgets('${entry.key} 窄宽卡片、大字号和不同槽高保持外框不变', (tester) async {
      for (final size in [
        const Size(180, 96),
        const Size(240, 192),
        const Size(400, 288),
        const Size(760, 384),
      ]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            host(
              SizedBox(
                width: size.width,
                height: size.height,
                child: shell(entry.value()),
              ),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(CollapsibleCard)), size);
          if (size == const Size(180, 96) &&
              (entry.key == 'streak' || entry.key == 'heatmap')) {
            expect(tester.getSize(find.byType(InsightDetailButton)).width, 32);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key}: $size scale $scale',
          );
        }
      }
    });
  }
  testWidgets('相同跨度的长短卡片宽高相同，内容刷新不推动相邻卡片', (tester) async {
    Widget grid(String text) => host(
      SizedBox(
        width: 500,
        child: Grid(
          crossAxisCount: 2,
          mainAxisExtent: 96,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            GridItem(
              crossAxisCellCount: 1,
              mainAxisCellCount: 2,
              child: KeyedSubtree(
                key: const ValueKey('short'),
                child: shell(const Text('短内容')),
              ),
            ),
            GridItem(
              crossAxisCellCount: 1,
              mainAxisCellCount: 2,
              child: KeyedSubtree(
                key: const ValueKey('long'),
                child: shell(Text(text)),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(grid('长内容\n' * 30));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byKey(const ValueKey('short')));
    final second = tester.getRect(find.byKey(const ValueKey('long')));
    expect(first.size, second.size);
    expect(first.top, second.top);
    expect(first.height, 180);
    await tester.pumpWidget(grid('更多内容\n' * 100));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('short'))), first);
    expect(tester.getRect(find.byKey(const ValueKey('long'))), second);
    expect(tester.takeException(), isNull);
  });
  testWidgets('折叠过渡保持槽位尺寸和内容状态', (tester) async {
    final childKey = GlobalKey();
    Widget card(bool expanded) => host(
      SizedBox(
        width: 240,
        height: 192,
        child: CollapsibleCard(
          cardId: 'retained',
          title: '阅读洞察',
          icon: AppGlyphs.trend,
          isExpanded: expanded,
          onToggle: () {},
          expressive: true,
          margin: EdgeInsets.zero,
          child: Text('长内容\n' * 30, key: childKey),
        ),
      ),
      animations: true,
    );
    await tester.pumpWidget(card(true));
    await tester.pumpAndSettle();
    final contentElement = childKey.currentContext;
    for (final expanded in [false, true]) {
      await tester.pumpWidget(card(expanded));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(CollapsibleCard)),
        const Size(240, 192),
      );
      expect(childKey.currentContext, same(contentElement));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('横向网格的同宽跨度不被长内容撑宽', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 500,
          height: 400,
          child: Grid(
            axisDirection: AxisDirection.right,
            crossAxisCount: 2,
            mainAxisExtent: 96,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              GridItem(
                crossAxisCellCount: 1,
                mainAxisCellCount: 2,
                child: KeyedSubtree(
                  key: const ValueKey('left'),
                  child: shell(const Text('短内容')),
                ),
              ),
              GridItem(
                crossAxisCellCount: 1,
                mainAxisCellCount: 2,
                child: KeyedSubtree(
                  key: const ValueKey('right'),
                  child: shell(Text('很长的内容' * 100)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('left'))),
      tester.getSize(find.byKey(const ValueKey('right'))),
    );
    expect(tester.getSize(find.byKey(const ValueKey('right'))).width, 180);
    expect(tester.takeException(), isNull);
  });
  testWidgets('最小跨度下编辑手柄不撑大卡片', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 240,
          height: 84,
          child: CardLayoutScope(
            editing: true,
            resizing: false,
            dragging: false,
            widthSpan: 1,
            heightSpan: 1,
            wrapHeader: (header) => header,
            onResize: (_, _) {},
            resizeHandle: const SizedBox(width: 40, height: 36),
            child: shell(const Text('内容')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CollapsibleCard)), const Size(240, 84));
    expect(tester.takeException(), isNull);
  });
  testWidgets('活跃日期支持触摸选择并显示真实记录数', (tester) async {
    final summary = buildReadingActivity(samples, now: now);
    await tester.pumpWidget(
      host(SizedBox(width: 500, child: ActivityCalendarView(summary: summary))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-12 · 2 条最后阅读记录'), findsOneWidget);
  });
  testWidgets('热力时段的键盘友好菜单复用统一弹层', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 500,
          child: ReadingHeatmapView(summary: buildReadingHeatmap(samples)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(CommonPopupMenu), findsOneWidget);
    await tester.ensureVisible(find.text('18:00').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('18:00').last);
    await tester.pumpAndSettle();
    expect(find.byType(CommonPopupMenu), findsNothing);
    expect(find.textContaining('18:00 ·'), findsOneWidget);
  });
}
