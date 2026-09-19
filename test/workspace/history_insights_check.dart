// 历史洞察四份聚合的**纯 Dart** 判据。
//
//   dart run test/workspace/history_insights_check.dart
//
// 断言的是「算错了不会报错、只会给出一个看起来很合理的错数字」的那几处：
//
//   1. **周边界** —— 近 7 日窗口必须含今天、且正好 7 格，对比窗口是再往前 7 天；
//      少了今天，卡片会在每天凌晨把自己统计没了。
//   2. **连续的定义** —— 断一天要归 1，而「昨天读过、今天还没读」**不能**算断；
//      跨月/跨年那两天必须连上（它们是日历上的相邻日）。
//   3. **热力格的编号** —— 周日必须落在第 0 行。直接拿 `weekday` 当下标不会崩，
//      只会让整张图错一行，而错一行的热力图照样「看起来对」。
//   4. **来源分类** —— 本地判定要用 `isLocalComicSource`，插件名不能被当成在线；
//      同一份数据的次序必须稳定，否则每次刷新条形会自己重排。
//
// 没有 package:test 依赖（跟 `shelf_entry_menu_check.dart` 同一套路：这个外壳里
// `dart run` 稳，`flutter test` 要拖起整套 binding）。失败抛 StateError 并以
// 非零码退出。
//
// ignore_for_file: avoid_print

import 'package:zephyr/workspace/model/history_insights.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

HistoryInsightEvent _event(
  DateTime at, {
  String source = 'Bika',
  String comicId = '1',
}) => HistoryInsightEvent(at: at, source: source, comicId: comicId);

void main() {
  _dailyTrend();
  _readingStreak();
  _readingHeatmap();
  _sourceBreakdown();
  _emptyWindow();
  print('OK: history insights checks passed ($_passed)');
}

void _dailyTrend() {
  // 2026-09-20 是周日。今天 + 前 6 天各 1 次，再往前 7 天里放 3 次。
  final now = DateTime(2026, 9, 20, 12);
  final events = <HistoryInsightEvent>[
    for (var offset = 0; offset <= 6; offset += 1)
      _event(DateTime(2026, 9, 20 - offset, 9)),
    _event(DateTime(2026, 9, 13, 9)),
    _event(DateTime(2026, 9, 12, 9)),
    _event(DateTime(2026, 9, 7, 9)),
  ];

  final summary = buildDailyTrend(events, now: now);
  check('近 7 日恒为 7 格', summary.days.length == 7);
  check(
    '最后一格是今天',
    summary.days.last.key == '2026-09-20',
    summary.days.last.key,
  );
  check(
    '第一格是 6 天前',
    summary.days.first.key == '2026-09-14',
    summary.days.first.key,
  );
  check(
    '今天那一格计入了今天的访问',
    summary.days.last.count == 1,
    '${summary.days.last.count}',
  );
  check('本周共 7 次', summary.currentWeek == 7, '${summary.currentWeek}');
  // 前一个 7 日窗口 = 09-07 … 09-13，命中 07/12/13 三次。
  check('对比窗口只数再往前 7 天', summary.previousWeek == 3, '${summary.previousWeek}');
  check('百分比按四舍五入', summary.deltaPercent == 133, '${summary.deltaPercent}');
  check('周日标签是「日」', summary.days.last.label == '日', summary.days.last.label);

  // 上周为 0：有访问就是 +100%，一次都没有才是 0。
  final onlyThisWeek = buildDailyTrend([
    _event(DateTime(2026, 9, 20, 9)),
  ], now: now);
  check(
    '上周为 0 且本周有访问 ⇒ +100%',
    onlyThisWeek.deltaPercent == 100,
    '${onlyThisWeek.deltaPercent}',
  );
  check(
    'maxCount 至少为 1（柱子不为除 0）',
    onlyThisWeek.maxCount == 1,
    '${onlyThisWeek.maxCount}',
  );
}

void _readingStreak() {
  final now = DateTime(2026, 9, 20, 12);

  // 09-16 … 09-20 连着读，09-18 读两次（同一天多条只算一天），中间无断档。
  final events = [
    _event(DateTime(2026, 9, 10, 8)),
    _event(DateTime(2026, 9, 16, 8)),
    _event(DateTime(2026, 9, 17, 23, 59)),
    _event(DateTime(2026, 9, 18, 1)),
    _event(DateTime(2026, 9, 18, 22)),
    _event(DateTime(2026, 9, 19, 6)),
    _event(DateTime(2026, 9, 20, 7)),
  ];

  final summary = buildReadingStreak(events, now: now);
  check('同一天多条只算一天', summary.points.length == 6, '${summary.points.length}');
  check(
    '今天读过 ⇒ 当前连续 5 天',
    summary.currentStreak == 5,
    '${summary.currentStreak}',
  );
  check('最长连续 5 天', summary.longestStreak == 5, '${summary.longestStreak}');
  check(
    '最近活跃是今天',
    summary.lastActiveDate == '2026-09-20',
    '${summary.lastActiveDate}',
  );
  check('断档后从 1 重新数', summary.points.first.value == 1);
  check(
    '断档那天回到 1（09-16 不接 09-10）',
    summary.points[1].value == 1,
    '${summary.points[1].value}',
  );

  // 昨天读过、今天还没读 ⇒ 连续**没有**断，当前连续仍按昨天那天算。
  final yesterdayLast = buildReadingStreak([
    _event(DateTime(2026, 9, 19, 20)),
    _event(DateTime(2026, 9, 18, 20)),
  ], now: now);
  check(
    '昨天读过而今天还没读 ⇒ 连续不算断',
    yesterdayLast.currentStreak == 2,
    '${yesterdayLast.currentStreak}',
  );

  // 前天读过 ⇒ 才算真断了。
  final twoDaysAgo = buildReadingStreak([
    _event(DateTime(2026, 9, 18, 20)),
  ], now: now);
  check('前天读过 ⇒ 当前连续归 0', twoDaysAgo.currentStreak == 0);
  check('最长连续仍然留着', twoDaysAgo.longestStreak == 1);

  // 跨年：12-31 → 01-01 是相邻日历日。用 dayNumber 才连得上。
  final acrossYear = buildReadingStreak([
    _event(DateTime(2025, 12, 31, 10)),
    _event(DateTime(2026, 1, 1, 10)),
  ], now: DateTime(2026, 1, 1, 23));
  check(
    '跨年那两个相邻日连成一条',
    acrossYear.longestStreak == 2,
    '${acrossYear.longestStreak}',
  );
  check(
    'maxValue 至少为 1（走势不为除 0）',
    acrossYear.maxValue >= 1 &&
        buildReadingStreak(events, now: now).maxValue == 5,
  );
}

