import 'dart:math' as math;

import 'package:zephyr/util/path_util.dart';

/// 历史洞察的**纯聚合**（neoview `cards/insights/reader-history-insights.ts` 的同位物）。
///
/// 本文件刻意不 import Flutter：输入只是「一段时间 + 一个来源」的事件，
/// 输出是四张卡片各自要的汇总结构 —— 于是它能被
/// `dart run test/workspace/history_insights_check.dart` 直接断言，
/// 不需要为「周几第几格」这种算错不会报错的东西起一整套 widget 测试。
///
/// 四份聚合读的是**同一个有界窗口**（最近 N 条历史），这点与 neoview 一致：
/// 洞察是「最近在读什么」，不是全库统计 —— 无界扫描既慢又没有解释力。
class HistoryInsightEvent {
  /// 这一次访问的时间（Rossi 侧即历史条目的 `lastReadAt`）。
  final DateTime at;

  /// 图源标识（插件名或 `local`）。分类见 [classifyHistorySource]。
  final String source;

  /// 漫画 id；本地条目这里就是路径，[isLocalComicSource] 要靠它认出本地。
  final String comicId;

  const HistoryInsightEvent({
    required this.at,
    required this.source,
    this.comicId = '',
  });
}

// ── 近 7 日趋势 ─────────────────────────────────────────────────────────────

class DailyTrendDay {
  final String key;
  final String label;
  final int count;

  const DailyTrendDay({
    required this.key,
    required this.label,
    required this.count,
  });
}

class DailyTrendSummary {
  /// 固定 7 项，**从 6 天前到今天**（最后一项是今天）。
  final List<DailyTrendDay> days;
  final int currentWeek;
  final int previousWeek;

  /// 相对上一个 7 天窗口的变化百分比；上周为 0 时退化为「有就读过算 +100%」。
  final int deltaPercent;

  /// 柱子归一化用的最大值，**至少为 1**（否则空数据会把柱子除以 0）。
  final int maxCount;

  const DailyTrendSummary({
    required this.days,
    required this.currentWeek,
    required this.previousWeek,
    required this.deltaPercent,
    required this.maxCount,
  });
}

DailyTrendSummary buildDailyTrend(
  List<HistoryInsightEvent> events, {
  DateTime? now,
}) {
  final today = startOfDay(now ?? DateTime.now());
  final counts = countByDayKey(events);

  final days = <DailyTrendDay>[
    for (var offset = 6; offset >= 0; offset -= 1)
      () {
        final day = localDate(today.year, today.month, today.day - offset);
        final key = dayKey(day);
        return DailyTrendDay(
          key: key,
          label: weekdayLabels[weekdayIndex(day)],
          count: counts[key] ?? 0,
        );
      }(),
  ];

  var previousWeek = 0;
  for (var offset = 13; offset >= 7; offset -= 1) {
    final day = localDate(today.year, today.month, today.day - offset);
    previousWeek += counts[dayKey(day)] ?? 0;
  }

  final currentWeek = days.fold(0, (sum, day) => sum + day.count);
  final deltaPercent = previousWeek > 0
      ? (((currentWeek - previousWeek) / previousWeek) * 100).round()
      : (currentWeek > 0 ? 100 : 0);

  return DailyTrendSummary(
    days: List.unmodifiable(days),
    currentWeek: currentWeek,
    previousWeek: previousWeek,
    deltaPercent: deltaPercent,
    maxCount: days.fold(1, (max, day) => math.max(max, day.count)),
  );
}

// ── 连续阅读 ────────────────────────────────────────────────────────────────

class ReadingStreakPoint {
  final String date;
  final String label;

  /// 走到这一天为止的连续天数（断一天就重新从 1 开始）。
  final int value;

  const ReadingStreakPoint({
    required this.date,
    required this.label,
    required this.value,
  });
}

