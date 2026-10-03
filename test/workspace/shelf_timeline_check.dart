// 时间线分组与日期文案的**纯 Dart** 判据。
//
//   dart run test/workspace/shelf_timeline_check.dart
//
//   # 要连夏令时那一条一起抓，换时区再跑一遍：
//   TZ=America/New_York dart run test/workspace/shelf_timeline_check.dart
//
// 钉的是四件只有把函数拆开才量得到的事：
//
//   1. **切段按本地日历日，不按时间差阈值** —— 同一天内差 1ms 不能裂成两段，
//      跨零点差 1ms 必须裂成两段。这两条必须同时成立，单独任何一条都能被
//      「用 24 小时做阈值」那种写法骗过去；
//   2. **只合并相邻的同一天** —— 输入没排序时宁可出现两段「10月3日」，
//      也不要把不相邻的条目捏到一起（那会让段里的下标不再连续，
//      而视图就是按下标去取的）；
//   3. **「昨天」必须是日历日之差为 1** —— 有夏令时的时区里两个本地零点
//      可能只差 23 小时，按 `Duration.inDays` 取整会把昨天读成今天；
//   4. **跨年才带年份** —— 时间线会一路翻到几年前，但同年里写
//      「2026年3月5日」是纯啰嗦。
//
// ignore_for_file: avoid_print

import 'package:zephyr/workspace/model/shelf_timeline.dart';

int _passed = 0;
int _failed = 0;

void check(String label, bool condition, [String? detail]) {
  if (condition) {
    _passed++;
    return;
  }
  _failed++;
  print('FAIL: $label${detail == null ? '' : ' — $detail'}');
}

/// 本地某天的一个时刻（避开零点本身，免得「零点特例」蒙对）。
DateTime _at(int year, int month, int day, {int hour = 12, int minute = 30}) {
  return DateTime(year, month, day, hour, minute);
}

List<List<int>> _groups(List<DateTime> times) {
  return [
    for (final day in groupShelfTimelineByDay(times)) day.indexes,
  ];
}

