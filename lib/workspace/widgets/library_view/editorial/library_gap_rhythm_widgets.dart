/// 展墙空隙里的**时间节律、连续活跃、画幅与载体分布类** MD3 Expressive 小组件。
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 连续多少天有记录。最新一天既不是今天也不是昨天时算 0 —— 断了就不报，
/// 否则一面半年没动的书签墙会永远显示「曾经连续 9 天」。
int streakGapDays(List<LibraryEntry> entries) {
  final days = <DateTime>{
    for (final e in entries)
      if (e.timestamp case final at?) DateTime(at.year, at.month, at.day),
  };
  if (days.isEmpty) return 0;
  final newest = days.reduce((a, b) => a.isAfter(b) ? a : b);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (today.difference(newest).inDays > 1) return 0;
  var streak = 0;
  while (days.contains(
    DateTime(newest.year, newest.month, newest.day - streak),
  )) {
    streak++;
  }
  return streak;
}

/// 近 [window] 天每一天是否有记录（最后一格是今天）。
List<bool> recentGapDayFlags(List<LibraryEntry> entries, [int window = 7]) {
  final days = <DateTime>{
    for (final e in entries)
      if (e.timestamp case final at?) DateTime(at.year, at.month, at.day),
  };
  if (days.isEmpty) return List.filled(window, false);
  final now = DateTime.now();
  final anchor = DateTime(now.year, now.month, now.day);
  return [
    for (var i = window - 1; i >= 0; i--)
      days.contains(DateTime(anchor.year, anchor.month, anchor.day - i)),
  ];
}

/// 按天分桶：最后一根是今天。返回（7 个计数，总数）。
(List<int>, int) weeklyGapBuckets(List<LibraryEntry> entries) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final counts = List.filled(7, 0);
  var total = 0;
  for (final entry in entries) {
    final at = entry.timestamp;
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    final back = today.difference(day).inDays;
    if (back < 0 || back > 6) continue;
    counts[6 - back]++;
    total++;
  }
  return (counts, total);
}

/// 四个时段桶（凌晨 / 上午 / 下午 / 晚上）+ 一句「多在 X」。
(List<int>, String) dayPartsGapBuckets(List<LibraryEntry> entries) {
  const names = ['凌晨', '上午', '下午', '晚上'];
  final counts = [0, 0, 0, 0];
  var total = 0;
  for (final e in entries) {
    final at = e.timestamp;
    if (at == null) continue;
    counts[at.hour ~/ 6]++;
    total++;
  }
  if (total == 0) return (counts, '暂无记录');
  var peak = 0;
  for (var i = 1; i < counts.length; i++) {
    if (counts[i] > counts[peak]) peak = i;
  }
  return (counts, '多在${names[peak]}');
}

/// 找出单日记录最多的一天：（日期文本如 `10/13`, 当日条数, 占比）。
(String dateLabel, int count, double share)? peakGapDay(
  List<LibraryEntry> entries,
) {
  final byDay = <DateTime, int>{};
  var total = 0;
  for (final e in entries) {
    final at = e.timestamp;
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    byDay[day] = (byDay[day] ?? 0) + 1;
    total++;
  }
  if (total < 3 || byDay.isEmpty) return null;
  final top = byDay.entries.reduce((a, b) => b.value > a.value ? b : a);
  final label = '${top.key.month}/${top.key.day}';
  return (label, top.value, top.value / total);
}

/// 近 3 天（今天、昨天、前天）各自的更新条数。
(int today, int yesterday, int twoDaysAgo, int total) recentThreeDayGapCounts(
  List<LibraryEntry> entries,
) {
  final now = DateTime.now();
  var d0 = 0;
  var d1 = 0;
  var d2 = 0;
  for (final e in entries) {
    final at = e.timestamp;
    if (at == null) continue;
    final diff = now.difference(at);
    if (diff.isNegative || diff >= const Duration(days: 3)) continue;
    if (diff < const Duration(days: 1)) {
      d0++;
    } else if (diff < const Duration(days: 2)) {
      d1++;
    } else {
      d2++;
    }
  }
  return (d0, d1, d2, d0 + d1 + d2);
}