void _readingHeatmap() {
  // 周日 09-20 的 23 点两条 + 周一 09-21 的 0 点一条。
  final summary = buildReadingHeatmap([
    _event(DateTime(2026, 9, 20, 23)),
    _event(DateTime(2026, 9, 20, 23, 30)),
    _event(DateTime(2026, 9, 21, 0, 5)),
  ]);

  check('热力格恒为 7×24', summary.cells.length == 168);
  check(
    '周日在第 0 行（weekday % 7，不是 weekday）',
    summary.cells[23].count == 2 && summary.cells[0].count == 0,
    'row0[23]=${summary.cells[23].count}',
  );
  check(
    '周一 0 点那一格是 1',
    summary.cells[24].count == 1,
    '${summary.cells[24].count}',
  );
  check('最大格计数是 2', summary.maxCount == 2, '${summary.maxCount}');
  check(
    '高峰时段指向周日 23:00',
    summary.topSlot != null &&
        summary.topSlot!.weekdayLabel == '周日' &&
        summary.topSlot!.hourLabel == '23:00',
    summary.topSlot == null
        ? 'null'
        : '${summary.topSlot!.weekdayLabel} ${summary.topSlot!.hourLabel}',
  );
  check(
    '小时标签补零',
    summary.cells[1].hourLabel == '01:00',
    summary.cells[1].hourLabel,
  );
}

void _sourceBreakdown() {
  final summary = buildSourceBreakdown([
    _event(DateTime(2026, 9, 20, 9), source: 'Bika'),
    _event(DateTime(2026, 9, 20, 9), source: 'Bika'),
    _event(DateTime(2026, 9, 20, 9), source: '禁漫'),
    // 本地：`from` 直接写着 local
    _event(DateTime(2026, 9, 20, 9), source: 'local', comicId: '/comics/a.cbz'),
    // 本地：`from` 是插件名，但 comicId 是个路径 —— 仍算本地
    _event(
      DateTime(2026, 9, 20, 9),
      source: 'unknown_plugin',
      comicId: r'D:\manga\b',
    ),
    // 在线：comicId 是 URL，不能因为带斜杠就被当成本地目录
    _event(
      DateTime(2026, 9, 20, 9),
      source: 'Bika',
      comicId: 'https://example.com/comic/1',
    ),
  ]);

  check('样本窗口按事件条数算', summary.total == 6, '${summary.total}');
  final bySource = {for (final item in summary.items) item.source: item};
  check(
    '同一图源的多次访问合并',
    bySource['Bika']?.count == 3,
    '${bySource['Bika']?.count}',
  );
  check(
    'from=local 归本地',
    bySource['本地']?.count == 2,
    '${bySource['本地']?.count}',
  );
  check('URL 的 comicId 不算本地', bySource.containsKey('Bika'));
  check('没有「未知」以外的漏项', !bySource.containsKey('未知'));
  check('次数多的排在前面', summary.items.first.source == 'Bika');
  check(
    '百分比各自四舍五入',
    bySource['Bika']?.percent == 50,
    '${bySource['Bika']?.percent}',
  );
  check(
    '同次数时按名字排（次序稳定）',
    summary.items.map((item) => item.source).join(',') == 'Bika,本地,禁漫',
    summary.items.map((item) => item.source).join(','),
  );
}

void _emptyWindow() {
  final now = DateTime(2026, 9, 20, 12);
  final trend = buildDailyTrend(const [], now: now);
  final streak = buildReadingStreak(const [], now: now);
  final heatmap = buildReadingHeatmap(const []);
  final source = buildSourceBreakdown(const []);

  check('空窗口：7 格全 0', trend.days.every((day) => day.count == 0));
  check('空窗口：百分比是 0 而不是 NaN', trend.deltaPercent == 0);
  check('空窗口：maxCount 仍是 1', trend.maxCount == 1);
  check(
    '空窗口：连续为 0 且无最近活跃日',
    streak.currentStreak == 0 && streak.lastActiveDate == null,
  );
  check('空窗口：走势为空', streak.points.isEmpty);
  check('空窗口：热力图仍铺满 168 格', heatmap.cells.length == 168);
  check('空窗口：没有高峰时段', heatmap.topSlot == null);
  check('空窗口：来源拆分为空且 total=0', source.items.isEmpty && source.total == 0);
}
