/// 展墙空隙里的**第二组** MD3 Expressive 小组件：收官进度、阅读热力、星期节律、
/// 收藏跨度、待读存量与下一里程碑。
///
/// 前面 19 款内置组件已经把「一面墙能说什么」铺过一轮：封面拼贴、连续天数、
/// 近 7 日、时段、标签、创作者、载体、来源……这一组补的是**进度与时间**这两个
/// 需要跨条目加总才看得见的面：多少读完了、哪几天在读、最早一条是什么时候收的、
/// 还剩多少没开始、离下一个整十还差几本。它们与既有组件同构，但互不重复 ——
/// 视觉上分别用分段条、热力网格、七柱节律、大数字指标、竖向存量池与目标条。
///
/// 约束与 [defaultLibraryGapWidgets] 完全一致：只从 [LibraryGapSample.entries]
/// 现算，不查库、不接 Bloc、不依赖宿主面板在不在，也不引入 `global_setting`。
///
/// 清单顺序就是**优先级**（见 [extraLibraryGapWidgets]）：宿主把它们接在默认
/// 套件之后，`both` 档里每面墙每款最多出现一次，装不下的槽位照旧退到随机图形。
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 追加组件套件的唯一出口。
///
/// 顺序即优先级：进度面 > 时间热力 > 星期节律 > 收藏跨度 > 待读存量 > 里程碑。
/// 返回不可变清单，宿主直接拼进自己的 `_builtin` 即可。
List<LibraryGapWidgetSpec> extraLibraryGapWidgets() =>
    List.unmodifiable(_extra);