void main() {
  final now = DateTime.now();
  print(
    '环境: 时区=${now.timeZoneName} 偏移=${now.timeZoneOffset} '
    '（第 3 组断言里有一条要 TZ=America/New_York 才有杀伤力）',
  );

  // ── 1. 切段按本地日历日，不按时间差 ─────────────────────────────────────
  check('空输入 ⇒ 0 段', groupShelfTimelineByDay(const []).isEmpty);

  check(
    '单条 ⇒ 1 段 1 项',
    _groups([_at(2026, 10, 3)]).length == 1 &&
        _groups([_at(2026, 10, 3)]).single.length == 1,
  );

  final sameDay = [
    _at(2026, 10, 3, hour: 1),
    _at(2026, 10, 3, hour: 9),
    _at(2026, 10, 3, hour: 23, minute: 59),
  ];
  check(
    '同一天三条 ⇒ 1 段且保序',
    _groups(sameDay).length == 1 &&
        _groups(sameDay).single.join(',') == '0,1,2',
    _groups(sameDay).toString(),
  );

  // 阴性对照：同一天内只差 1ms —— 任何「按时间差阈值切」的写法都会在这里裂。
  final dense = [
    DateTime(2026, 10, 3, 12, 0, 0, 0),
    DateTime(2026, 10, 3, 12, 0, 0, 1),
    DateTime(2026, 10, 3, 18, 0, 0, 0),
  ];
  check(
    '同一天内差 1ms 不分裂（排除「按时间差阈值」写法）',
    _groups(dense).length == 1,
    _groups(dense).toString(),
  );

  // 阳性对照：只差 1ms 但跨了零点 —— 必须分裂，否则上一条不是白切。
  final acrossMidnight = [
    DateTime(2026, 10, 3, 23, 59, 59, 999),
    DateTime(2026, 10, 4, 0, 0, 0, 0),
  ];
  check(
    '跨零点只差 1ms 必须分成两段',
    _groups(acrossMidnight).length == 2 &&
        _groups(acrossMidnight)[0].join() == '0' &&
        _groups(acrossMidnight)[1].join() == '1',
    _groups(acrossMidnight).toString(),
  );

  // ── 2. 只合并相邻的同一天 ───────────────────────────────────────────────
  final interleaved = [
    _at(2026, 10, 3),
    _at(2026, 10, 4),
    _at(2026, 10, 3),
  ];
  final interleavedGroups = _groups(interleaved);
  check(
    '不相邻的同一天 ⇒ 两段（不悄悄捏合）',
    interleavedGroups.length == 3 &&
        interleavedGroups[0].join() == '0' &&
        interleavedGroups[2].join() == '2',
    interleavedGroups.toString(),
  );
  check(
    '段的 dayStart 与首条同一天',
    shelfDayStart(interleaved[1]) ==
        groupShelfTimelineByDay(interleaved)[1].dayStart,
  );

  // ── 3. 本地日历日：不变式与时区无关 ─────────────────────────────────────
  final samples = [
    DateTime.utc(2026, 10, 2, 17, 0),
    DateTime.utc(2026, 10, 3, 23, 30),
    now,
  ];
  for (final sample in samples) {
    final start = shelfDayStart(sample);
    final local = sample.toLocal();
    check(
      'dayStart 落在本地那一天（${sample.toIso8601String()}）',
      start.year == local.year &&
          start.month == local.month &&
          start.day == local.day &&
          start.hour == 0 &&
          start.minute == 0 &&
          start.second == 0 &&
          start.millisecond == 0,
      '得到 $start，本地是 $local',
    );
  }
  // 阳性对照：只要本机不是 UTC，就得有一个样本的 UTC 日号与本地日号不同 ——
  // 否则上面那三条其实没在检查「有没有 toLocal」。
  //
  // 取哪个时刻**要按偏移的符号挑**：东半球拿本地凌晨、西半球拿本地深夜，
  // 才一定跨过 UTC 的日界。写死一个时刻的写法在另一个时区里会静默失去
  // 杀伤力 —— 本机 CST 下全绿，换 `TZ=America/New_York` 就红，正是这条暴露的。
  final offset = DateTime.now().timeZoneOffset;
  if (offset.inMinutes != 0) {
    final crossing = offset.isNegative
        ? DateTime(2026, 10, 3, 23, 30)
        : DateTime(2026, 10, 3, 0, 30);
    check(
      'dayStart 落在本地那一天（跨 UTC 日界的那个样本）',
      shelfDayStart(crossing).day == crossing.toLocal().day,
    );
    check(
      '非 UTC 时区下确实有样本的日号与 UTC 日号不同',
      shelfDayStart(crossing).day != crossing.toUtc().day,
      '偏移 $offset，本地 ${crossing.toIso8601String()} → '
          'UTC ${crossing.toUtc().toIso8601String()}',
    );
  }

  // ── 4. 日期文案 ─────────────────────────────────────────────────────────
  final reference = DateTime(2026, 10, 3, 23, 59);
  check(
    '同一天 ⇒ 今天（now 带时分秒也要成立）',
    shelfTimelineDayLabel(DateTime(2026, 10, 3, 0, 1), now: reference) == '今天',
  );
  check(
    '差一个日历日 ⇒ 昨天',
    shelfTimelineDayLabel(DateTime(2026, 10, 2), now: reference) == '昨天',
  );
  // 阳性对照：差两天绝不能落到「昨天」这一档。
  check(
    '差两个日历日不是昨天',
    shelfTimelineDayLabel(DateTime(2026, 10, 1), now: reference) == '10月1日',
  );
  check(
    '同年 ⇒ 不带年份',
    shelfTimelineDayLabel(DateTime(2026, 3, 5), now: reference) == '3月5日',
  );
  check(
    '跨年 ⇒ 带年份',
    shelfTimelineDayLabel(DateTime(2025, 12, 1), now: reference) ==
        '2025年12月1日',
  );
  // 闰年月界：3月1日的前一天是 2月29日，必须叫昨天而不是「2月29日」。
  check(
    '闰年 3月1日 的昨天是 2月29日',
    shelfTimelineDayLabel(
      DateTime(2028, 2, 29),
      now: DateTime(2028, 3, 1, 8, 0),
    ) ==
        '昨天',
  );
  // 夏令时界：美国 3月第二个周日「今天减昨天」本地只差 23 小时。
  // 在 TZ=America/New_York 下跑这一条才算真被检查过。
  check(
    '夏令时切换日的昨天（TZ=America/New_York 下才有杀伤力）',
    shelfTimelineDayLabel(
      DateTime(2026, 3, 8),
      now: DateTime(2026, 3, 9, 8, 0),
    ) ==
        '昨天',
  );
  check(
    '跨年且往前 ⇒ 带年份而不是负数天',
    shelfTimelineDayLabel(DateTime(2024, 10, 3), now: reference) ==
        '2024年10月3日',
  );
  // 导入了一条时间在未来（用户改过系统时钟 / 别的机器的记录）：
  // 不能崩，也不能叫「昨天」。
  final futureLabel = shelfTimelineDayLabel(DateTime(2026, 10, 9), now: reference);
  check('未来时间 ⇒ 走日期文案', futureLabel == '10月9日', futureLabel);

  print('shelf_timeline_check: $_passed checks passed, $_failed failed');
  if (_failed > 0) {
    throw StateError('$_failed 条断言未通过');
  }
}
