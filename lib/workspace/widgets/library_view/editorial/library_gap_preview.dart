import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 设置页里的**示例条目**：只为本机预览服务，不查库、不依赖宿主数据。
///
/// 数据面刻意铺满所有小组件会读的字段：时间（今天 / 昨天 / 上周 / 去年）、
/// 阅读进度（读完 / 在读 / 未开始）、页数、体积、标签、来源、标题里的
/// `[社团 (作者)]`。组件因此能在设置里按「真实数据长什么样」预览，
/// 而不是拿一排空卡片糊弄。
///
/// 结果稳定（除「今天」以 [now] 为锚点外没有随机），同一个设置面板每次
/// 打开看到的是同一批示例，方便对照开关前后的差别。
List<LibraryEntry> libraryGapPreviewEntries({DateTime? now}) {
  final anchor = now ?? DateTime.now();
  final dates = <DateTime>[
    anchor,
    anchor.subtract(const Duration(hours: 3)),
    anchor.subtract(const Duration(days: 1)),
    anchor.subtract(const Duration(days: 2)),
    anchor.subtract(const Duration(days: 4)),
    anchor.subtract(const Duration(days: 7)),
    anchor.subtract(const Duration(days: 9)),
    anchor.subtract(const Duration(days: 13)),
    anchor.subtract(const Duration(days: 21)),
    anchor.subtract(const Duration(days: 34)),
    anchor.subtract(const Duration(days: 55)),
    anchor.subtract(const Duration(days: 88)),
    anchor.subtract(const Duration(days: 120)),
    anchor.subtract(const Duration(days: 160)),
    anchor.subtract(const Duration(days: 210)),
    anchor.subtract(const Duration(days: 280)),
    anchor.subtract(const Duration(days: 360)),
    anchor.subtract(const Duration(days: 420)),
  ];
  const authors = ['社团甲 (作者一)', '社团乙 (作者二)', '社团丙 (作者三)'];
  const sources = ['本地', '插件甲', '插件乙'];
  const tags = ['短篇', '连载', '同人', '全彩', '汉化', '合集'];
  return [
    for (var i = 0; i < dates.length; i++)
      LibraryEntry(
        key: 'preview-$i',
        title: '[${authors[i % authors.length]}] 示例作品 ${i + 1}',
        subtitle: 'P.${12 + i * 3}',
        description: '一条只用于设置预览的示例条目。',
        section: sources[i % sources.length],
        timestamp: dates[i],
        // 前几本有明确的阅读状态，后面留未开始 —— 完成率与待读存量
        // 都要有「有数据」和「没数据」两种条目可读。
        progress: i % 4 == 0 ? 1 : (i % 3 == 0 ? .25 + (i % 5) * .12 : null),
        reading: i == 1,
        tags: [tags[i % tags.length], tags[(i + 2) % tags.length]],
        itemCount: 6 + i * 4,
        byteSize: (12 + i * 7) * 1024 * 1024,
        mediaAspectRatio: i % 5 == 0 ? 1.55 : .7,
        media:
            (
              context, {
              required double width,
              required double height,
              required BorderRadius radius,
              required BoxFit fit,
            }) => _PreviewCover(seed: i, width: width, height: height),
      ),
  ];
}

/// 预览封面：种子决定的双色渐变 + 一条斜向色块，避免 18 张全一样的方块。
class _PreviewCover extends StatelessWidget {
  const _PreviewCover({
    required this.seed,
    required this.width,
    required this.height,
  });

  final int seed;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      (scheme.primaryContainer, scheme.tertiaryContainer),
      (scheme.secondaryContainer, scheme.primaryContainer),
      (scheme.tertiaryContainer, scheme.secondaryContainer),
      (scheme.surfaceContainerHighest, scheme.primaryContainer),
    ];
    final (from, to) = palette[seed % palette.length];
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [from, to],
          ),
        ),
        child: Align(
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: math.pi / 7,
            child: FractionallySizedBox(
              widthFactor: .7,
              heightFactor: .12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: .5),
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 给一款小组件造一份预览用的空隙样本。
///
/// 尺寸就是预览卡里那块预留区域：组件按真实槽位的口径自适应，
/// 于是设置里看到的就是它装进墙里时的样子，而不是另一个「展示版」。
LibraryGapSample libraryGapPreviewSample(
  LibraryGapWidgetSpec spec, {
  required Size size,
  List<LibraryEntry>? entries,
  int seed = 7,
}) => LibraryGapSample(
  entries: entries ?? libraryGapPreviewEntries(),
  slot: LibraryGapSlot(
    row: 0,
    tile: 0,
    columnStart: 0,
    span: 1,
    width: size.width,
    height: size.height,
  ),
  seed: seed,
);

/// 小组件预览：把真实的 builder 塞进一块给定大小的空隙里。
class LibraryGapWidgetPreview extends StatelessWidget {
  const LibraryGapWidgetPreview({
    super.key,
    required this.spec,
    this.entries,
    this.seed = 7,
  });

  final LibraryGapWidgetSpec spec;
  final List<LibraryEntry>? entries;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 180,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 112,
        );
        final sample = libraryGapPreviewSample(
          spec,
          size: size,
          entries: entries,
          seed: seed,
        );
        return spec.builder(context, sample);
      },
    );
  }
}

/// 随机图形预览：一款样式 + 一个固定种子。
class LibraryGapShapePreview extends StatelessWidget {
  const LibraryGapShapePreview({super.key, required this.style, this.seed = 7});

  final LibraryGapShapeStyle style;
  final int seed;

  @override
  Widget build(BuildContext context) =>
      LibraryGapShape(seed: seed, style: style);
}
