import 'dart:math' as math;

import 'package:zephyr/workspace/model/history_insights.dart';

/// 最近 28 个本地日的最后阅读记录，复用现有有界历史样本，不推断会话或时长。
class ReadingActivitySummary {
  const ReadingActivitySummary({
    required this.days,
    required this.weekdays,
    required this.periods,
    required this.records,
    required this.sources,
  });
  final List<DailyTrendDay> days;

  /// 周一到周日。
  final List<int> weekdays;

  /// 00–06 / 06–12 / 12–18 / 18–24。
  final List<int> periods;
  final int records;
  final int sources;
  int get activeDays => days.where((day) => day.count > 0).length;
  int get maxDay => days.fold(1, (value, day) => math.max(value, day.count));
  int get maxWeekday => weekdays.fold(1, math.max);
  int get busiestWeekday => weekdays.indexOf(weekdays.reduce(math.max));
  int get busiestPeriod => periods.indexOf(periods.reduce(math.max));
}

ReadingActivitySummary buildReadingActivity(
  List<HistoryInsightEvent> events, {
  DateTime? now,
}) {
  final instant = (now ?? DateTime.now()).toLocal();
  final today = startOfDay(instant);
  final first = localDate(today.year, today.month, today.day - 27);
  final counts = <String, int>{};
  final weekdays = List.filled(7, 0);
  final periods = List.filled(4, 0);
  final sources = <String>{};
  var records = 0;
  for (final event in events) {
    final time = event.at.toLocal();
    if (time.isBefore(first) || time.isAfter(instant)) continue;
    final key = dayKey(time);
    counts[key] = (counts[key] ?? 0) + 1;
    weekdays[time.weekday - 1]++;
    periods[time.hour ~/ 6]++;
    sources.add(classifyHistorySource(event));
    records++;
  }
  return ReadingActivitySummary(
    days: List.unmodifiable([
      for (var offset = 27; offset >= 0; offset--)
        () {
          final day = localDate(today.year, today.month, today.day - offset);
          return DailyTrendDay(
            key: dayKey(day),
            label: '${day.month}/${day.day}',
            count: counts[dayKey(day)] ?? 0,
          );
        }(),
    ]),
    weekdays: List.unmodifiable(weekdays),
    periods: List.unmodifiable(periods),
    records: records,
    sources: sources.length,
  );
}
