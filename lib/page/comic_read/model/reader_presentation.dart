/// 阅读器呈现层（缩放 / 旋转 / 宽页策略）的值模型与尺寸数学。
///
/// 逐条对齐 neoview 的 `packages/nodes/neoview/src/domain/presentation/presentation.ts`：
/// 那边是顶栏与渲染层之间唯一的口径来源，这里也只做这一件事 —— 不碰状态、不碰 Widget。
///
/// **刻意不含 `orientation`**：neoview 的 `orientation` 是「一帧往哪个轴排页」，
/// 本项目的对应物是 `readSetting.readMode`（条漫 / 横翻），已经有一份权威了。
/// 再抄一遍就会有两个真相。
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 缩放模式。
///
/// [fit] 是 neoview 的默认档；[fitLeft] / [fitRight] 与 [fit] **缩放比例完全相同**，
/// 差别只在容器内的对齐（neoview 里靠 `justifyContent` 实现，这里靠 [alignment]）。
enum ReaderFitMode {
  /// 适应窗口：整页缩到视口内，两边可能留白。
  fit,

  /// 铺满整个窗口：取较大的那个比例，短边溢出。
  fill,

  /// 适应宽度。
  fitWidth,

  /// 适应高度。
  fitHeight,

  /// 原始大小：图片像素 1:1 当逻辑点用。
  original,

  /// 适应窗口并靠左。
  fitLeft,

  /// 适应窗口并靠右。
  fitRight;

  bool get isFit => this == fit || this == fitLeft || this == fitRight;

  Alignment get alignment => switch (this) {
    fitLeft => Alignment.centerLeft,
    fitRight => Alignment.centerRight,
    _ => Alignment.center,
  };
}

/// 自动旋转 —— 按**页面自身**的横竖决定要不要转 90°。
enum ReaderAutoRotation {
  /// 不自动旋转。
  none,

  /// 纵向页左旋。
  left,

  /// 纵向页右旋。
  right,

  /// 横向页左旋。
  horizontalLeft,

  /// 横向页右旋。
  horizontalRight,

  /// 一律左旋。
  forcedLeft,

  /// 一律右旋。
  forcedRight;

  /// 顶栏「自动旋转」那一组里的三档（纵向页）。
  static const portraitGroup = [none, left, right];
}

/// 宽页策略 —— 一帧里有多页时，各自按比例缩放会错位。
enum ReaderWidePageStretch {
  /// 无对齐：保持各页原始比例。
  none,

  /// 高度对齐：每页缩放到该帧最高那一页的高度。
  uniformHeight,

  /// 宽度对齐：每页缩放到该帧的平均宽度。
  uniformWidth,
}

/// 一帧的排布轴。
///
/// [strip] 是本项目独有的**条漫**：neoview 没有连续长条模式，它的 `orientation`
/// 是「一帧内多页往哪排」，跟长条滚动不是一回事。条漫的固定轴是宽度（长条必须
/// 横贯画面），所以除了 [fitHeight] 与 [original]，其余模式都退回按宽算 ——
/// 否则默认档 [ReaderFitMode.fit] 会把一张 8000px 高的长条缩进一屏，
/// 那是「升级即把条漫看坏了」的改动。
enum ReaderFrameAxis {
  /// 横翻：一帧 1~2 页，视口是两个轴都有限的窗口。
  page,

  /// 条漫：竖向连续长条，只有宽度是固定的。
  strip,
}

/// 顶栏与渲染层之间传递的那一份呈现状态。
@immutable
class ReaderPresentation {
  final ReaderFitMode fitMode;

  /// 手动缩放，**是 fit 之上的乘数而不是绝对倍率**：`1.0` 意味着「纯按 fitMode 铺」。
  ///
  /// 顶栏允许 10%~1000%，渲染侧一律先过 [normalizeReaderManualScale] 收到 0.1~8，
  /// 所以选到 1000% 实际按 800% 铺 —— 这一条 neoview 也是一样的（两处 clamp 不重合）。
  final double manualScale;

  /// 手动旋转，只取 0 / 90 / 180 / 270。
  final int rotation;

