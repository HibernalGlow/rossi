/// 展墙空隙里的**封面、阅读与漫游发现类** MD3 Expressive 小组件。
///
/// 只依赖 [LibraryGapSample]（整墙条目 + 槽位尺寸 + 稳定种子）与主题 `ColorScheme`，
/// 不查库、不接全局设置。
library;

import 'package:zephyr/i18n/strings.g.dart';

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 最近一次真正碰过的那一本：有进度、或标着在读，取时间最新的一条。
LibraryEntry? continueGapEntry(List<LibraryEntry> entries) {
  LibraryEntry? best;
  int touchedAt(LibraryEntry e) => e.timestamp?.millisecondsSinceEpoch ?? 0;
  for (final entry in entries) {
    final touched = (entry.progress ?? 0) > 0 || entry.reading == true;
    if (!touched) continue;
    if (best == null || touchedAt(entry) > touchedAt(best)) best = entry;
  }
  return best;
}

/// 待看队列：在读、有进度或可直接起读的条目，按时间倒序排列。
List<LibraryEntry> readingQueueGapEntries(List<LibraryEntry> entries) {
  final pool = entries.where((e) {
    return e.reading == true ||
        (e.progress ?? 0) > 0 ||
        (e.onRead != null && e.media != null);
  }).toList();
  pool.sort((a, b) {
    final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
    final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
    return tb.compareTo(ta);
  });
  return pool;
}

/// 随机漫游条目：按槽位种子稳定抽取一张带封面的条目，优先避开「接着看」那一本。
LibraryEntry? randomGapEntry(LibraryGapSample sample) {
  final pool = sample.entries.where((e) => e.media != null).toList();
  if (pool.isEmpty) return null;
  final current = continueGapEntry(sample.entries);
  final filtered = current == null || pool.length <= 1
      ? pool
      : pool.where((e) => e.key != current.key).toList();
  final candidates = filtered.isEmpty ? pool : filtered;
  return candidates[sample.seed.abs() % candidates.length];
}

/// 尘封重温：找出时间戳最早、且与最新记录至少隔开半天的作品。
LibraryEntry? oldestGapEntry(List<LibraryEntry> entries) {
  final dated = entries.where((e) => e.timestamp != null).toList();
  if (dated.length < 2) return null;
  dated.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
  final oldest = dated.first;
  final newest = dated.last;
  if (oldest.key == newest.key) return null;
  if (newest.timestamp!.difference(oldest.timestamp!).inHours < 12) {
    return null;
  }
  return oldest;
}

final RegExp _kPageNumberPattern = RegExp(
  r'(?:P\.|第\s*)(\d+)\s*页?',
  caseSensitive: false,
);

/// 从条目中提取可展示的进度比例与页码标签（兼容历史墙只写 `subtitle: P.3` 的情况）。
(double progress, String badge) _resolveContinueProgress(LibraryEntry entry) {
  final rawProgress = entry.progress;
  final match = _kPageNumberPattern.firstMatch(
    '${entry.subtitle ?? ''} ${entry.metaText ?? ''}',
  );
  final pageNum = match == null ? null : int.tryParse(match.group(1)!);
  final total = entry.itemCount;

  if (rawProgress != null && rawProgress > 0) {
    final clamped = rawProgress.clamp(0.0, 1.0);
    final label = pageNum != null
        ? 'P.$pageNum'
        : '${(clamped * 100).round()}%';
    return (clamped, label);
  }
  if (pageNum != null && pageNum > 0) {
    if (total != null && total > 0) {
      return ((pageNum / total).clamp(0.08, 1.0), 'P.$pageNum/$total');
    }
    final fallbackRatio = (0.22 + (pageNum % 9) * 0.07).clamp(0.22, 0.82);
    return (fallbackRatio, t.workspace.seenAtPage(pageNum: pageNum));
  }
  if (entry.reading == true) {
    return (0.35, t.workspace.readingLabel);
  }
  return (0.2, t.workspace.toContinue);
}

/// 1. 「封面拼贴」：不对称圆角 + 胶囊/超椭圆错落画格 + 右下角统计胶囊。
class GapCollageBody extends StatelessWidget {
  const GapCollageBody({super.key, required this.sample});

  final LibraryGapSample sample;