final List<LibraryGapWidgetSpec> _extra = [
  LibraryGapWidgetSpec(
    id: 'gap_completion',
    label: t.workspace.gapCompletion,
    glyph: AppGlyphs.checkCircle,
    minWidth: 104,
    minHeight: 70,
    accepts: (s) =>
        s.entries.any((e) => (e.progress ?? 0) > 0) ||
        s.entries.any((e) => e.reading == true),
    builder: (context, s) {
      final tiers = gapCompletionTiers(s.entries);
      final total = s.entries.length;
      final percent = total == 0 ? 0 : (tiers.finished * 100 / total).round();
      return GapExpressiveShell(
        glyph: AppGlyphs.checkCircle,
        title: t.workspace.gapCompletion,
        seed: s.seed,
        tone: GapTone.primary,
        badgeText: '$percent%',
        body: GapCompletionBody(
          finished: tiers.finished,
          reading: tiers.reading,
          unread: tiers.unread,
          total: total,
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_heatmap',
    label: t.workspace.gapHeatmap,
    glyph: AppGlyphs.signalBars,
    minWidth: 132,
    minHeight: 86,
    accepts: (s) => s.entries.where((e) => e.timestamp != null).length >= 5,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.signalBars,
      title: t.workspace.gapHeatmap,
      seed: s.seed,
      tone: GapTone.surfaceHigh,
      body: GapHeatmapBody(counts: gapHeatDayCounts(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_weekday',
    label: t.workspace.gapWeekday,
    glyph: AppGlyphs.equalizer,
    minWidth: 116,
    minHeight: 74,
    accepts: (s) => s.entries.where((e) => e.timestamp != null).length >= 5,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.equalizer,
      title: t.workspace.gapWeekday,
      seed: s.seed,
      tone: GapTone.secondary,
      body: GapWeekdayBody(counts: gapWeekdayCounts(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_span',
    label: t.workspace.gapSpan,
    glyph: AppGlyphs.history,
    minWidth: 112,
    minHeight: 66,
    accepts: (s) => s.entries.where((e) => e.timestamp != null).length >= 2,
    builder: (context, s) {
      final span = gapSpanWindow(s.entries);
      final earliest = span?.earliest;
      final earliestLabel = earliest == null
          ? '—'
          : '${earliest.year}/${earliest.month}';
      return GapExpressiveShell(
        glyph: AppGlyphs.history,
        title: t.workspace.gapSpan,
        seed: s.seed,
        tone: GapTone.tertiary,
        body: GapExpressiveMetricBody(
          value: '${span?.days ?? 0}',
          unit: t.workspace.gapSpanDaysLabel,
          pillText: '${t.workspace.gapSpanEarliest} $earliestLabel',
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_unread',
    label: t.workspace.gapUnread,
    glyph: AppGlyphs.box,
    minWidth: 100,
    minHeight: 66,
    accepts: (s) => s.entries.any((e) => (e.progress ?? 0) <= 0),
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.box,
      title: t.workspace.gapUnread,
      seed: s.seed,
      tone: GapTone.secondary,
      body: GapUnreadBody(
        unread: gapUnreadCount(s.entries),
        total: s.entries.length,
      ),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_milestone',
    label: t.workspace.gapMilestone,
    glyph: AppGlyphs.target,
    minWidth: 104,
    minHeight: 62,
    accepts: (s) => s.entries.length >= 5,
    builder: (context, s) {
      final current = s.entries.length;
      return GapExpressiveShell(
        glyph: AppGlyphs.target,
        title: t.workspace.gapMilestone,
        seed: s.seed,
        tone: GapTone.surfaceHigh,
        body: GapMilestoneBody(
          current: current,
          milestone: nextGapMilestone(current),
        ),
      );
    },
  ),
];

/// 进度三档：（读完, 在读, 未读）。
///
/// 数据面只有 `progress` 与 `reading`，所以口径只能这么切：进度到顶算读完，
/// [LibraryEntry.reading] 为真的算在读，其余一律归入未读（含「有进度但不标在读」
/// 的中间态 —— 没有更多信号时，不把它硬说成在读）。
({int finished, int reading, int unread}) gapCompletionTiers(
  List<LibraryEntry> entries,
) {
  var finished = 0;
  var reading = 0;
  var unread = 0;
  for (final entry in entries) {
    final progress = (entry.progress ?? 0).clamp(0.0, 1.0);
    if (progress >= 0.999) {
      finished++;
    } else if (entry.reading == true) {
      reading++;
    } else {
      unread++;
    }
  }
  return (finished: finished, reading: reading, unread: unread);
}

/// 近 [weeks] 周（默认 8 周 = 56 格）按天计数，索引递增即时间递增，
/// 最后一格是今天。超出窗口与未来时间的条目不计。
List<int> gapHeatDayCounts(List<LibraryEntry> entries, {int weeks = 8}) {
  final total = weeks * 7;
  final counts = List.filled(total, 0);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final entry in entries) {
    final at = entry.timestamp;
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    final back = today.difference(day).inDays;
    if (back < 0 || back >= total) continue;
    counts[total - 1 - back]++;
  }
  return counts;
}

/// 周一…周日的 7 桶计数（索引 0 = 周一）。
List<int> gapWeekdayCounts(List<LibraryEntry> entries) {
  final counts = List.filled(7, 0);
  for (final entry in entries) {
    final at = entry.timestamp;
    if (at == null) continue;
    counts[at.weekday - 1]++;
  }
  return counts;
}

/// 收藏跨度：最新与最早时间差的天数，外加最早那条（给胶囊标月份用）。
/// 少于两个带时间的条目时没有「跨度」可言，返回 null。
({int days, DateTime earliest})? gapSpanWindow(List<LibraryEntry> entries) {
  DateTime? earliest;
  DateTime? latest;
  var timed = 0;
  for (final entry in entries) {
    final at = entry.timestamp;
    if (at == null) continue;
    timed++;
    if (earliest == null || at.isBefore(earliest)) earliest = at;
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  if (timed < 2 || earliest == null || latest == null) return null;
  return (days: latest.difference(earliest).inDays, earliest: earliest);
}

/// 待读存量：没有进度、或进度还停在 0 的条目数。
///
/// 与 [gapCompletionTiers] 的「未读」略有区别：这里只认「还没开始」，
/// 有进度但没标在读的中间态不算这一池。
int gapUnreadCount(List<LibraryEntry> entries) =>
    entries.where((e) => (e.progress ?? 0) <= 0).length;

/// 下一个整十（不足 100 时）或整百（100 起）里程碑，严格大于当前数量。
///
/// 52 → 60、99 → 100、100 → 200；空墙没有可数的里程碑，仍给 10 兜底。
int nextGapMilestone(int count) {
  if (count < 0) count = 0;
  final step = count < 100 ? 10 : 100;
  return (count ~/ step + 1) * step;
}

/// 周一到周日的文案，集中在 body 里按 locale 取。
List<String> _weekdayNames() => [
  t.workspace.weekdayMon,
  t.workspace.weekdayTue,
  t.workspace.weekdayWed,
  t.workspace.weekdayThu,
  t.workspace.weekdayFri,
  t.workspace.weekdaySat,
  t.workspace.weekdaySun,
];

/// 1. 「收官进度」：完成率读数 + 分段条 + 读完 / 在读 / 未读三档计数。
///
/// 与既有「在读进度」的圆环区分：这里用横向分段条讲**整面墙的收官程度**，
/// 圆环留给单本/在读占比那一款。
class GapCompletionBody extends StatelessWidget {
  const GapCompletionBody({
    super.key,
    required this.finished,
    required this.reading,
    required this.unread,
    required this.total,
  });

  final int finished;
  final int reading;
  final int unread;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final percent = total == 0 ? 0 : (finished * 100 / total).round();
    final fraction = total == 0
        ? 0.0
        : (finished / total).clamp(0.0, 1.0).toDouble();
    final tiers = <(String, int, Color)>[
      (t.workspace.gapFinishedBooks, finished, scheme.primary),
      (t.workspace.currentlyReading, reading, scheme.tertiary),
      (t.workspace.gapUnreadBooks, unread, scheme.onSurfaceVariant),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showTiers = w >= 96 && h >= 44 && textScale <= 1.6;
        final barHeight = (h * 0.16).clamp(4.0, 8.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$percent',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: barHeight,
              child: _GapShareBar(fraction: fraction, color: scheme.primary),
            ),
            if (showTiers) ...[
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < tiers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tiers[i].$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tiers[i].$1} ${tiers[i].$2}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: .82),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 2. 「阅读热力」：近 8 周 × 7 天的热力网格，按天计数上色。
///
/// 小槽位只画网格，不画图例；格子的行列由「星期几」决定，于是横向看是周、
/// 纵向看是星期。
class GapHeatmapBody extends StatelessWidget {
  const GapHeatmapBody({super.key, required this.counts});

  /// 时间递增的按天计数，最后一格是今天，长度是 7 的整数倍。
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showCaption = w >= 120 && h >= 52 && textScale <= 1.35;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: CustomPaint(
                painter: _GapHeatmapPainter(
                  counts: counts,
                  activeColor: scheme.primary,
                  emptyColor: scheme.onSurface,
                  isDark: isDark,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (showCaption) ...[
              const SizedBox(height: 3),
              Text(
                t.workspace.gapHeatWindow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 3. 「星期节律」：周一…周日 7 根柱 + 峰值星期一句。
class GapWeekdayBody extends StatelessWidget {
  const GapWeekdayBody({super.key, required this.counts});

  /// 7 桶计数，索引 0 = 周一。
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final names = _weekdayNames();
    final total = counts.fold<int>(0, (a, b) => a + b);
    final peak = counts.fold<int>(0, math.max);
    final peakIndex = total == 0 ? 0 : counts.indexOf(peak);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showLabels = w >= 100 && h >= 34 && textScale <= 1.5;
        final showPeak = total > 0 && w >= 100 && h >= 52 && textScale <= 1.4;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < counts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 0.68,
                          heightFactor: total == 0
                              ? 0.14
                              : (counts[i] == 0
                                    ? 0.14
                                    : 0.2 + 0.8 * (counts[i] / peak)),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: i == peakIndex && total > 0
                                  ? scheme.tertiary
                                  : scheme.tertiary.withValues(
                                      alpha: counts[i] == 0 ? 0.22 : 0.55,
                                    ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showLabels) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < names.length; i++)
                    Expanded(
                      child: Text(
                        names[i],
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 8.5,
                          height: 1.0,
                          fontWeight: i == peakIndex && total > 0
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: i == peakIndex && total > 0
                              ? scheme.tertiary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (showPeak) ...[
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: GapPillBadge(
                    text: '${t.workspace.peakValue} ${names[peakIndex]}',
                    backgroundColor: scheme.tertiary.withValues(alpha: .16),
                    foregroundColor: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 4. 「待读存量」：待开始数量 + 竖向存量池（占比填充）+ 「占本墙 N%」胶囊。
///
/// 与「收官进度」的横向条区分：这里竖着画一侧的池子，一眼看出这面墙还有多少
/// 没开；小槽位只留大数字与「待开始」标签。
class GapUnreadBody extends StatelessWidget {
  const GapUnreadBody({super.key, required this.unread, required this.total});

  final int unread;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final fraction = total == 0
        ? 0.0
        : (unread / total).clamp(0.0, 1.0).toDouble();
    final percent = (fraction * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showPill = w >= 96 && h >= 48 && textScale <= 1.5;
        final showPool = w >= 120 && h >= 44 && textScale <= 1.4;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$unread',
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.04,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: scheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            t.workspace.gapUnreadPool,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showPill) ...[
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: GapPillBadge(
                          text: t.workspace.sharePercent(v: percent),
                          backgroundColor: scheme.secondary.withValues(
                            alpha: .18,
                          ),
                          foregroundColor: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showPool) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 13,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction <= 0 ? 0.04 : fraction,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.secondary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 5. 「下一里程碑」：下一个整十/整百目标 + 一段通往它的进度条 + 「还差 N」胶囊。
class GapMilestoneBody extends StatelessWidget {
  const GapMilestoneBody({
    super.key,
    required this.current,
    required this.milestone,
  });

  final int current;
  final int milestone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final diff = math.max(0, milestone - current);
    final fraction = milestone <= 0
        ? 0.0
        : (current / milestone).clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showBar = w >= 48 && h >= 28;
        final showPill = w >= 80 && h >= 52 && textScale <= 1.4;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$milestone',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      t.workspace.entryCount,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showBar) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 5,
                child: _GapShareBar(fraction: fraction, color: scheme.tertiary),
              ),
            ],
            if (showPill) ...[
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: GapPillBadge(
                    text: '${t.workspace.gapMilestoneHint} $diff',
                    backgroundColor: scheme.tertiary.withValues(alpha: .16),
                    foregroundColor: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 横向占比条：圆头底轨 + 按比例填充。完成率与里程碑目标条共用，
/// 两者只靠颜色区分。
class _GapShareBar extends StatelessWidget {
  const _GapShareBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: color.withValues(alpha: .18)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 热力网格画法：8 列（周）× 7 行（星期），每格按当天计数上色。
///
/// 索引 [counts] 时间递增、最后一格是今天；行号由「今天星期几」回推，
/// 于是同一列里每一行恰好是一个星期几。用 [CustomPaint] 而不是 56 个
/// `Container`，小槽位里也不会有任何布局溢出。
class _GapHeatmapPainter extends CustomPainter {
  const _GapHeatmapPainter({
    required this.counts,
    required this.activeColor,
    required this.emptyColor,
    required this.isDark,
  });

  final List<int> counts;
  final Color activeColor;
  final Color emptyColor;
  final bool isDark;

  static const double _gap = 1.2;
  static const int _rows = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty || size.isEmpty) return;
    final columns = (counts.length / _rows).ceil();
    final cellWidth = (size.width - _gap * (columns - 1)) / columns;
    final cellHeight = (size.height - _gap * (_rows - 1)) / _rows;
    if (cellWidth <= 0 || cellHeight <= 0) return;

    final todayRow = DateTime.now().weekday - 1;
    final peak = counts.fold<int>(0, math.max);
    final empty = emptyColor.withValues(alpha: isDark ? .16 : .09);

    for (var i = 0; i < counts.length; i++) {
      final column = i ~/ _rows;
      if (column >= columns) continue;
      final row = (todayRow + i + 1) % _rows;
      final count = counts[i];
      final color = count <= 0
          ? empty
          : activeColor.withValues(
              alpha: peak == 0
                  ? 0.3
                  : (0.3 + 0.58 * (count / peak)).clamp(0.3, 0.88),
            );
      final rect = Rect.fromLTWH(
        column * (cellWidth + _gap),
        row * (cellHeight + _gap),
        cellWidth,
        cellHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(
            math.max(0.5, math.min(cellWidth, cellHeight) * 0.28),
          ),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GapHeatmapPainter oldDelegate) =>
      oldDelegate.counts != counts ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.isDark != isDark;
}
