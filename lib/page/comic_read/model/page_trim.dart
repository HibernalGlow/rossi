import 'dart:ui' show Rect, Size;

/// 非破坏式裁边（自动去余白）的**显示几何与模式策略**。
///
/// 这里没有像素、没有纹理、也不碰桥：只做「内容矩形该怎么摆」的算术，
/// 以及「哪种阅读模式允许裁哪几条边」的判定。检测算法本身是 mImageViewer
/// `src/margin_fit.rs` 的移植，住在 Rust 侧（`rossi_local_core::margin_fit`）。
///
/// 口径与上游一致：**只改变可见区域与缩放，源像素一律不动**。所以开关来回切
/// 不需要重生成大图，也不会污染超分的输入或 OCR 读到的原图。
class PageTrimGeometry {
  /// 围绕盒子原点的缩放倍数（&gt; 1 表示把内容矩形放大）。
  final double scale;

  /// 缩放后再平移的 X（盒子坐标系，逻辑像素）。
  final double dx;

  /// 缩放后再平移的 Y。
  final double dy;

  const PageTrimGeometry(this.scale, this.dx, this.dy);

  @override
  String toString() =>
      'PageTrimGeometry(scale: ${scale.toStringAsFixed(3)}, '
      'dx: ${dx.toStringAsFixed(1)}, dy: ${dy.toStringAsFixed(1)})';
}

/// 缩放倍数小于这个容差就当「没有可裁的」，避免为 0.1% 的差异挂一层变换。
const double _kMinTrimScale = 1.001;

/// 算出把 [contentRect]（归一化 0..1，相对整页）铺满盒子所需的变换。
///
/// [boxSize] 是这一页实际拿到的盒子（逻辑像素），[imageSize] 是整页像素尺寸
/// （**只有纵横比参与计算**，所以超分换尺寸、降采样解码都不影响结果）。
///
/// 返回 `null` 表示**照原样画**，三种情况都会走到这里：
/// - 盒子尺寸不是有限值（列模式在 `paintSize` 到位之前高度未定，没有可裁的盒子）；
/// - 内容矩形退化到接近整页（裁了也没意义）；
/// - 内容矩形越界或方向不对（数据不可信，宁可不裁）。
///
/// 语义与两条渲染路对齐：位图路是 `BoxFit.contain`，纹理路的等比缩放与留边在
/// Rust 着色器里做完，同样是 contain。所以「整页落在盒子里的矩形」这一层算法
/// 对两条路是同一个，切换路径时画面不会跳。
PageTrimGeometry? computePageTrim({
  required Size boxSize,
  required Size imageSize,
  required Rect contentRect,
}) {
  if (!contentRect.left.isFinite ||
      !contentRect.top.isFinite ||
      !contentRect.right.isFinite ||
      !contentRect.bottom.isFinite ||
      contentRect.left < 0 ||
      contentRect.top < 0 ||
      contentRect.right > 1 ||
      contentRect.bottom > 1 ||
      contentRect.isEmpty) {
    return null;
  }
  if (!boxSize.width.isFinite ||
      !boxSize.height.isFinite ||
      !imageSize.width.isFinite ||
      !imageSize.height.isFinite) {
    return null;
  }
  if (boxSize.width <= 0 ||
      boxSize.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return null;
  }

  // 整页按 contain 落在盒子里的那块矩形。
  final double fit =
      boxSize.width / imageSize.width < boxSize.height / imageSize.height
      ? boxSize.width / imageSize.width
      : boxSize.height / imageSize.height;
  final double drawnWidth = imageSize.width * fit;
  final double drawnHeight = imageSize.height * fit;
  final Rect drawn = Rect.fromLTWH(
    (boxSize.width - drawnWidth) / 2,
    (boxSize.height - drawnHeight) / 2,
    drawnWidth,
    drawnHeight,
  );

  // 内容矩形换算到同一坐标系。
  final double left = drawn.left + contentRect.left * drawn.width;
  final double top = drawn.top + contentRect.top * drawn.height;
  final double right = drawn.left + contentRect.right * drawn.width;
  final double bottom = drawn.top + contentRect.bottom * drawn.height;
  final double contentWidth = right - left;
  final double contentHeight = bottom - top;
  if (contentWidth <= 0 || contentHeight <= 0) return null;

  // 内容区等比铺满可用盒子。条漫外层同步增加高度，因此不丢上下接缝。
  final double scale =
      boxSize.width / contentWidth < boxSize.height / contentHeight
      ? boxSize.width / contentWidth
      : boxSize.height / contentHeight;
  if (scale <= _kMinTrimScale) return null;

  // 缩放后内容矩形在可用盒子内居中。
  final double targetWidth = contentWidth * scale;
  final double targetHeight = contentHeight * scale;
  final double targetLeft = boxSize.width / 2 - targetWidth / 2;
  final double targetTop = boxSize.height / 2 - targetHeight / 2;

  return PageTrimGeometry(
    scale,
    targetLeft - left * scale,
    targetTop - top * scale,
  );
}

/// 按阅读模式决定**允许裁哪几条边**，返回可用于显示的内容矩形（`null` = 不裁）。
///
/// 条漫（纵向滚动）里，一张分段图的上下边**可能就是连续画面的接缝**：逐张独立
/// 裁上下，接缝两侧的高度各自变化，拼起来就会跳画面或缺一块（Mihon 的裁边在
/// 长条模式踩过同一个坑）。所以纵向滚动只允许裁左右，上下保持整幅。
///
/// 横向翻页的整页没有这个问题：上下就是这一页自己的边。
Rect? trimRectForScroll({
  required Rect? detected,
  required bool verticalScroll,
}) {
  if (detected == null) return null;
  if (!verticalScroll) return detected;
  final Rect horizontalOnly = Rect.fromLTRB(
    detected.left,
    0.0,
    detected.right,
    1.0,
  );
  if (horizontalOnly.left <= 0.0 && horizontalOnly.right >= 1.0) {
    // 左右也裁不动 = 这一页等于没裁。
    return null;
  }
  return horizontalOnly;
}

/// 双页（跨页并排）时把两页的内容矩形协调成同一上下边界。
///
/// 两页各自检测会得到各自的高度范围；直接各画各的，两页顶边不齐、画面会一高一低。
/// 规则：**上下边界取两页的并集**（宁可多留一点，也不切掉任何一页的内容），
/// 左右边界保留各页自己的外侧边（左页裁左边、右页裁右边，中缝那条边不裁，
/// 因为中缝是装订线，切了会让两页贴到一起）。
({Rect leftPage, Rect rightPage})? coordinateSpreadTrim({
  required Rect? left,
  required Rect? right,
}) {
  if (left == null && right == null) return null;
  final Rect fallback = const Rect.fromLTWH(0, 0, 1, 1);
  final Rect a = left ?? fallback;
  final Rect b = right ?? fallback;
  final double top = a.top < b.top ? a.top : b.top;
  final double bottom = a.bottom > b.bottom ? a.bottom : b.bottom;
  return (
    leftPage: Rect.fromLTRB(a.left, top, 0.5, bottom),
    rightPage: Rect.fromLTRB(0.5, top, b.right, bottom),
  );
}