  final ReaderAutoRotation autoRotation;

  final ReaderWidePageStretch widePageStretch;

  const ReaderPresentation({
    this.fitMode = ReaderFitMode.fit,
    this.manualScale = 1,
    this.rotation = 0,
    this.autoRotation = ReaderAutoRotation.none,
    this.widePageStretch = ReaderWidePageStretch.none,
  });

  /// 「重置视图」的目标档。
  ///
  /// 与 neoview 的 `DEFAULT_READER_PRESENTATION` 只差一处：那边 `widePageStretch`
  /// 默认 `uniform-height`，这边默认 `none`（= 本仓改造前的双页观感）。
  static const ReaderPresentation defaultPresentation = ReaderPresentation();

  bool get isDefault =>
      fitMode == ReaderFitMode.fit &&
      normalizeReaderManualScale(manualScale) == 1 &&
      rotation == 0 &&
      autoRotation == ReaderAutoRotation.none &&
      widePageStretch == ReaderWidePageStretch.none;

  /// 缩放倍率步进（顶栏按钮与 `reader.zoom-in` / `reader.zoom-out` 动作共用）。
  double scaledByStep(int direction) =>
      stepReaderManualScale(manualScale, direction);

  /// 顺时针转 `quarterTurns` 个直角。
  ReaderPresentation rotated(int quarterTurns) =>
      copyWith(rotation: normalizeReaderRotation(rotation + quarterTurns * 90));

