/// 展墙空隙里的 **MD3 Expressive 小组件**清单与共享视觉外壳。
///
/// 两款填充（随机图形 / 小组件）解决的是同一个问题：不规则轮廓之间剩下的空白。
/// 图形是纯装饰，组件则顺手把这一墙数据的**汇总面与发现面**说一遍 —— 书签墙上的
/// 「近 7 日新增」、历史墙上的「接着看 / 待看叠卡」、本地墙上的「载体分布 / 画幅构成」
/// 本来就散在几十张卡里，没人会自己加总。
///
/// 因此这里只允许从 [LibraryGapSample.entries] 现算：不查库、不接 Bloc、
/// 不依赖宿主面板在不在，也不引入 `global_setting`。
///
/// # MD3 Expressive 视觉规范落地
///
/// 1. **色阶容器分层 ([GapTone])**：告别原先千篇一律的 `surfaceContainerLow` +
///    `0.5px` 细灰描边，按组件语义交错使用 `primaryContainer`、`secondaryContainer`、
///    `tertiaryContainer` 与 `surfaceContainerHigh` 色阶对。
/// 2. **三圆一尖非对称张力圆角**：外壳采用 `22 / 22 / 8 / 22` 非对称圆角，尖角方位随
///    槽位 `seed` 轮转，与相邻规整卡片形成几何张力。
/// 3. **撞色几何贴片底纹 ([_GapCollageBackdropPainter])**：在卡片边角绘制由 `seed`
///    决定的 `material_new_shapes` 多边形（星芒、四叶草、曲边钻、扇面、超椭圆）与
///    [ExpressiveBlob] 描边轮廓，杜绝大尺寸槽位中部出现纯黑死区。
/// 4. **多态图标座 ([GapShapeBadge]) 与胶囊徽章 ([GapPillBadge])**：标题行使用有机多边形
///    承载图标，并在空间充裕时附带右侧状态胶囊与底部微图表。
///
/// 清单顺序就是**优先级**：`both` 档里每款组件一面墙最多出现一次，
/// 于是数据越具体的组件越先认领空隙，小空隙或已用完的槽位退到随机图形。
library;

import 'dart:math' as math;

import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_media_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_rhythm_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_stat_widgets.dart';

/// 默认组件套件（书签、历史、发现、书架、本地文件都适用）。
///
/// 宿主想换一套或只留图形，走 `LibraryEditorialCanvas.gapWidgets`；
/// 这里不再开第二个注入口。
List<LibraryGapWidgetSpec> defaultLibraryGapWidgets() =>
    List.unmodifiable(_builtin);

