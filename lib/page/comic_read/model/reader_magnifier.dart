/// 放大镜（loupe）的取样几何。
///
/// 逐条对齐 mImageViewer 的 `ui_fullscreen.rs`：常数取自 `LOUPE_*`
/// （`:328-333`），映射函数是 `loupe_sample_mapping`（`:3821-3846`），
/// 窗口落点是绘制点上的那段（`:41811-41822`）。那边是 egui + 纹理，
/// 这边是 `Canvas` + `ui.Image`，**几何口径一致**，只有像素来源不同。
///
/// 上游没做的两件事这里也不做，理由写在各自的判据里：
/// 旋转页（UV 逆变换在上游 v0.7.0 就明确不支持）、以及全景模式
/// （本仓还没有全景模式那一档）。
library;

import 'dart:ui';

/// 放大镜由哪种输入驱动。
enum ReaderMagnifierMode {
  /// 按设备自动选：有指针设备就跟随悬停，纯触屏就跟随手指。
  auto,

  /// 只跟随鼠标悬停（指针不离开画面才显示）。
  hover,

  /// 只跟随手指拖拽（按下才显示，抬手即收）。
  touch,
}

/// 窗口边长（逻辑像素）与其上下限。
///
/// 上游那个 300 是给桌面全屏定的；本仓要装进手机屏，所以默认档小一档，
/// 但**允许拖到比上游更大**——上限按「不超过短边」在执行侧再收一次。
const double kReaderLoupeSizeDefault = 220;
const double kReaderLoupeSizeMin = 120;
const double kReaderLoupeSizeMax = 400;

/// 放大倍率（百分比）与其上下限。
const int kReaderLoupeZoomPercentDefault = 300;
const int kReaderLoupeZoomPercentMin = 150;
const int kReaderLoupeZoomPercentMax = 800;

/// 窗口相对焦点的偏移，照上游 `LOUPE_OFFSET`。
const double kReaderLoupeOffset = 40;

/// 越界收拢的最小边距，照上游那两行 `.max(full_rect.min + 4.0)`。
const double kReaderLoupeEdgeInset = 4;

/// 上游 `LOUPE_SAMPLE_WINDOW` 的对应物：窗口在画面上实际覆盖的一边长。
///
/// 焦点稍微移出页面时，只要这个窗口内还有画面，放大镜就不消失 ——
/// 检端部像素本来就需要往外挪一点，只按页面命中判会让放大镜在边上瞬间整块丢掉
/// （上游注释里那条实机结论：`実機 2026-08-09`）。
double readerLoupeSampleWindow({
  required double loupeSize,
  required double zoom,
}) {
  final factor = readerLoupeZoomFactor(zoom);
  return factor <= 0 ? loupeSize : loupeSize / factor;
}

/// 百分比 → 倍率。
double readerLoupeZoomFactor(double zoomPercent) => zoomPercent / 100;

double normalizeReaderLoupeSize(double size) => size.isFinite
    ? size.clamp(kReaderLoupeSizeMin, kReaderLoupeSizeMax)
    : kReaderLoupeSizeDefault;

double normalizeReaderLoupeZoomPercent(double percent) => !percent.isFinite
    ? kReaderLoupeZoomPercentDefault.toDouble()
    : percent.roundToDouble().clamp(
        kReaderLoupeZoomPercentMin.toDouble(),
        kReaderLoupeZoomPercentMax.toDouble(),
      );

/// 一次倍率步进：一档 25%（面板上的 ± 按钮与滚轮共用）。
double stepReaderLoupeZoomPercent(double percent, int direction) =>
    normalizeReaderLoupeZoomPercent(
      percent + direction * 25 * (percent >= 400 ? 2 : 1),
    );

/// 焦点在页面上的归一化 UV（口径同 `screen_to_source_normalized`）。
///
/// [pageRect] 是**这一页在屏幕上的落位矩形**（已经算过对齐与留白）。
Offset readerLoupeUvCenter({
  required Offset focalGlobal,
  required Rect pageRect,
}) {
  final width = pageRect.width;
  final height = pageRect.height;
  if (width <= 0 || height <= 0) return const Offset(0.5, 0.5);
  return Offset(
    (focalGlobal.dx - pageRect.left) / width,
    (focalGlobal.dy - pageRect.top) / height,
  );
}

/// 取样窗口在 UV 空间的半宽半高。
///
/// 上游写的是 `sample_px_half = LOUPE_SIZE * 0.5 / (total_scale * LOUPE_ZOOM)`
/// 再除以纹理像素数（`:41808-41809`）。`total_scale * tex_size` 就是这一页
/// **画在屏幕上的尺寸**，所以这里直接用 `displayedPageSize` —— 两边算的是同一个数，
/// 只是本仓不需要把纹理尺寸与缩放比分开传。
Offset readerLoupeHalfUv({
  required double loupeSize,
  required double zoomPercent,
  required Size displayedPageSize,
}) {
  final factor = readerLoupeZoomFactor(zoomPercent);
  if (factor <= 0 ||
      !displayedPageSize.width.isFinite ||
      !displayedPageSize.height.isFinite ||
      displayedPageSize.width <= 0 ||
      displayedPageSize.height <= 0) {
    return Offset.zero;
  }
  final half = loupeSize * 0.5 / factor;
  return Offset(
    half / displayedPageSize.width,
    half / displayedPageSize.height,
  );
}