  ReaderPresentation copyWith({
    ReaderFitMode? fitMode,
    double? manualScale,
    int? rotation,
    ReaderAutoRotation? autoRotation,
    ReaderWidePageStretch? widePageStretch,
  }) {
    return ReaderPresentation(
      fitMode: fitMode ?? this.fitMode,
      manualScale: manualScale ?? this.manualScale,
      rotation: rotation ?? this.rotation,
      autoRotation: autoRotation ?? this.autoRotation,
      widePageStretch: widePageStretch ?? this.widePageStretch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPresentation &&
      other.fitMode == fitMode &&
      other.manualScale == manualScale &&
      other.rotation == rotation &&
      other.autoRotation == autoRotation &&
      other.widePageStretch == widePageStretch;

  @override
  int get hashCode => Object.hash(
    fitMode,
    manualScale,
    rotation,
    autoRotation,
    widePageStretch,
  );

  @override
  String toString() =>
      'ReaderPresentation($fitMode, ${manualScale}x, $rotation°, '
      '$autoRotation, $widePageStretch)';
}

/// 把任意角度收到 0 / 90 / 180 / 270。
int normalizeReaderRotation(int rotation) =>
    (((rotation / 90).round() * 90) % 360 + 360) % 360;

/// 手动缩放的渲染侧上限：`0.1 ~ 8`，两位小数。
double normalizeReaderManualScale(double scale) {
  if (!scale.isFinite) return 1;
  return math.min(8, math.max(0.1, (scale * 100).roundToDouble() / 100));
}

/// 一次缩放步进：×1.1 或 ÷1.1（与 neoview 同一系数）。
double stepReaderManualScale(double scale, int direction) =>
    normalizeReaderManualScale(scale * (direction > 0 ? 1.1 : 1 / 1.1));

/// 一帧内容铺到视口上该用多大的比例。
///
/// [content] 必须是**已经旋转过、并且乘过宽页策略**的尺寸（见 [readerFrameSize]），
/// 否则 fit 计算会把 90° 旋转的页按未旋转的宽高比算，于是横页会溢出到屏幕外。
double calculateReaderScale({
  required ReaderFitMode fitMode,
  required Size content,
  required Size viewport,
  double manualScale = 1,
  ReaderFrameAxis axis = ReaderFrameAxis.page,
}) {
  final normalized = normalizeReaderManualScale(manualScale);
  if (!_validSize(content) || !_validSize(viewport)) return normalized;

  final widthScale = viewport.width / content.width;
  final heightScale = viewport.height / content.height;
  final modeScale = switch (fitMode) {
    ReaderFitMode.fill =>
      axis == ReaderFrameAxis.strip
          ? widthScale
          : math.max(widthScale, heightScale),
    ReaderFitMode.fitWidth => widthScale,
    ReaderFitMode.fitHeight => heightScale,
    ReaderFitMode.original => 1.0,
    // 条漫的固定轴是宽度：`fit` 在这里就是「铺满宽」，不是「塞进一屏」。
    ReaderFitMode.fit || ReaderFitMode.fitLeft || ReaderFitMode.fitRight =>
      axis == ReaderFrameAxis.strip
          ? widthScale
          : math.min(widthScale, heightScale),
  };
  return modeScale * normalized;
}

/// 逐页的宽页策略倍率。不足两页或策略为 [ReaderWidePageStretch.none] 时全是 1。
List<double> calculateReaderPageStretchScales(
  List<Size> pages,
  ReaderWidePageStretch mode,
) {
  if (pages.length < 2 || mode == ReaderWidePageStretch.none) {
    return List.filled(pages.length, 1);
  }
  if (mode == ReaderWidePageStretch.uniformHeight) {
    var maxHeight = 0.0;
    for (final page in pages) {
      maxHeight = math.max(maxHeight, page.height);
    }
    return maxHeight > 0
        ? pages.map((page) => maxHeight / page.height).toList()
        : List.filled(pages.length, 1);
  }
  var totalWidth = 0.0;
  for (final page in pages) {
    totalWidth += page.width;
  }
  final averageWidth = totalWidth / pages.length;
  return averageWidth > 0
      ? pages.map((page) => averageWidth / page.width).toList()
      : List.filled(pages.length, 1);
}

/// 这一页在该转多少度 —— 手动旋转叠加自动旋转。
///
/// [autoRotation] 的 `left` / `right` 只管纵向页，`horizontal-*` 只管横向页，
/// `forced-*` 无条件管；「纵向」按**旋转前**的尺寸判。
int effectiveReaderRotation(
  int manualRotation,
  ReaderAutoRotation autoRotation,
  Size page,
) {
  final portrait = page.height > page.width;
  final delta =
      autoRotation == ReaderAutoRotation.forcedLeft ||
          (autoRotation == ReaderAutoRotation.left && portrait) ||
          (autoRotation == ReaderAutoRotation.horizontalLeft && !portrait)
      ? -90
      : autoRotation == ReaderAutoRotation.forcedRight ||
            (autoRotation == ReaderAutoRotation.right && portrait) ||
            (autoRotation == ReaderAutoRotation.horizontalRight && !portrait)
      ? 90
      : 0;
  return normalizeReaderRotation(manualRotation + delta);
}

/// 旋转后的布局尺寸：直角旋转会交换宽高。
Size rotatePresentationSize(Size size, int rotation) =>
    (rotation == 90 || rotation == 270) ? Size(size.height, size.width) : size;

/// 一帧的总尺寸：沿排布轴累加，交叉轴取最大。
///
/// 返回 null 表示这一帧还没有任何有效尺寸（图片还没解出来），调用方应当按
/// 「还不知道该铺多大」处理，而不是拿 0 去除。
Size? readerFrameSize({
  required List<Size> pages,
  required int rotation,
  required ReaderAutoRotation autoRotation,
  required ReaderWidePageStretch widePageStretch,
  ReaderFrameAxis axis = ReaderFrameAxis.page,
}) {
  final valid = pages.where(_validSize).toList();
  if (valid.isEmpty) return null;
  final rotated = valid
      .map(
        (page) => rotatePresentationSize(
          page,
          effectiveReaderRotation(rotation, autoRotation, page),
        ),
      )
      .toList();
  final stretches = calculateReaderPageStretchScales(rotated, widePageStretch);
  var width = 0.0;
  var height = 0.0;
  for (var i = 0; i < rotated.length; i++) {
    final page = rotated[i];
    final stretch = stretches[i];
    final scaled = Size(page.width * stretch, page.height * stretch);
    if (axis == ReaderFrameAxis.strip) {
      width = math.max(width, scaled.width);
      height += scaled.height;
    } else {
      width += scaled.width;
      height = math.max(height, scaled.height);
    }
  }
  return Size(width, height);
}

bool _validSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;
