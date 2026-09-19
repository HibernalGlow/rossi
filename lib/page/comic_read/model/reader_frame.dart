/// 一帧（横翻的一页或一对页、条漫的一节）的排布计算。
///
/// 把 neoview 分散在 `calculateReaderFrameSize` + `ReaderFrame.tsx` 里的那套
/// 「先按页面自身尺寸算好帧，再整帧铺到视口上」收成一个纯函数，渲染层只消费结果。
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' show Size;
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';

/// 一帧里某一页最终要占的位置与要画的大小。
class ReaderPlacedPage {
  /// 旋转之后在帧里占的矩形 —— 父级（`SizedBox` / `RotatedBox` 外框）用它。
  final Size boxSize;

  /// 图片**自身**（未旋转）该画多大 —— 交给 `Image` 的 width/height。
  ///
  /// 与 [boxSize] 差一次旋转交换：`boxSize` 是「占位」，`paintSize` 是「画布」。
  final Size paintSize;

  /// 这一页实际转了多少度（手动叠加自动，见 [effectiveReaderRotation]）。
  final int rotation;

  const ReaderPlacedPage({
    required this.boxSize,
    required this.paintSize,
    required this.rotation,
  });

  int get quarterTurns => rotation ~/ 90;
}

/// 一帧的排布结果。
class ReaderFrame {
  final List<ReaderPlacedPage> pages;

  /// 整帧缩放后的尺寸（页轴 = 宽相加、高取最大；条漫轴反之）。
  final Size size;

  const ReaderFrame({required this.pages, required this.size});

  /// 算不出来的两种情况：一页有效尺寸都没有，或视口还没定下来。
  ///
  /// 调用方拿到 null 时应当**退回改造前的铺排**（让 `Image` 自己 contain），
  /// 而不是拿 0 去除 —— 后者会让第一帧在图片解出尺寸之前塌成一条线。
  static ReaderFrame? of({
    required List<Size> intrinsicPages,
    required Size viewport,
    required ReaderPresentation presentation,
    ReaderFrameAxis axis = ReaderFrameAxis.page,
  }) {
    final pages = intrinsicPages.where(_valid).toList();
    if (pages.isEmpty || !_valid(viewport)) return null;

    final rotations = pages
        .map(
          (page) => effectiveReaderRotation(
            presentation.rotation,
            presentation.autoRotation,
            page,
          ),
        )
        .toList();
    final rotated = <Size>[
      for (var i = 0; i < pages.length; i++)
        rotatePresentationSize(pages[i], rotations[i]),
    ];
    final stretches = calculateReaderPageStretchScales(
      rotated,
      presentation.widePageStretch,
    );
    final stretched = <Size>[
      for (var i = 0; i < rotated.length; i++)
        rotated[i] * stretches[i],
    ];

    final content = _frameSize(stretched, axis);
    final scale = calculateReaderScale(
      fitMode: presentation.fitMode,
      content: content,
      viewport: viewport,
      manualScale: presentation.manualScale,
      axis: axis,
    );

    final placed = <ReaderPlacedPage>[
      for (var i = 0; i < stretched.length; i++)
        ReaderPlacedPage(
          boxSize: stretched[i] * scale,
          paintSize: rotatePresentationSize(stretched[i] * scale, rotations[i]),
          rotation: rotations[i],
        ),
    ];

    return ReaderFrame(
      pages: placed,
      size: _frameSize(
        placed.map((page) => page.boxSize).toList(),
        axis,
      ),
    );
  }

  static Size _frameSize(List<Size> sizes, ReaderFrameAxis axis) {
    var width = 0.0;
    var height = 0.0;
    for (final size in sizes) {
      if (axis == ReaderFrameAxis.strip) {
        width = math.max(width, size.width);
        height += size.height;
      } else {
        width += size.width;
        height = math.max(height, size.height);
      }
    }
    return Size(width, height);
  }
}

bool _valid(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;