class ReadingStreakSummary {
  /// 按日期升序，只含**有访问**的日子。
  final List<ReadingStreakPoint> points;
  final int currentStreak;
  final int longestStreak;

  /// 最近一次访问的日期键（`yyyy-MM-dd`）；一次访问都没有时为 `null`。
  final String? lastActiveDate;
  final int maxValue;

  const ReadingStreakSummary({
    required this.points,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActiveDate,
    required this.maxValue,
  });
}

ReadingStreakSummary buildReadingStreak(
  List<HistoryInsightEvent> events, {
  DateTime? now,
}) {
  final days = activeDays(events);
  final points = <ReadingStreakPoint>[];
  var running = 0;
  var longestStreak = 0;
  int? previousDayNumber;

  for (final day in days) {
    final number = dayNumber(day);
    // 只认「紧邻的下一天」。这里比的是**日历日序号**而不是两个 midday 的时差：
    // 跨夏时制的那两天差值是 23 h 或 25 h，按时长整除会得到「没连上」。
    running = previousDayNumber != null && number - previousDayNumber == 1
        ? running + 1
        : 1;
    previousDayNumber = number;
    longestStreak = math.max(longestStreak, running);
    points.add(
      ReadingStreakPoint(
        date: dayKey(day),
        label: '${day.month}/${day.day}',
        value: running,
      ),
    );
  }

  final todayNumber = dayNumber(startOfDay(now ?? DateTime.now()));
  final lastNumber = days.isEmpty ? null : dayNumber(days.last);
  // 「昨天读过」仍然算在连续里：今天还没过完，不该因为今天还没读就判连续已断。
  final currentStreak =
      lastNumber != null &&
          (lastNumber == todayNumber || lastNumber == todayNumber - 1)
      ? (points.isEmpty ? 0 : points.last.value)
      : 0;

  return ReadingStreakSummary(
    points: List.unmodifiable(points),
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    lastActiveDate: days.isEmpty ? null : dayKey(days.last),
    maxValue: math.max(longestStreak, 1),
  );
}

// ── 星期 × 小时热力 ─────────────────────────────────────────────────────────

class ReadingHeatmapCell {
  /// 0 = 周日 …… 6 = 周六（与 neoview 的 `Date.getDay()` 同一套编号）。
  final int weekday;
  final int hour;
  final int count;
  final String weekdayLabel;
  final String hourLabel;

  const ReadingHeatmapCell({
    required this.weekday,
    required this.hour,
    required this.count,
    required this.weekdayLabel,
    required this.hourLabel,
  });
}

class ReadingHeatmapSummary {
  /// 展平成 `weekday * 24 + hour`，恒为 168 项 —— 卡片按格取用，不再自己算下标。
  final List<ReadingHeatmapCell> cells;
  final int maxCount;

  /// 访问最密集的那一格；一次访问都没有时为 `null`。
  final ReadingHeatmapCell? topSlot;

  const ReadingHeatmapSummary({
    required this.cells,
    required this.maxCount,
    required this.topSlot,
  });
}

ReadingHeatmapSummary buildReadingHeatmap(List<HistoryInsightEvent> events) {
  final matrix = List.generate(7, (_) => List.filled(24, 0));
  for (final event in events) {
    matrix[weekdayIndex(event.at)][event.at.hour] += 1;
  }

  var maxCount = 0;
  ReadingHeatmapCell? topSlot;
  final cells = <ReadingHeatmapCell>[];
  for (var weekday = 0; weekday < 7; weekday += 1) {
    for (var hour = 0; hour < 24; hour += 1) {
      final count = matrix[weekday][hour];
      maxCount = math.max(maxCount, count);
      final cell = ReadingHeatmapCell(
        weekday: weekday,
        hour: hour,
        count: count,
        weekdayLabel: weekdayFullLabels[weekday],
        hourLabel: '${hour.toString().padLeft(2, '0')}:00',
      );
      if (topSlot == null || cell.count > topSlot.count) topSlot = cell;
      cells.add(cell);
    }
  }

  return ReadingHeatmapSummary(
    cells: List.unmodifiable(cells),
    maxCount: maxCount,
    topSlot: (topSlot?.count ?? 0) > 0 ? topSlot : null,
  );
}

