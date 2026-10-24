import 'package:zephyr/workspace/model/history_insights.dart';

/// 「近 N 周」**逐日**计数的纯聚合 —— 移动端首页那条热力窄条的数据。
///
/// 洞察面板已有的聚合各有自己的口径:`buildDailyTrend` 只看 7 天,
/// `buildReadingActivity` 是 28 日窗口还带时段/来源拆分;首页这条
/// 「近 12 周」的窄条要的只是**逐日一格**、按周对齐、今天收尾,
/// 单独一个纯函数比硬套 28 日结构诚实。与其它聚合一样吃同一个
/// 有界窗口(`HistoryInsightsWindow`),不扫全库。
///
/// 刻意不 import Flutter:输入是事件、输出是整数数组,
/// `flutter test` 直接断言,不需要起 widget。
class WeekHeatline {
  /// 逐日访问次数,长度恒为 [buildWeekHeatline] 的 `weeks * 7`,
  /// **从最老一天排到今天**(今天一定是最后一格)。
  final List<int> counts;

  /// 最大单日计数,至少为 1(空数据时避免除以零)。
  final int maxCount;

  const WeekHeatline({required this.counts, required this.maxCount});

  /// 一格的显示层级:0 = 没有记录,1..4 = 按占最大值的比例分四档。
  int levelAt(int index) {
    final count = counts[index];
    if (count <= 0) return 0;
    final ratio = count / maxCount;
    if (ratio <= 0.25) return 1;
    if (ratio <= 0.5) return 2;
    if (ratio <= 0.75) return 3;
    return 4;
  }
}

/// 取「最近 [weeks] 周」的逐日计数:窗口是**从今天往前数 `weeks * 7` 天**
/// 的连续日历日,今天永远收尾(条的最右一格 = 今天)。
///
/// 「哪一天」按**本地时区**的日历日算(与 `buildReadingStreak` 的
/// 连续判定同一条口径):事件时间先转本地再取 y/m/d。
WeekHeatline buildWeekHeatline(
  List<HistoryInsightEvent> events, {
  required DateTime now,
  int weeks = 12,
}) {
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  final totalDays = weeks * 7;
  final start = today.subtract(Duration(days: totalDays - 1));

  final counts = List<int>.filled(totalDays, 0);
  for (final event in events) {
    final at = event.at.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    final index = day.difference(start).inDays;
    if (index >= 0 && index < totalDays) {
      counts[index] += 1;
    }
  }

  var maxCount = 1;
  for (final count in counts) {
    if (count > maxCount) maxCount = count;
  }
  return WeekHeatline(counts: counts, maxCount: maxCount);
}