final List<LibraryGapWidgetSpec> _builtin = [
  LibraryGapWidgetSpec(
    id: 'gap_cover_collage',
    label: '封面拼贴',
    glyph: AppGlyphs.panorama,
    minWidth: 104,
    minHeight: 104,
    accepts: (s) => s.entries.any((e) => e.media != null),
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.panorama,
      title: '封面',
      seed: s.seed,
      tone: GapTone.surfaceHigh,
      badgeText: '${s.entries.where((e) => e.media != null).length} 图',
      body: GapCollageBody(sample: s),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_continue',
    label: '接着看',
    glyph: AppGlyphs.playCircle,
    minWidth: 132,
    minHeight: 92,
    accepts: (s) => continueGapEntry(s.entries) != null,
    builder: (context, s) {
      final entry = continueGapEntry(s.entries);
      return GapExpressiveShell(
        glyph: AppGlyphs.playCircle,
        title: '接着看',
        seed: s.seed,
        tone: GapTone.primary,
        badgeText: '继续',
        body: entry == null
            ? const SizedBox.shrink()
            : GapContinueBody(entry: entry, seed: s.seed),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_streak_days',
    label: '连续天数',
    glyph: AppGlyphs.fire,
    minWidth: 96,
    minHeight: 56,
    accepts: (s) => streakGapDays(s.entries) >= 2,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.fire,
      title: '连续',
      seed: s.seed,
      tone: GapTone.tertiary,
      badgeText: '活跃',
      body: GapStreakBody(
        days: streakGapDays(s.entries),
        weekFlags: recentGapDayFlags(s.entries, 7),
      ),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_week_bars',
    label: '近 7 日',
    glyph: AppGlyphs.calendar,
    minWidth: 108,
    minHeight: 76,
    accepts: (s) => s.entries.where((e) => e.timestamp != null).length >= 3,
    builder: (context, s) {
      final (bars, total) = weeklyGapBuckets(s.entries);
      return GapExpressiveShell(
        glyph: AppGlyphs.calendar,
        title: '近 7 日',
        seed: s.seed,
        tone: GapTone.secondary,
        body: GapBarsBody(counts: bars, caption: '$total 条'),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_day_parts',
    label: '阅读时段',
    glyph: AppGlyphs.moon,
    minWidth: 108,
    minHeight: 64,
    accepts: (s) => s.entries.where((e) => e.timestamp != null).length >= 3,
    builder: (context, s) {
      final (counts, caption) = dayPartsGapBuckets(s.entries);
      return GapExpressiveShell(
        glyph: AppGlyphs.moon,
        title: '时段',
        seed: s.seed,
        tone: GapTone.surfaceHigh,
        body: GapDayPartsBody(counts: counts, caption: caption),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_random_pick',
    label: '随机漫游',
    glyph: AppGlyphs.dice,
    minWidth: 116,
    minHeight: 80,
    accepts: (s) => s.entries.where((e) => e.media != null).length >= 2,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.dice,
      title: '随机漫游',
      seed: s.seed,
      tone: GapTone.secondary,
      badgeText: '偶遇',
      body: GapRandomPickBody(entry: randomGapEntry(s), seed: s.seed),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_reading_queue',
    label: '待看叠卡',
    glyph: AppGlyphs.bookmark,
    minWidth: 124,
    minHeight: 82,
    accepts: (s) => readingQueueGapEntries(s.entries).length >= 2,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.bookmark,
      title: '待看叠卡',
      seed: s.seed,
      tone: GapTone.tertiary,
      body: GapReadingQueueBody(queue: readingQueueGapEntries(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_top_tags',
    label: '高频标签',
    glyph: AppGlyphs.sell,
    minWidth: 112,
    minHeight: 76,
    accepts: (s) => topGapTags(s.entries).isNotEmpty,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.sell,
      title: '常见标签',
      seed: s.seed,
      tone: GapTone.secondary,
      body: GapTagsBody(tags: topGapTags(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_creators',
    label: '常看创作者',
    glyph: AppGlyphs.palette,
    minWidth: 112,
    minHeight: 74,
    accepts: (s) => topGapCreators(s.entries).isNotEmpty,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.palette,
      title: '创作者',
      seed: s.seed,
      tone: GapTone.surfaceHigh,
      body: GapCreatorsBody(creators: topGapCreators(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_progress',
    label: '在读进度',
    glyph: AppGlyphs.trend,
    minWidth: 96,
    minHeight: 72,
    accepts: (s) =>
        s.entries.any((e) => (e.progress ?? 0) > 0) ||
        s.entries.any((e) => e.reading == true),
    builder: (context, s) {
      final read = s.entries.where((e) => (e.progress ?? 0) > 0).toList();
      final avg = read.isEmpty
          ? 0.0
          : read
                    .map((e) => e.progress!.clamp(0.0, 1.0))
                    .reduce((a, b) => a + b) /
                read.length;
      final active = s.entries.where((e) => e.reading == true).length;
      return GapExpressiveShell(
        glyph: AppGlyphs.openBook,
        title: '在读',
        seed: s.seed,
        tone: GapTone.primary,
        body: GapProgressBody(
          progress: avg,
          active: active,
          counted: read.length,
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_rediscover',
    label: '尘封重温',
    glyph: AppGlyphs.hourglass,
    minWidth: 118,
    minHeight: 76,
    accepts: (s) => oldestGapEntry(s.entries) != null,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.hourglass,
      title: '尘封重温',
      seed: s.seed,
      tone: GapTone.tertiary,
      body: GapRediscoverBody(entry: oldestGapEntry(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_peak_day',
    label: '活跃峰值',
    glyph: AppGlyphs.trophy,
    minWidth: 100,
    minHeight: 64,
    accepts: (s) => peakGapDay(s.entries) != null,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.trophy,
      title: '峰值日',
      seed: s.seed,
      tone: GapTone.secondary,
      body: GapPeakDayBody(peak: peakGapDay(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_page_scale',
    label: '篇幅分布',
    glyph: AppGlyphs.openBook,
    minWidth: 104,
    minHeight: 64,
    accepts: (s) => pageScaleGapCounts(s.entries).length >= 2,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.openBook,
      title: '篇幅',
      seed: s.seed,
      tone: GapTone.primary,
      body: GapPageScaleBody(pages: pageScaleGapCounts(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_aspect_mix',
    label: '画幅构成',
    glyph: AppGlyphs.dashboard,
    minWidth: 108,
    minHeight: 68,
    accepts: (s) =>
        s.entries
            .where((e) => e.media != null && e.mediaAspectRatio != null)
            .length >=
        2,
    builder: (context, s) {
      final (portrait, square, landscape) = aspectMixGapCounts(s.entries);
      return GapExpressiveShell(
        glyph: AppGlyphs.dashboard,
        title: '画幅',
        seed: s.seed,
        tone: GapTone.surfaceHigh,
        body: GapAspectMixBody(
          portrait: portrait,
          square: square,
          landscape: landscape,
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_media_format',
    label: '载体分布',
    glyph: AppGlyphs.category,
    minWidth: 108,
    minHeight: 68,
    accepts: (s) => mediaFormatGapCounts(s.entries).length >= 2,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.category,
      title: '载体',
      seed: s.seed,
      tone: GapTone.secondary,
      body: GapMediaFormatBody(formats: mediaFormatGapCounts(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_source_mix',
    label: '来源构成',
    glyph: AppGlyphs.pieChart,
    minWidth: 112,
    minHeight: 68,
    accepts: (s) => sourceGapCounts(s.entries).length > 1,
    builder: (context, s) => GapExpressiveShell(
      glyph: AppGlyphs.pieChart,
      title: '来源',
      seed: s.seed,
      tone: GapTone.surfaceHigh,
      body: GapSourceBody(sources: sourceGapCounts(s.entries)),
    ),
  ),
  LibraryGapWidgetSpec(
    id: 'gap_recent_new',
    label: '近 3 天',
    glyph: AppGlyphs.sparkle,
    minWidth: 92,
    minHeight: 60,
    accepts: (s) => s.entries.any((e) => e.timestamp != null),
    builder: (context, s) {
      final (d0, d1, d2, total) = recentThreeDayGapCounts(s.entries);
      return GapExpressiveShell(
        glyph: AppGlyphs.sparkle,
        title: '近 3 天',
        seed: s.seed,
        tone: GapTone.primary,
        body: GapExpressiveMetricBody(
          value: '$total',
          unit: '条有更新',
          pillText: d0 > 0 ? '今日 +$d0' : (d1 > 0 ? '昨日 +$d1' : '前日 +$d2'),
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_volume',
    label: '占用体积',
    glyph: AppGlyphs.storage,
    minWidth: 96,
    minHeight: 56,
    accepts: (s) => s.entries.any((e) => (e.byteSize ?? 0) > 0),
    builder: (context, s) {
      final bytes = s.entries.fold<double>(0, (a, e) => a + (e.byteSize ?? 0));
      final avg = s.entries.isEmpty ? 0.0 : bytes / s.entries.length;
      return GapExpressiveShell(
        glyph: AppGlyphs.storage,
        title: '体积',
        seed: s.seed,
        tone: GapTone.secondary,
        body: GapExpressiveMetricBody(
          value: formatGapBytes(bytes),
          unit: '${s.entries.length} 项合计',
          pillText: avg > 0 ? '均 ${formatGapBytes(avg)}' : null,
        ),
      );
    },
  ),
  LibraryGapWidgetSpec(
    id: 'gap_count',
    label: '条目数',
    glyph: AppGlyphs.layers,
    minWidth: 80,
    minHeight: 52,
    builder: (context, s) {
      final pages = s.entries.fold<int>(0, (a, e) => a + (e.itemCount ?? 0));
      return GapExpressiveShell(
        glyph: AppGlyphs.layers,
        title: '这一墙',
        seed: s.seed,
        tone: GapTone.surfaceHigh,
        body: GapExpressiveMetricBody(
          value: '${s.entries.length}',
          unit: pages > 0 ? '共 $pages 话' : '条内容',
          pillText: pages > 0 ? '$pages 话' : '馆藏',
        ),
      );
    },
  ),
];

/// `1.2 MB`。这里自己写一份而不复用 `info_card_kit` 的同名函数：那份在
/// `expressive_widgets.dart` 的 import 链上挂着 `global_setting`，而空隙填充物
/// 的整个依赖面就该是「条目 + 主题」，不该把应用级配置拖进来。
String formatGapBytes(double bytes) {
  if (bytes <= 0) return '—';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes;
  var index = 0;
  while (value >= 1024 && index < suffixes.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
}

/// 槽位 → 画什么。组件 id 找不到时（宿主换了套件）退回随机图形，
/// 而不是留一块空白。
class LibraryGapFiller extends StatelessWidget {
  const LibraryGapFiller({
    super.key,
    required this.choice,
    required this.sample,
    required this.widgets,
  });

  final LibraryGapChoice choice;
  final LibraryGapSample sample;
  final List<LibraryGapWidgetSpec> widgets;

  @override
  Widget build(BuildContext context) {
    if (choice.isShape) return LibraryGapShape(seed: choice.seed);
    final spec = widgets.where((w) => w.id == choice.widgetId).firstOrNull;
    if (spec == null) return LibraryGapShape(seed: choice.seed);
    return IgnorePointer(
      child: Semantics(label: spec.label, child: spec.builder(context, sample)),
    );
  }
}

/// 空隙小组件的 MD3 Expressive 容器色阶。
enum GapTone { primary, secondary, tertiary, surfaceHigh }

({
  Color container,
  Color onContainer,
  Color accent,
  Color onAccent,
  Color patchA,
  Color patchB,
})
_resolveGapTone(ColorScheme scheme, GapTone tone) {
  return switch (tone) {
    GapTone.primary => (
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      patchA: scheme.tertiaryContainer,
      patchB: scheme.secondaryContainer,
    ),
    GapTone.secondary => (
      container: scheme.secondaryContainer,
      onContainer: scheme.onSecondaryContainer,
      accent: scheme.secondary,
      onAccent: scheme.onSecondary,
      patchA: scheme.primaryContainer,
      patchB: scheme.tertiaryContainer,
    ),
    GapTone.tertiary => (
      container: scheme.tertiaryContainer,
      onContainer: scheme.onTertiaryContainer,
      accent: scheme.tertiary,
      onAccent: scheme.onTertiary,
      patchA: scheme.primaryContainer,
      patchB: scheme.secondaryContainer,
    ),
    GapTone.surfaceHigh => (
      container: scheme.surfaceContainerHigh,
      onContainer: scheme.onSurface,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      patchA: scheme.primaryContainer,
      patchB: scheme.tertiaryContainer,
    ),
  };
}

/// 按种子生成「三圆一尖」的 MD3 Expressive 非对称张力圆角。
BorderRadius _expressiveGapRadius(int seed, {required bool tight}) {
  final lg = Radius.circular(tight ? 15 : 22);
  final sharp = Radius.circular(tight ? 5 : 8);
  return switch (seed.abs() % 4) {
    0 => BorderRadius.only(
      topLeft: lg,
      topRight: lg,
      bottomLeft: sharp,
      bottomRight: lg,
    ),
    1 => BorderRadius.only(
      topLeft: lg,
      topRight: sharp,
      bottomLeft: lg,
      bottomRight: lg,
    ),
    2 => BorderRadius.only(
      topLeft: lg,
      topRight: lg,
      bottomLeft: lg,
      bottomRight: sharp,
    ),
    _ => BorderRadius.only(
      topLeft: sharp,
      topRight: lg,
      bottomLeft: lg,
      bottomRight: lg,
    ),
  };
}

/// 适合做空隙图标座与背景几何贴片的 M3E 多边形池。
const List<ExpressiveButtonShape> _kGapExpressiveShapes = [
  ExpressiveButtonShape.sunny,
  ExpressiveButtonShape.clover4Leaf,
  ExpressiveButtonShape.softBurst,
  ExpressiveButtonShape.puffyDiamond,
  ExpressiveButtonShape.cookie4Sided,
  ExpressiveButtonShape.cookie6Sided,
  ExpressiveButtonShape.cookie7Sided,
  ExpressiveButtonShape.cookie9Sided,
  ExpressiveButtonShape.flower,
  ExpressiveButtonShape.gem,
  ExpressiveButtonShape.pentagon,
  ExpressiveButtonShape.clamShell,
  ExpressiveButtonShape.puffy,
  ExpressiveButtonShape.arch,
  ExpressiveButtonShape.clover8Leaf,
  ExpressiveButtonShape.verySunny,
];

/// 多态几何图标座：将 `GlyphIcon` 包在 `material_new_shapes` 的有机多边形容器内。
class GapShapeBadge extends StatelessWidget {
  const GapShapeBadge({
    super.key,
    required this.glyph,
    required this.seed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.size = 22,
    this.shape,
  });

  final Glyph glyph;
  final int seed;
  final Color backgroundColor;
  final Color foregroundColor;
  final double size;
  final ExpressiveButtonShape? shape;

  @override
  Widget build(BuildContext context) {
    final picked =
        shape ??
        _kGapExpressiveShapes[seed.abs() % _kGapExpressiveShapes.length];
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: ExpressiveMorphBorder(from: picked, to: picked),
        ),
        child: Center(
          child: GlyphIcon(
            glyph,
            size: (size * 0.56).clamp(10.0, 22.0),
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}

/// MD3 Expressive 胶囊角标 (`StadiumBorder`)。
class GapPillBadge extends StatelessWidget {
  const GapPillBadge({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: foregroundColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 小组件 MD3 Expressive 外壳：
/// - 色阶容器背景 + 非对称张力圆角
/// - 边角撞色多边形与 Blob 几何贴片底纹
/// - 有机多边形图标座 + 标题行（在极限矮槽位或 2x 大字号下自动收起，防止溢出）
class GapExpressiveShell extends StatelessWidget {
  const GapExpressiveShell({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
    required this.seed,
    this.tone = GapTone.surfaceHigh,
    this.badgeText,
  });

  final Glyph glyph;
  final String title;
  final Widget body;
  final int seed;
  final GapTone tone;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final palette = _resolveGapTone(scheme, tone);
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final tight = h < 84 || w < 96 || textScale > 1.45;
        final radius = _expressiveGapRadius(seed, tight: tight);
        final showBadgePill =
            !tight && badgeText != null && w >= 146 && textScale <= 1.25;

        return ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.container,
              borderRadius: radius,
              border: Border.all(
                color: palette.accent.withValues(alpha: isDark ? 0.22 : 0.16),
                width: 0.8,
              ),
            ),
            child: CustomPaint(
              painter: _GapCollageBackdropPainter(
                seed: seed,
                patchA: palette.patchA,
                patchB: palette.patchB,
                strokeColor: palette.accent,
                isDark: isDark,
              ),
              child: Padding(
                padding: EdgeInsets.all(tight ? 8 : 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!tight) ...[
                      Row(
                        children: [
                          GapShapeBadge(
                            glyph: glyph,
                            seed: seed,
                            size: 20,
                            backgroundColor: palette.accent.withValues(
                              alpha: isDark ? 0.24 : 0.18,
                            ),
                            foregroundColor: palette.onContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                color: palette.onContainer.withValues(
                                  alpha: .88,
                                ),
                              ),
                            ),
                          ),
                          if (showBadgePill) ...[
                            const SizedBox(width: 4),
                            GapPillBadge(
                              text: badgeText!,
                              backgroundColor: palette.accent.withValues(
                                alpha: isDark ? 0.22 : 0.16,
                              ),
                              foregroundColor: palette.onContainer,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GapCollageBackdropPainter extends CustomPainter {
  const _GapCollageBackdropPainter({
    required this.seed,
    required this.patchA,
    required this.patchB,
    required this.strokeColor,
    required this.isDark,
  });

  final int seed;
  final Color patchA;
  final Color patchB;
  final Color strokeColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = seed.abs();
    final shapeA = _kGapExpressiveShapes[s % _kGapExpressiveShapes.length];
    final shapeB =
        _kGapExpressiveShapes[(s >> 4) % _kGapExpressiveShapes.length];

    final alphaA = isDark ? 0.34 : 0.52;
    final alphaB = isDark ? 0.26 : 0.42;
    final strokeAlpha = isDark ? 0.28 : 0.36;

    // 1. 右上/右下主几何贴片
    final diameterA = (size.shortestSide * 0.72).clamp(36.0, 128.0);
    final topAnchor = (s & 1) == 0;
    final centerA = Offset(
      size.width - diameterA * 0.18,
      topAnchor ? diameterA * 0.16 : size.height - diameterA * 0.16,
    );
    _drawPolygon(
      canvas,
      polygon: shapeA.polygon,
      center: centerA,
      diameter: diameterA,
      angle: ((s % 11) - 5) * 0.12,
      paint: Paint()
        ..style = PaintingStyle.fill
        ..color = patchA.withValues(alpha: alphaA),
    );

    // 2. 次级叠印多边形贴片
    if (size.longestSide >= 96) {
      final diameterB = (size.shortestSide * 0.46).clamp(24.0, 82.0);
      final centerB = Offset(
        size.width - diameterA * 0.64,
        topAnchor ? size.height - diameterB * 0.12 : diameterB * 0.2,
      );
      _drawPolygon(
        canvas,
        polygon: shapeB.polygon,
        center: centerB,
        diameter: diameterB,
        angle: -((s >> 3) % 9) * 0.14,
        paint: Paint()
          ..style = PaintingStyle.fill
          ..color = patchB.withValues(alpha: alphaB),
      );
    }

    // 3. 种子驱动的不规则 Blob 描边轮廓
    final blobSide = (size.shortestSide * 0.44).clamp(22.0, 74.0);
    final blobRect = Rect.fromCenter(
      center: Offset(
        size.width - diameterA * 0.32,
        size.height * (topAnchor ? 0.68 : 0.32),
      ),
      width: blobSide * 1.2,
      height: blobSide,
    );
    canvas.drawPath(
      ExpressiveBlob.ofSeed(
        s ^ 0x5bd1e995,
      ).path(rect: blobRect, progress: 0, safeInset: 5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = strokeColor.withValues(alpha: strokeAlpha),
    );
  }

  void _drawPolygon(
    Canvas canvas, {
    required RoundedPolygon polygon,
    required Offset center,
    required double diameter,
    required double angle,
    required Paint paint,
  }) {
    var path = polygon.toPath();
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(diameter, diameter, 1, 1)
      ..translateByDouble(-.5, -.5, 0, 1);
    path = path.transform(matrix.storage);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GapCollageBackdropPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.patchA != patchA ||
      oldDelegate.patchB != patchB ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.isDark != isDark;
}

/// 响应式大数字指标体：
/// - 在大槽位中自动放大 Display 字号并展示底部胶囊副标，填满竖向与横向空间；
/// - 在紧凑槽位或 2x 字号下自动通过 [FittedBox] 缩放，零溢出。
class GapExpressiveMetricBody extends StatelessWidget {
  const GapExpressiveMetricBody({
    super.key,
    required this.value,
    required this.unit,
    this.pillText,
  });

  final String value;
  final String unit;
  final String? pillText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isRoomy = h >= 72 && w >= 104 && textScale <= 1.35;
        final showBottomPill =
            pillText != null && h >= 82 && w >= 96 && textScale <= 1.3;
        final numberSize = isRoomy
            ? (math.min(w, h) * 0.42).clamp(26.0, 52.0)
            : 24.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: numberSize,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unit,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: isRoomy ? 12 : 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showBottomPill) ...[
              const SizedBox(height: 4),
              GapPillBadge(
                text: pillText!,
                backgroundColor: scheme.primary.withValues(alpha: .16),
                foregroundColor: scheme.onSurface,
              ),
            ],
          ],
        );
      },
    );
  }
}