  BorderRadius _cellRadius(int index, int seed) {
    return switch ((seed + index * 3) % 4) {
      0 => const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(14),
      ),
      1 => BorderRadius.circular(999),
      2 => const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      _ => BorderRadius.circular(12),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pool = sample.entries.where((e) => e.media != null).toList();
    if (pool.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 52).floor().clamp(2, 4);
        final rows = (constraints.maxHeight / 58).floor().clamp(2, 4);
        final cells = cols * rows;
        final stride = math.max(1, pool.length ~/ cells);
        final showBadge =
            constraints.maxWidth >= 100 &&
            constraints.maxHeight >= 76 &&
            MediaQuery.textScalerOf(context).scale(10) <= 1.5;

        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                for (var r = 0; r < rows; r++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var c = 0; c < cols; c++)
                          Expanded(
                            flex: (r + c).isEven && cols >= 3 ? 3 : 2,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: ClipRRect(
                                borderRadius: _cellRadius(
                                  r * cols + c,
                                  sample.seed,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                  ),
                                  child:
                                      pool[(sample.seed.abs() +
                                                  (r * cols + c) * stride) %
                                              pool.length]
                                          .media!(
                                        context,
                                        width: constraints.maxWidth / cols * 2,
                                        height:
                                            constraints.maxHeight / rows * 2,
                                        radius: BorderRadius.zero,
                                        fit: BoxFit.cover,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            if (showBadge)
              Positioned(
                right: 4,
                bottom: 4,
                child: GapPillBadge(
                  text: t.workspace.artbookCount(n: pool.length),
                  backgroundColor: scheme.primaryContainer.withValues(
                    alpha: .92,
                  ),
                  foregroundColor: scheme.onPrimaryContainer,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 2. 「接着看」：满高超椭圆封面 + 胶囊页码角标 + 双色缺口胶囊进度轨 + 多态播放徽章。
class GapContinueBody extends StatelessWidget {
  const GapContinueBody({super.key, required this.entry, required this.seed});

  final LibraryEntry entry;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (progress, badgeText) = _resolveContinueProgress(entry);
    final media = entry.media;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isVerticalPoster = h >= 132 && w < h * 1.05 && textScale <= 1.3;

        if (isVerticalPoster) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (media != null) ...[
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(16),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        media(
                          context,
                          width: w * 1.6,
                          height: h,
                          radius: BorderRadius.zero,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: GapPillBadge(
                            text: badgeText,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 5),
              _ExpressiveSegmentedTrack(
                progress: progress,
                activeColor: scheme.primary,
                trackColor: scheme.onPrimaryContainer.withValues(alpha: .18),
                height: 6,
              ),
            ],
          );
        }

        final showThumb = media != null && w >= 104 && h >= 42;
        final thumbWidth =
            (h * 0.78).clamp(36.0, math.min(72.0, w * 0.34)).toDouble();
        final showActionBadge = w >= 168 && h >= 52 && textScale <= 1.35;
        final showSubtitlePill = h >= 68 && textScale <= 1.3;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showThumb) ...[
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(5),
                  bottomRight: Radius.circular(14),
                ),
                child: SizedBox(
                  width: thumbWidth,
                  child: media(
                    context,
                    width: thumbWidth * 2,
                    height: h * 2,
                    radius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (showSubtitlePill)
                    Row(
                      children: [
                        Flexible(
                          child: GapPillBadge(
                            text: badgeText,
                            backgroundColor: scheme.primary.withValues(
                              alpha: .18,
                            ),
                            foregroundColor: scheme.onPrimaryContainer,
                          ),
                        ),
                        if (entry.subtitle != null &&
                            entry.subtitle!.isNotEmpty &&
                            w >= 210) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              entry.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer.withValues(
                                  alpha: .76,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        entry.title,
                        maxLines: h >= 58 && textScale <= 1.35 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: textScale > 1.4 ? 10.5 : 12.5,
                          height: 1.22,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  if (h >= 38)
                    _ExpressiveSegmentedTrack(
                      progress: progress,
                      activeColor: scheme.primary,
                      trackColor: scheme.onPrimaryContainer.withValues(
                        alpha: .2,
                      ),
                      height: h >= 64 ? 6.5 : 5.0,
                    ),
                ],
              ),
            ),
            if (showActionBadge) ...[
              const SizedBox(width: 8),
              Center(
                child: GapShapeBadge(
                  glyph: AppGlyphs.playCircle,
                  seed: seed ^ 0x3c6ef372,
                  size: (h * 0.56).clamp(28.0, 38.0),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: ExpressiveButtonShape.cookie6Sided,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 3. 「随机漫游」：用多边形/拱门视窗裁切封面 + 作品推荐卡片。
class GapRandomPickBody extends StatelessWidget {
  const GapRandomPickBody({super.key, required this.entry, required this.seed});

  final LibraryEntry? entry;
  final int seed;

  static const _frameShapes = <ExpressiveButtonShape>[
    ExpressiveButtonShape.arch,
    ExpressiveButtonShape.cookie4Sided,
    ExpressiveButtonShape.clover4Leaf,
    ExpressiveButtonShape.pentagon,
    ExpressiveButtonShape.slanted,
  ];

  @override
  Widget build(BuildContext context) {
    final target = entry;
    if (target == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final media = target.media;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final frameShape = _frameShapes[seed.abs() % _frameShapes.length];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showCover = media != null && w >= 96 && h >= 40;
        final thumbSide = math.min(h * 0.88, w * 0.36).clamp(32.0, 74.0);
        final meta = target.subtitle?.trim().isNotEmpty == true
            ? target.subtitle!
            : (target.section ?? t.workspace.imFeelingLucky);

        return Row(
          children: [
            if (showCover) ...[
              SizedBox(
                width: thumbSide,
                height: thumbSide,
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: ExpressiveMorphBorder(
                      from: frameShape,
                      to: frameShape,
                    ),
                  ),
                  child: media(
                    context,
                    width: thumbSide * 2,
                    height: thumbSide * 2,
                    radius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      target.title,
                      maxLines: h >= 56 && textScale <= 1.35 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: textScale > 1.4 ? 10.5 : 12,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (h >= 54 && textScale <= 1.35) ...[
                    const SizedBox(height: 4),
                    GapPillBadge(
                      text: meta,
                      backgroundColor: scheme.secondary.withValues(alpha: .16),
                      foregroundColor: scheme.onSecondaryContainer,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 4. 「待看叠卡」：错位扇形叠放的 3 张封面 + 待看统计与首部标题。
class GapReadingQueueBody extends StatelessWidget {
  const GapReadingQueueBody({super.key, required this.queue});

  final List<LibraryEntry> queue;

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final covers = queue.where((e) => e.media != null).take(3).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showStack = covers.isNotEmpty && w >= 112 && h >= 44;
        final cardH = (h * 0.86).clamp(32.0, 68.0);
        final cardW = (cardH * 0.74).clamp(24.0, 50.0);
        final stackW = showStack
            ? (cardW + (covers.length - 1) * 12.0).clamp(28.0, w * 0.42)
            : 0.0;

        return Row(
          children: [
            if (showStack) ...[
              SizedBox(
                width: stackW,
                height: cardH,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    for (var i = covers.length - 1; i >= 0; i--)
                      Positioned(
                        left: i * 10.0,
                        child: Transform.rotate(
                          angle: (i - 0.5) * 0.08,
                          child: Container(
                            width: cardW,
                            height: cardH * (1 - i * 0.06),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.surfaceContainerHighest,
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: covers[i].media!(
                              context,
                              width: cardW * 2,
                              height: cardH * 2,
                              radius: BorderRadius.zero,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(48.0, w - stackW - 12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${queue.length}',
                            style: TextStyle(
                              fontSize: textScale > 1.4 ? 18 : 22,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              color: scheme.onTertiaryContainer,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            t.workspace.booksQueued,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scheme.onTertiaryContainer.withValues(
                                alpha: .82,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (h >= 50) ...[
                        const SizedBox(height: 3),
                        Text(
                          queue.first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onTertiaryContainer.withValues(
                              alpha: .78,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 5. 「尘封重温」：最早一条记录的时光胶囊。
class GapRediscoverBody extends StatelessWidget {
  const GapRediscoverBody({super.key, required this.entry});

  final LibraryEntry? entry;

  String _ageLabel(DateTime? at) {
    if (at == null) return t.workspace.earlyFavourites;
    final days = DateTime.now().difference(at).inDays.abs();
    if (days >= 30) return t.workspace.monthsAgo(months: days ~/ 30);
    if (days >= 1) return '$days 天前';
    return '${at.month}/${at.day}';
  }

  @override
  Widget build(BuildContext context) {
    final target = entry;
    if (target == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final media = target.media;
    final age = _ageLabel(target.timestamp);
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final showCover = media != null && w >= 104 && h >= 42;
        final side = math.min(h * 0.85, w * 0.34).clamp(30.0, 64.0);

        return Row(
          children: [
            if (showCover) ...[
              SizedBox(
                width: side,
                height: side,
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: const ExpressiveMorphBorder(
                      from: ExpressiveButtonShape.cookie7Sided,
                      to: ExpressiveButtonShape.cookie7Sided,
                    ),
                  ),
                  child: media(
                    context,
                    width: side * 2,
                    height: side * 2,
                    radius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (h >= 52 && textScale <= 1.35) ...[
                    GapPillBadge(
                      text: age,
                      backgroundColor: scheme.tertiary.withValues(alpha: .18),
                      foregroundColor: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(height: 3),
                  ],
                  Flexible(
                    child: Text(
                      target.title,
                      maxLines: h >= 58 && textScale <= 1.3 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: textScale > 1.4 ? 10.5 : 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// MD3 Expressive 双段缺口胶囊进度轨：已读胶囊与剩余轨道之间留 `3.5dp` 呼吸间距。
class _ExpressiveSegmentedTrack extends StatelessWidget {
  const _ExpressiveSegmentedTrack({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    this.height = 6,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.06, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (maxW <= 12) return const SizedBox.shrink();
        final activeW = (maxW * p).clamp(height, maxW);
        final hasRemainder = maxW - activeW > height + 4;
        return SizedBox(
          height: height,
          child: Row(
            children: [
              Container(
                width: hasRemainder ? activeW - 2 : maxW,
                height: height,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              if (hasRemainder) ...[
                const SizedBox(width: 3.5),
                Expanded(
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
