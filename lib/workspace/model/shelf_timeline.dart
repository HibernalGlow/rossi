/// 时间线视图的分组与日期文案。
///
/// 刻意不 import Flutter、不 import 视图层：这一段是「哪些条目算同一天、
/// 那一天叫什么」的纯函数，判据要能 `dart run` 跑完（同 `shelf_library_query.dart`
/// 的理由 —— 本机的 `flutter test` 要拖起整棵工作台）。
///
/// # 为什么时间线不做成 `LibraryViewMode` 的第七档
///
/// `LibraryViewMode` 与 Rust 侧 `FileManagerViewMode` 是**一一对应**的
/// （`rust/local_core/src/file_manager/types.rs`，并且有一条往返测试钉着六种模式）。
/// 加一档会连带：文件管理器的视图菜单里冒出一个「时间线」（那里根本没有
/// 「阅读时间」这个概念）、Dart↔Rust 的映射表要补一支、`LibraryEntrySurface`
/// 的六路 switch 要补第七路 —— 为了一个书架专属的东西去动三家共用的行契约，
/// 代价与收益不对。所以时间线是书架本地的一档**开关**，见 `ShelfListToolbar.timelineOn`。
library;

/// 一个「按本地日历日」切出来的段。
class ShelfTimelineDay {
  const ShelfTimelineDay({required this.dayStart, required this.indexes});

  /// 这一天的本地零点。用来算文案与比较，不拿它当键（`DateTime` 相等比较带微秒）。
  final DateTime dayStart;

  /// 属于这一天的条目在**输入序列里的下标**，保持输入的顺序。
  final List<int> indexes;
}

/// 本地日历日的零点。
///
/// **刻意用本地时间而不是 UTC**：一条 23:50 读的记录被切到「明天」，
/// 用户看到的是「这本书我明天读过」—— 分组按用户的日历，不按服务器的日历。
DateTime shelfDayStart(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 把**已经排好序**的条目时间切成一天的段。
///
/// 相邻同天才合并：输入没有排序时（比如用户按标题排完又开了时间线），
/// 同一个日期会出现在两段里 —— 这是刻意的，比「悄悄把不相邻的同类项捏到一起」
/// 更诚实，调用方要一天的段连续就该先按时间排。
List<ShelfTimelineDay> groupShelfTimelineByDay(List<DateTime> times) {
  final days = <ShelfTimelineDay>[];
  for (var index = 0; index < times.length; index++) {
    final day = shelfDayStart(times[index]);
    final last = days.isEmpty ? null : days.last;
    if (last != null && shelfDayStart(last.dayStart) == day) {
      days[days.length - 1] = ShelfTimelineDay(
        dayStart: last.dayStart,
        indexes: [...last.indexes, index],
      );
      continue;
    }
    days.add(ShelfTimelineDay(dayStart: day, indexes: [index]));
  }
  return days;
}

/// 某一天的段头文案：今天 / 昨天 / 「3月5日」/ 「2025年12月1日」。
///
/// 跨年必须带年份：时间线会一路翻到几年前，只写「1月3日」看不出是哪一年，
/// 而「2025年12月1日」在同年里又啰嗦 —— 所以只在跨年时才加年份。
///
/// [now] 由调用方注入（卡片传 `DateTime.now()`，判据传一个固定时刻），
/// 否则「今天」这条断言会在午夜两侧随机红。
String shelfTimelineDayLabel(
  DateTime day, {
  required DateTime now,
  String today = '今天',
  String yesterday = '昨天',
}) {
  final target = shelfDayStart(day);
  final reference = shelfDayStart(now);
  // 日历日之差**必须按 UTC 零点算**，不能拿两个本地零点相减再取 `inDays`：
  // 有夏令时的时区里「昨天到今天」可能是 23 或 25 小时，`inDays` 向下取整
  // 就把「昨天」读成「今天」。按年月日重建 UTC 零点，差值永远是 24 的整数倍，
  // 与本机时区无关。
  final daysApart = DateTime.utc(
    reference.year,
    reference.month,
    reference.day,
  ).difference(DateTime.utc(target.year, target.month, target.day)).inDays;
  if (daysApart == 0) return today;
  if (daysApart == 1) return yesterday;
  // 往前跨到去年、或者往后（导入了一条未来时间的记录）都要能认出「不是今年」。
  if (target.year != reference.year) {
    return '${target.year}年${target.month}月${target.day}日';
  }
  return '${target.month}月${target.day}日';
}
