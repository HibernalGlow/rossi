import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/history_week_heatline.dart';

HistoryInsightEvent event(DateTime time) =>
    HistoryInsightEvent(at: time, source: 'local', comicId: '/a.cbz');

void main() {
  // 2026-10-23 是周五(weekday = 5)。
  final now = DateTime(2026, 10, 23, 18);

  test('窗口长度恒为 weeks*7,今天收尾', () {
    final heatline = buildWeekHeatline(const [], now: now);
    expect(heatline.counts.length, 84);
    // 连续日历日:起点 = 今天往前 83 天(84 格含今天)。
    final start = DateTime(2026, 10, 23).subtract(const Duration(days: 83));
    expect(start, DateTime(2026, 8, 1));
  });

  test('事件落在窗口内按本地日历日计数,窗口外不计', () {
    final heatline = buildWeekHeatline([
      event(DateTime(2026, 10, 23, 9)),
      event(DateTime(2026, 10, 23, 23)),
      event(DateTime(2026, 10, 22, 12)),
      // 窗口起点之前 / 未来,都不计。
      event(DateTime(2026, 6, 1)),
      event(DateTime(2026, 12, 25)),
    ], now: now);
    expect(heatline.counts.last, 2, reason: '今天两笔');
    expect(heatline.counts[heatline.counts.length - 2], 1, reason: '昨天一笔');
    expect(heatline.counts.first, 0);
  });

  test('层级按占最大值的比例分四档,零记录为 0,空数据不除零', () {
    final empty = buildWeekHeatline(const [], now: now);
    expect(empty.maxCount, 1);
    expect(empty.levelAt(0), 0);

    final heatline = buildWeekHeatline([
      for (var i = 0; i < 8; i++) event(DateTime(2026, 10, 23, i)),
      for (var i = 0; i < 4; i++) event(DateTime(2026, 10, 20, i)),
      for (var i = 0; i < 2; i++) event(DateTime(2026, 10, 15, i)),
      event(DateTime(2026, 10, 10)),
    ], now: now);
    expect(heatline.maxCount, 8);
    expect(heatline.levelAt(heatline.counts.length - 1), 4); // 8/8
    expect(heatline.levelAt(heatline.counts.length - 4), 2); // 4/8 = 0.5
    expect(heatline.levelAt(heatline.counts.length - 9), 1); // 2/8 = 0.25 → l1
    expect(heatline.levelAt(heatline.counts.length - 14), 1); // 1/8 = 0.125 → l1
  });
}
