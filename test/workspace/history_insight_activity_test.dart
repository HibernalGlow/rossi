import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/history_insight_activity.dart';

HistoryInsightEvent event(DateTime time, [String source = 'local']) =>
    HistoryInsightEvent(
      at: time,
      source: source,
      comicId: source == 'local' ? '/Comics/test.cbz' : 'comic',
    );
void main() {
  test('28 日窗口跨年，含起点与当前时刻，排除旧日和未来记录', () {
    final now = DateTime(2027, 1, 5, 12);
    final summary = buildReadingActivity([
      event(DateTime(2026, 12, 9)),
      event(DateTime(2026, 12, 8, 23, 59)),
      event(now),
      event(DateTime(2027, 1, 5, 13)),
      event(DateTime(2027, 1, 6)),
    ], now: now);
    expect(summary.days.length, 28);
    expect(summary.days.first.key, '2026-12-09');
    expect(summary.days.last.key, '2027-01-05');
    expect(summary.records, 2);
    expect(summary.activeDays, 2);
    expect(summary.sources, 1);
  });
  test('六小时分段边界与星期编号保持正确，来源大小写统一', () {
    final now = DateTime(2026, 10, 13, 23, 59);
    final summary = buildReadingActivity([
      event(DateTime(2026, 10, 12, 0), 'A16835E9-D405-4E01-8019-08E30BA6CDE2'),
      event(
        DateTime(2026, 10, 12, 5, 59),
        'a16835e9-d405-4e01-8019-08e30ba6cde2',
      ),
      event(DateTime(2026, 10, 12, 6)),
      event(DateTime(2026, 10, 12, 11, 59)),
      event(DateTime(2026, 10, 12, 12)),
      event(DateTime(2026, 10, 12, 17, 59)),
      event(DateTime(2026, 10, 12, 18)),
      event(DateTime(2026, 10, 11, 23, 59)),
    ], now: now);
    expect(summary.periods, [2, 2, 2, 2]);
    expect(summary.weekdays, [7, 0, 0, 0, 0, 0, 1]);
    expect(summary.sources, 2);
    expect(summary.activeDays, 2);
    expect(summary.busiestWeekday, 0);
    expect(
      summary.days.where((day) => day.key == '2026-10-12').single.count,
      7,
    );
  });
  test('空样本与全部过期样本不产生虚构记录或除零', () {
    final summary = buildReadingActivity([
      event(DateTime(2020)),
    ], now: DateTime(2026, 10, 13));
    expect(summary.records, 0);
    expect(summary.activeDays, 0);
    expect(summary.sources, 0);
    expect(summary.maxDay, 1);
    expect(summary.maxWeekday, 1);
    expect(summary.periods, [0, 0, 0, 0]);
    expect(() => summary.weekdays.add(1), throwsUnsupportedError);
  });
}