/// 画幅构成：（竖幅数, 方幅数, 横幅数）。要求条目同时具备封面与宽高比。
(int portrait, int square, int landscape) aspectMixGapCounts(
  List<LibraryEntry> entries,
) {
  var portrait = 0;
  var square = 0;
  var landscape = 0;
  for (final e in entries) {
    if (e.media == null) continue;
    final ratio = e.mediaAspectRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) continue;
    if (ratio < 0.88) {
      portrait++;
    } else if (ratio <= 1.15) {
      square++;
    } else {
      landscape++;
    }
  }
  return (portrait, square, landscape);
}

final RegExp _kVideoExtPattern = RegExp(
  r'\.(mp4|mkv|webm|avi|mov|flv|m4v|ts)(\b|$)',
  caseSensitive: false,
);
final RegExp _kArchiveExtPattern = RegExp(
  r'\.(zip|cbz|rar|cbr|7z|cb7|tar|epub|pdf)(\b|$)',
  caseSensitive: false,
);

/// 载体/格式构成：从标题、副标题与分组名中提取（视频 / 归档 / 图集 / 目录 / 漫画）。
Map<String, int> mediaFormatGapCounts(List<LibraryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    if (e.media == null &&
        e.subtitle == null &&
        e.section == null &&
        e.byteSize == null) {
      continue;
    }
    final hay = '${e.title} ${e.subtitle ?? ''} ${e.section ?? ''}';
    final String kind;
    if (_kVideoExtPattern.hasMatch(hay) ||
        (e.section?.contains('视频') ?? false)) {
      kind = '视频';
    } else if (_kArchiveExtPattern.hasMatch(hay) ||
        (e.section?.contains('归档') ?? false)) {
      kind = '归档';
    } else if (e.section == '文件夹' || e.section == '收藏夹') {
      kind = '目录';
    } else if (hay.contains('Pixiv') ||
        hay.contains('图') ||
        hay.contains('P.') ||
        e.preserveMedia) {
      kind = '图集';
    } else if (e.section != null && e.section!.isNotEmpty) {
      kind = e.section!;
    } else {
      kind = '漫画';
    }
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

/// 1. 「连续天数」：大号 Display 数字 + 底部近 7 日活跃胶囊矩阵（解决竖向槽位留白）。
class GapStreakBody extends StatelessWidget {
  const GapStreakBody({super.key, required this.days, required this.weekFlags});

  final int days;
  final List<bool> weekFlags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showMatrix = h >= 58 && w >= 88 && textScale <= 1.45;
        final isTall = h >= 110 && textScale <= 1.3;
        final numberFontSize = isTall
            ? (math.min(w, h) * 0.44).clamp(32.0, 56.0)
            : 26.0;

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
                      '$days',
                      style: TextStyle(
                        fontSize: numberFontSize,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        color: scheme.onTertiaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '天有记录',
                      style: TextStyle(
                        fontSize: isTall ? 13 : 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer.withValues(
                          alpha: .84,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showMatrix) ...[
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: isTall ? 7 : 5,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < weekFlags.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: weekFlags[i]
                                ? (isTall ? 18.0 : 11.0)
                                : (isTall ? 7.0 : 5.0),
                            decoration: BoxDecoration(
                              color: weekFlags[i]
                                  ? scheme.tertiary
                                  : scheme.onTertiaryContainer.withValues(
                                      alpha: .22,
                                    ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                    ],
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

/// 2. 「近 7 日」柱状分布：胶囊圆柱 + 峰值高亮 + 胶囊计数角标。
class GapBarsBody extends StatelessWidget {
  const GapBarsBody({super.key, required this.counts, required this.caption});

  final List<int> counts;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = counts.fold(0, math.max);
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showCaption = constraints.maxWidth >= 84 && textScale <= 1.5;
        final barMaxH = math.max(8.0, constraints.maxHeight - 2);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < counts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3.5),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final ratio = peak == 0 ? 0.0 : counts[i] / peak;
                          final isPeak = peak > 0 && counts[i] == peak;
                          return Container(
                            height: math.max(
                              5.0,
                              barMaxH * (ratio == 0 ? 0.14 : ratio),
                            ),
                            decoration: BoxDecoration(
                              color: isPeak
                                  ? scheme.primary
                                  : scheme.primary.withValues(
                                      alpha: ratio == 0
                                          ? 0.18
                                          : 0.38 + 0.45 * ratio,
                                    ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showCaption) ...[
              const SizedBox(width: 7),
              Flexible(
                child: GapPillBadge(
                  text: caption,
                  backgroundColor: scheme.primary.withValues(alpha: .16),
                  foregroundColor: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 3. 「阅读时段」：凌晨/上午/下午/晚上四象限节奏胶囊。
class GapDayPartsBody extends StatelessWidget {
  const GapDayPartsBody({
    super.key,
    required this.counts,
    required this.caption,
  });

  final List<int> counts;
  final String caption;

  static const _shortNames = ['夜', '晨', '午', '晚'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = counts.fold(0, math.max);
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showCaption = constraints.maxWidth >= 92 && textScale <= 1.45;
        final showLabels =
            constraints.maxHeight >= 52 &&
            constraints.maxWidth >= 104 &&
            textScale <= 1.25;
        final barSpace = math.max(
          8.0,
          constraints.maxHeight - (showLabels ? 16.0 : 2.0),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < counts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: math.max(
                              6.0,
                              barSpace *
                                  (peak == 0
                                      ? 0.2
                                      : (counts[i] == 0
                                            ? 0.18
                                            : counts[i] / peak)),
                            ),
                            decoration: BoxDecoration(
                              color: peak > 0 && counts[i] == peak
                                  ? scheme.tertiary
                                  : scheme.tertiary.withValues(
                                      alpha: counts[i] == 0 ? 0.18 : 0.46,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          if (showLabels) ...[
                            const SizedBox(height: 2),
                            Text(
                              _shortNames[i % _shortNames.length],
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showCaption) ...[
              const SizedBox(width: 7),
              Flexible(
                child: GapPillBadge(
                  text: caption,
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 4. 「活跃峰值」：单日最高活跃记录与占比。
class GapPeakDayBody extends StatelessWidget {
  const GapPeakDayBody({super.key, required this.peak});

  final (String dateLabel, int count, double share)? peak;

  @override
  Widget build(BuildContext context) {
    final data = peak;
    if (data == null) return const SizedBox.shrink();
    return GapExpressiveMetricBody(
      value: '${data.$2}',
      unit: '${data.$1} 单日最高',
      pillText: '占 ${(data.$3 * 100).round()}%',
    );
  }
}

/// 5. 「画幅构成」：竖图 / 方图 / 横图三枚几何比例框与占比。
class GapAspectMixBody extends StatelessWidget {
  const GapAspectMixBody({
    super.key,
    required this.portrait,
    required this.square,
    required this.landscape,
  });

  final int portrait;
  final int square;
  final int landscape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = portrait + square + landscape;
    if (total <= 0) return const SizedBox.shrink();
    final items = <(String, int, double, double, Color)>[
      ('竖幅', portrait, 10, 15, scheme.primary),
      ('方幅', square, 13, 13, scheme.tertiary),
      ('横幅', landscape, 16, 10, scheme.secondary),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final showBars =
            constraints.maxHeight >= 46 &&
            MediaQuery.textScalerOf(context).scale(11) <= 1.5;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (showBars)
              SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      if (items[i].$2 > 0) ...[
                        if (i > 0 &&
                            items.take(i).any((element) => element.$2 > 0))
                          const SizedBox(width: 3),
                        Expanded(
                          flex: items[i].$2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: items[i].$5,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    for (final item in items)
                      if (item.$2 > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: item.$3,
                                height: item.$4,
                                decoration: BoxDecoration(
                                  color: item.$5.withValues(alpha: .24),
                                  borderRadius: BorderRadius.circular(3.5),
                                  border: Border.all(
                                    color: item.$5,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item.$1} ${item.$2}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 6. 「载体分布」：图集 / 视频 / 归档 / 目录的多色胶囊组合。
class GapMediaFormatBody extends StatelessWidget {
  const GapMediaFormatBody({super.key, required this.formats});

  final Map<String, int> formats;

  @override
  Widget build(BuildContext context) {
    if (formats.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final sorted = formats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = sorted.take(3).toList();
    final total = shown.fold<int>(0, (a, e) => a + e.value);
    if (total <= 0) return const SizedBox.shrink();

    final palette = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.surfaceContainerHighest, scheme.onSurface),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(88.0, constraints.maxWidth),
            ),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < shown.length; i++)
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: palette[i % palette.length].$1,
                      shape: i == 0
                          ? const StadiumBorder()
                          : RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shown[i].key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: palette[i % palette.length].$2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${shown[i].value}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: palette[i % palette.length].$2.withValues(
                                alpha: .75,
                              ),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