// ── 来源拆分 ────────────────────────────────────────────────────────────────

class SourceBreakdownItem {
  final String source;
  final int count;

  /// 占样本窗口的百分比（整数，各自四舍五入 ⇒ **不保证加起来是 100**）。
  final int percent;

  const SourceBreakdownItem({
    required this.source,
    required this.count,
    required this.percent,
  });
}

class SourceBreakdownSummary {
  final int total;
  final List<SourceBreakdownItem> items;

  const SourceBreakdownSummary({required this.total, required this.items});
}

SourceBreakdownSummary buildSourceBreakdown(List<HistoryInsightEvent> events) {
  final counts = <String, int>{};
  for (final event in events) {
    final source = classifyHistorySource(event);
    counts[source] = (counts[source] ?? 0) + 1;
  }

  final total = events.length;
  final items = counts.entries.toList()
    // 次数多的在前；同次数按名字排，保证同一份数据每次渲染的次序一样。
    ..sort(
      (a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key),
    );

  return SourceBreakdownSummary(
    total: total,
    items: List.unmodifiable([
      for (final entry in items)
        SourceBreakdownItem(
          source: entry.key,
          count: entry.value,
          percent: total > 0 ? ((entry.value / total) * 100).round() : 0,
        ),
    ]),
  );
}

/// 这条历史属于哪个「来源」。
///
/// neoview 拆的是**文件类型**（压缩包 / 文件夹 / 图片……），因为它那边只有本地文件。
/// Rossi 的历史自带图源标识，所以这里拆的是**条目从哪来**：本地是一类，
/// 每个插件图源各一类。本地判定复用 [isLocalComicSource]，于是
/// 「`from` 写着插件名、comicId 却是个路径」这类历史不会被算成在线。
String classifyHistorySource(HistoryInsightEvent event) {
  if (isLocalComicSource(event.source, event.comicId)) return '本地';
  final source = event.source.trim();
  return source.isEmpty ? '未知' : source;
}

// ── 日期工具 ────────────────────────────────────────────────────────────────

const List<String> weekdayLabels = ['日', '一', '二', '三', '四', '五', '六'];
const List<String> weekdayFullLabels = [
  '周日',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
];

/// 本地日的键（`yyyy-MM-dd`）。它同时是**分组键**与卡片上的可读数。
String dayKey(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}'
    '-${time.day.toString().padLeft(2, '0')}';

/// 按**本地**日历日归零。ObjectBox 的 date 属性读出来就是本地时间，
/// 用它统计「周几几点在读」才与用户的体感一致。
DateTime startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);

/// 年月日可以是越界值（`DateTime` 会自己规整），所以「往前 7 天」不用手算借位。
DateTime localDate(int year, int month, int day) => DateTime(year, month, day);

/// 0 = 周日。Dart 的 `weekday` 是 1 = 周一 …… 7 = 周日，取模即得 neoview 的编号。
int weekdayIndex(DateTime time) => time.weekday % 7;

/// 自 UTC 纪元起的日历日序号。连续判定用它，理由见 [buildReadingStreak]。
int dayNumber(DateTime time) =>
    DateTime.utc(time.year, time.month, time.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

Map<String, int> countByDayKey(List<HistoryInsightEvent> events) {
  final counts = <String, int>{};
  for (final event in events) {
    final key = dayKey(event.at);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// 有访问的日期，按本地日历日**升序**（每个日期都是当天零点）。
List<DateTime> activeDays(List<HistoryInsightEvent> events) {
  final days = <DateTime>{};
  for (final event in events) {
    days.add(startOfDay(event.at));
  }
  return days.toList()..sort((a, b) => a.compareTo(b));
}
