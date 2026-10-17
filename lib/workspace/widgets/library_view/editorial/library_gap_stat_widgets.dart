/// 展墙空隙里的**标签、创作者、进度、篇幅与来源构成类** MD3 Expressive 小组件。
library;

import 'package:zephyr/i18n/strings.g.dart';

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 高频标签列表。
List<MapEntry<String, int>> topGapTags(List<LibraryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    for (final raw in e.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  return counts.entries.toList()..sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount == 0 ? a.key.compareTo(b.key) : byCount;
  });
}

final RegExp _kBracketTokenPattern = RegExp(r'\[([^\[\]]{2,28})\]');
final RegExp _kIgnoredBracketToken = RegExp(
  r'^(DL版|數位版|デジタル版|中国翻訳|中国語|中文|汉化|漢化|個人漢化|个人汉化|無修正|无修正|完全版|合集|\d+.*|[A-Z0-9_-]{5,})$',
  caseSensitive: false,
);

/// 提取高频创作者 / 社团（从标题 `[社团 (作者)]` 聚合）。
List<MapEntry<String, int>> topGapCreators(List<LibraryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    final matches = _kBracketTokenPattern.allMatches(e.title);
    for (final m in matches) {
      final raw = m.group(1)?.trim() ?? '';
      if (raw.isEmpty || _kIgnoredBracketToken.hasMatch(raw)) continue;
      if (raw.contains('汉化') ||
          raw.contains(t.workspace.chineseLocalized) ||
          raw.contains(t.workspace.jpTranslated)) {
        continue;
      }
      counts[raw] = (counts[raw] ?? 0) + 1;
      break;
    }
  }
  return counts.entries.toList()..sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount == 0 ? a.key.compareTo(b.key) : byCount;
  });
}

final RegExp _kSubtitlePageCount = RegExp(
  r'(?:P\.|第\s*)(\d+)\s*页?',
  caseSensitive: false,
);

/// 提取每条内容的页数/子项数（优先读 `itemCount`，其次解析副标题里的 `P.13`）。
List<int> pageScaleGapCounts(List<LibraryEntry> entries) {
  final result = <int>[];
  for (final e in entries) {
    final direct = e.itemCount;
    if (direct != null && direct > 0) {
      result.add(direct);
      continue;
    }
    final sub = e.subtitle;
    if (sub != null) {
      final m = _kSubtitlePageCount.firstMatch(sub);
      final parsed = m == null ? null : int.tryParse(m.group(1)!);
      if (parsed != null && parsed > 0) result.add(parsed);
    }
  }
  return result;
}

/// 来源构成聚合。
Map<String, int> sourceGapCounts(List<LibraryEntry> entries) {
  final map = <String, int>{};
  for (final entry in entries) {
    final name = entry.section ?? entry.metaText;
    if (name == null || name.isEmpty) continue;
    map[name] = (map[name] ?? 0) + 1;
  }
  return map;
}

/// 1. 「高频标签」：胶囊与超椭圆混排的 MD3E 撞色标签云。
class GapTagsBody extends StatelessWidget {
  const GapTagsBody({super.key, required this.tags});