/// 放大镜窗口该摆在哪儿（含出屏翻转），照 `:41811-41822`。
///
/// 默认右下摆；任何一边越界就翻到对侧；再越界就贴回视口内边。
Rect readerLoupeWindowRect({
  required Offset focalGlobal,
  required double loupeSize,
  required Rect viewport,
}) {
  final size = normalizeReaderLoupeSize(loupeSize);
  var left = focalGlobal.dx + kReaderLoupeOffset;
  var top = focalGlobal.dy + kReaderLoupeOffset;
  if (left + size > viewport.right)
    left = focalGlobal.dx - kReaderLoupeOffset - size;
  if (top + size > viewport.bottom)
    top = focalGlobal.dy - kReaderLoupeOffset - size;
  if (left < viewport.left + kReaderLoupeEdgeInset) {
    left = viewport.left + kReaderLoupeEdgeInset;
  }
  if (top < viewport.top + kReaderLoupeEdgeInset) {
    top = viewport.top + kReaderLoupeEdgeInset;
  }
  return Rect.fromLTWH(left, top, size, size);
}

/// 一次取样：UV 子矩形 + 位图在该子矩形下应占的绘制矩形。
class ReaderLoupeMapping {
  const ReaderLoupeMapping({required this.uvRect, required this.drawRect});

  /// 要 sampled 的那一小块 UV（已经裁进 `[0,1]`）。
  final Rect uvRect;

  /// 位图在放大镜窗口内的落点：可能比窗口小 —— 这正是「贴边仍保持同倍率」的实现方式，
  /// 多余的边角留给底色。
  final Rect drawRect;
}

/// `loupe_sample_mapping` 的逐行移植。
///
/// 关键在最后那个 fraction：UV 被裁进页面内之后，绘制矩形**也按同样比例收缩**，
/// 于是每单位屏幕像素对应的源像素不变 —— 边缘处看到的是「窗口里画面贴边」，
/// 而不是「画面被拉伸」。写成「始终铺满窗口」就在端点上悄悄多放大了。
ReaderLoupeMapping readerLoupeSampleMapping({
  required Offset uvCenter,
  required Offset halfUv,
  required Rect loupeRect,
}) {
  assert(halfUv.dx > 0 && halfUv.dy > 0, '取样半宽必须为正');
  final desiredMin = Offset(uvCenter.dx - halfUv.dx, uvCenter.dy - halfUv.dy);
  final desiredMax = Offset(uvCenter.dx + halfUv.dx, uvCenter.dy + halfUv.dy);
  final uvMin = Offset(
    desiredMin.dx.clamp(0.0, 1.0),
    desiredMin.dy.clamp(0.0, 1.0),
  );
  final uvMax = Offset(
    desiredMax.dx.clamp(0.0, 1.0),
    desiredMax.dy.clamp(0.0, 1.0),
  );
  final desiredSize = Offset(
    desiredMax.dx - desiredMin.dx,
    desiredMax.dy - desiredMin.dy,
  );
  if (desiredSize.dx <= 0 || desiredSize.dy <= 0) {
    return ReaderLoupeMapping(uvRect: loupeRect, drawRect: loupeRect);
  }
  final minFraction = Offset(
    (uvMin.dx - desiredMin.dx) / desiredSize.dx,
    (uvMin.dy - desiredMin.dy) / desiredSize.dy,
  );
  final maxFraction = Offset(
    (uvMax.dx - desiredMin.dx) / desiredSize.dx,
    (uvMax.dy - desiredMin.dy) / desiredSize.dy,
  );
  final imageMin = Offset(
    loupeRect.left + minFraction.dx * loupeRect.width,
    loupeRect.top + minFraction.dy * loupeRect.height,
  );
  final imageMax = Offset(
    loupeRect.left + maxFraction.dx * loupeRect.width,
    loupeRect.top + maxFraction.dy * loupeRect.height,
  );
  return ReaderLoupeMapping(
    uvRect: Rect.fromLTRB(uvMin.dx, uvMin.dy, uvMax.dx, uvMax.dy),
    drawRect: Rect.fromLTRB(imageMin.dx, imageMin.dy, imageMax.dx, imageMax.dy),
  );
}

/// 把「页面 UV」换算成「位图 UV」。
///
/// 横长页被拆成两半时，这一页画面上只是位图的左（或右）一半；
/// 不做这一步的话放大镜会在半页上取到整页的中间。
Rect readerLoupeBitmapUvRect(Rect pageUvRect, Rect bitmapUvSubRect) {
  final w = bitmapUvSubRect.width;
  final h = bitmapUvSubRect.height;
  return Rect.fromLTRB(
    bitmapUvSubRect.left + pageUvRect.left * w,
    bitmapUvSubRect.top + pageUvRect.top * h,
    bitmapUvSubRect.left + pageUvRect.right * w,
    bitmapUvSubRect.top + pageUvRect.bottom * h,
  );
}

/// 旋转页不做放大 —— 与上游同一口径：任意角度旋转下 UV 逆变换没实现，
/// 与其画错，不如不画。返回 `true` 表示当前页可以取样。
bool readerLoupeSupportedForRotation(int rotationDegrees) =>
    rotationDegrees % 360 == 0;
