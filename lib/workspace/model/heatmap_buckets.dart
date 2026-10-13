import 'package:zephyr/workspace/model/history_insights.dart';

/// 只合并展示列，保留全部七个星期；每条记录仍计入一个格子。
class HeatmapBucket {
  const HeatmapBucket({
    required this.weekday,
    required this.firstHour,
    required this.hours,
    required this.count,
  });
  final int weekday;
  final int firstHour;
  final int hours;
  final int count;
  String get range =>
      '${firstHour.toString().padLeft(2, '0')}:00–${(firstHour + hours).toString().padLeft(2, '0')}:00';
  String get label => '${weekdayFullLabels[weekday]} $range：$count 条记录';
}

List<HeatmapBucket> heatmapBuckets(ReadingHeatmapSummary summary, int hours) {
  assert(hours > 0 && 24 % hours == 0);
  return [
    for (var day = 0; day < 7; day++)
      for (var first = 0; first < 24; first += hours)
        HeatmapBucket(
          weekday: day,
          firstHour: first,
          hours: hours,
          count: summary.cells
              .sublist(day * 24 + first, day * 24 + first + hours)
              .fold(0, (sum, cell) => sum + cell.count),
        ),
  ];
}