  final List<MapEntry<String, int>> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final palette = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.surfaceContainerHighest, scheme.onSurface),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxItems = constraints.maxHeight >= 96
            ? 4
            : constraints.maxHeight >= 64
            ? 3
            : 2;
        final shown = tags.take(maxItems).toList();

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(88.0, constraints.maxWidth),
            ),
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (var i = 0; i < shown.length; i++)
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: palette[i % palette.length].$1,
                      shape: i.isEven
                          ? const StadiumBorder()
                          : const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(11),
                                topRight: Radius.circular(11),
                                bottomLeft: Radius.circular(3),
                                bottomRight: Radius.circular(11),
                              ),
                            ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      // 胶囊在最小槽位 + 2 倍字号下会超出自身宽度：
                      // 先在胶囊内部等比缩到装得下，避免把结尾的计数挤掉。
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(
                                  52.0,
                                  constraints.maxWidth * 0.62,
                                ),
                              ),
                              child: Text(
                                shown[i].key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: palette[i % palette.length].$2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '×${shown[i].value}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: palette[i % palette.length].$2
                                    .withValues(alpha: .72),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
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

/// 2. 「常看创作者」：从标题 `[作者/社团]` 提取的创作者胶囊榜。
class GapCreatorsBody extends StatelessWidget {
  const GapCreatorsBody({super.key, required this.creators});

  final List<MapEntry<String, int>> creators;

  @override
  Widget build(BuildContext context) {
    if (creators.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final top = creators.take(2).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(88.0, constraints.maxWidth),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: i == 0
                          ? scheme.tertiaryContainer
                          : scheme.surfaceContainerHighest,
                      shape: const StadiumBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(
                                  58.0,
                                  constraints.maxWidth * 0.68,
                                ),
                              ),
                              child: Text(
                                top[i].key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: i == 0
                                      ? scheme.onTertiaryContainer
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              t.workspace.worksCount(n: top[i].value),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color:
                                    (i == 0
                                            ? scheme.onTertiaryContainer
                                            : scheme.onSurfaceVariant)
                                        .withValues(alpha: .78),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 3. 「在读进度」：圆头缺口弧形仪表盘 + 在读状态胶囊。
class GapProgressBody extends StatelessWidget {
  const GapProgressBody({
    super.key,
    required this.progress,
    required this.active,
    required this.counted,
  });

  final double progress;
  final int active;
  final int counted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownProgress = progress > 0
        ? progress.clamp(0.0, 1.0)
        : (active > 0 ? 0.32 : 0.0);
    final pct = (shownProgress * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final ringSide = math
            .min(constraints.maxHeight * 0.88, 40.0)
            .clamp(26.0, 42.0);
        return Row(
          children: [
            SizedBox(
              width: ringSide,
              height: ringSide,
              child: CustomPaint(
                painter: _ExpressiveRingPainter(
                  progress: shownProgress,
                  activeColor: scheme.primary,
                  trackColor: scheme.primary.withValues(alpha: .2),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        '$pct%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active > 0 ? '$active 本在读' : '$counted 本有进度',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      active > 0 ? '平均进度 $pct%' : t.workspace.resumeLastReading,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer.withValues(alpha: .76),
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

class _ExpressiveRingPainter extends CustomPainter {
  const _ExpressiveRingPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroke = (size.shortestSide * 0.13).clamp(3.2, 5.2);
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = activeColor;

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.02) {
      canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);
      return;
    }
    const startAngle = -math.pi / 2;
    const gapAngle = 0.24;
    final sweep = (math.pi * 2 - gapAngle * 2) * p;
    canvas.drawArc(rect, startAngle, sweep, false, activePaint);
    if (p < 0.96) {
      canvas.drawArc(
        rect,
        startAngle + sweep + gapAngle,
        math.max(0.1, math.pi * 2 - sweep - gapAngle * 2),
        false,
        trackPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExpressiveRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor;
}

/// 4. 「篇幅分布」：平均页数与峰值页数。
class GapPageScaleBody extends StatelessWidget {
  const GapPageScaleBody({super.key, required this.pages});

  final List<int> pages;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final total = pages.fold<int>(0, (a, b) => a + b);
    final avg = (total / pages.length).round();
    final maxPage = pages.reduce(math.max);
    return GapExpressiveMetricBody(
      value: '$avg',
      unit: t.workspace.avgPagesPerBook,
      pillText: t.workspace.highestPage(value: maxPage),
    );
  }
}

/// 5. 「来源构成」：带缺口的圆角分段比例条 + 双色来源胶囊。
class GapSourceBody extends StatelessWidget {
  const GapSourceBody({super.key, required this.sources});

  final Map<String, int> sources;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
    ];
    final top = sources.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(tones.length).toList();
    final total = shown.fold<int>(0, (a, e) => a + e.value);
    if (total == 0) return const SizedBox.shrink();
    final lead = shown.first;
    final second = shown.length > 1 ? shown[1] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  flex: shown[i].value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tones[i % tones.length].withValues(alpha: .86),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tones.first,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${lead.key} ${math.max(1, (lead.value * 100 / total)).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (second != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tones[1],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${second.key} ${math.max(1, (second.value * 100 / total)).round()}%',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
