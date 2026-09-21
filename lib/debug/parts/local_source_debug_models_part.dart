part of '../local_source_debug_page.dart';
// 调试页的数据模型（翻页分段记录、预取页、解码器模式）与图片格式嗅探


/// 一次翻页的分段记录。留着历史才能对比「全尺寸 vs 显示尺寸」。
class _StageRow {
  _StageRow({
    required this.index,
    required this.mode,
    required this.read,
    required this.decode,
    required this.pack,
    required this.paint,
    required this.total,
    required this.width,
    required this.height,
    required this.cacheHit,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.prefetchHit = false,
    this.prefetchCost,
    this.prefetchDuringDecode = 0,
    this.prefetchWait,
  });

  final int index;
  final String mode;
  final Duration read;

  /// 编码字节 → 位图。
  ///
  /// 两条路径的**含义不同，别直接比**：外壳路径是引擎解码；
  /// Rust 路径是「Rust 解码器 + FRB 过桥」，读页那一段也并了进来（所以 `read` 为 0）。
  final Duration decode;

  /// Rust 路径专有：位图字节 → `ui.Image`（`ui.decodeImageFromPixels`）。
  /// 外壳路径没有这一步，记 0。
  final Duration pack;

  final Duration paint;
  final Duration total;
  final int width;
  final int height;

  /// 解码器输出的原始尺寸（降采样前）。外壳路径拿不到，记 0。
  final int sourceWidth;
  final int sourceHeight;

  final bool cacheHit;

  /// 这一页是**预取命中**：翻页时既没解码也没建图，`decode` / `pack` 都是 0。
  ///
  /// 必须与 `cacheHit` 分开标：`cacheHit` 说的是「图片缓存命中，没重新解码」，
  /// 而这一条是「用户在翻之前我们就解好了」—— 成本没有消失，只是**挪到了翻页之外**。
  final bool prefetchHit;

  /// 预取这一页时实际花掉的（解码 + 建图），用于证明成本只是被挪走而非消失。
  final Duration? prefetchCost;

  /// 这一页**开始解码那一刻**，预取正占着几张许可。
  ///
  /// 这是「解 572 ms 而不是 431 ms」的解释项：dav1d 一条流几乎不并行
  /// （1 核 610–667 ms / 16 核 269–295 ms），所以两个解码同时跑不是分核，是双输。
  /// 记在行上而不是让人自己从「许可 N/6 在用」去推 —— 那个数在翻页结束时就变了。
  final int prefetchDuringDecode;

  /// 翻页等了「正在预取的这一页」多久才拿到图（合并路径，见 `_loadPage`）。
  ///
  /// 走这条路径时 `decode` / `pack` 仍是 0（翻页没解），但**用户确实等了**——
  /// 等待时间记在这里，不记进「屏」，否则历史行会谎报「合 9 ms」。
  final Duration? prefetchWait;

  int get pixels => width * height;

  /// RGBA 位图的字节数 —— 也就是要走一趟 PCIe 的那个量。
  int get bitmapBytes => pixels * 4;

  /// 相对原始像素量省下的比例，0 表示没省。
  double get pixelSaving {
    final source = sourceWidth * sourceHeight;
    if (source == 0) return 0;
    return 1 - pixels / source;
  }
}


/// 预取好的一页：已经解完码、已经建成 `ui.Image`，翻到它时零解码零建图。
///
/// 为什么必须有这个：这本 AVIF 单页冷解码的地板是 **270 ms**
/// （AV1 4:4:4、一个 tile、dav1d 已用满 16 核仍只有 2.25× 加速 —— 见
/// `docs/v0.1-local-core.md` §12.4），而且 **NVDEC 明确拒绝 4:4:4**
/// （`av1_cuvid` 报 `not supported with this chroma format`），
/// 所以「把解码本身做快」这条路在软硬两侧都走不通。
/// 唯一能让翻页掉到 200 ms 以下的办法是**别在翻页时解码**。
class _PrefetchedPage {
  _PrefetchedPage({
    required this.index,
    required this.targetWidth,
    required this.image,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.decode,
    required this.pack,
  });

  final int index;

  /// 预取时的目标宽。翻页时若窗口/开关变了，这份就作废（宁可重解也不能给错尺寸）。
  final int? targetWidth;

  final ui.Image image;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;

  /// 预取时花掉的两段成本，翻页后原样报出来。
  final Duration decode;
  final Duration pack;

  int get bytes => width * height * 4;

  void dispose() => image.dispose();
}


/// 这一页让谁来解码。
///
/// 这一维是 `avif` 逼出来的：Windows 引擎（`flutter_windows.dll`）没有链入 AV1
/// 解码器，外壳路径对它**必然失败**；而 Rust 侧（dav1d）能解。
/// 留着开关是为了让两条路径的耗时当场可比，而不是只能信文档里的数字。
enum _DecoderMode {
  /// 先试 Rust；它明确回答「这页归外壳」时才退回外壳。
  auto('解码器：自动'),

  /// 只走 Rust（`local_page_pixels`）。avif 唯一能出图的形态。
  rust('解码器：Rust'),

  /// 只走外壳（Flutter / Skia），即「编码字节过桥」。
  shell('解码器：外壳');

  const _DecoderMode(this.label);

  final String label;
}


/// 从编码字节的魔数判断格式。
///
/// 只看前 16 字节，不解码 —— 目的是让「解码 500 ms」这个数字带上上下文：
/// 44.8 MPix 的 JPEG 慢是必然的，跟读取路径无关。
String sniffImageFormat(Uint8List? bytes) {
  if (bytes == null || bytes.length < 12) return '未知';
  final b = bytes;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'JPEG';
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'PNG';
  }
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'GIF';
  if (b[0] == 0x42 && b[1] == 0x4D) return 'BMP';
  if (b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'WebP';
  }
  return '未知';
}
