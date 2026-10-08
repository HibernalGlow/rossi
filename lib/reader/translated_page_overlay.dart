import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';

/// 译文**叠层**：把图层 JSON 画成一层盖在底图之上的字，不改底图一个像素。
///
/// # 为什么挂在 `RotatedBox` 里面
///
/// `read_mode_image_builder.dart` 那一层的注释写着：「旋转放在这一层而不是
/// `ImageDisplay` 里，是因为本地 GPU 管线那条分支走的是完全不同的绘制路径，
/// 放在外层才能让两条路径一起旋转」。同一段代码正好也是叠层的挂载理由 ——
/// 放进同一个 `RotatedBox`，旋转 / 双页 / 页宽适配**自动跟随**，不必在两条
/// 渲染路里各算一遍变换（ADR-0018 §决定 4 那条解冻点名的就是这个）。
///
/// # 为什么不注入增强图轨
///
/// 占轨的是烘焙档（一张烤好的 PNG），它占掉那一页唯一的像素，所以必须压掉超分。
/// 这一层不烤进像素：译文是盖上去的一层，底图换不换、换哪张由控制器那一侧决定 ——
/// 「翻译迁移到超分后的图上」到这一步才真的成立。谁上屏由 `resolvePageDisplaySource`
/// 裁决，这里只画已经被选中的那一格。
///
/// # 底图必须是擦干净的
///
/// 渲染台实测：译文叠在没擦字的原图上字压字率 0.085，叠在擦字底上 0.000。
/// 所以这一层只该叠在**擦字底图**（或它的超分产物）上；而「这一页到底有没有
/// 擦字底图」由控制器在 `_turnOn` 时按 `TranslatedPageCache.overlayReady` 判过一次，
/// 这里只读它登记的结果 —— 两处各判一次就会在中间那一格画出半截译文。
class TranslatedPageOverlay extends StatefulWidget {
  const TranslatedPageOverlay({
    required this.pageIndex,
    required this.boxSize,
    this.slice = PageSlice.full,
    super.key,
  });

  final int pageIndex;

  /// 这一槽位显示的是整页还是半页（横排拆分阅读）。
  ///
  /// 图层的坐标始终是**整页**物理像素，所以半页不是「不画」而是「按同一把尺裁」：
  /// 底图那一路（`ImageSurface` / `ImageDisplay`）本来就按 `PageSlice.uvRect` 裁，
  /// 这一层跟着裁才能对齐 —— 之前直接不挂叠层，双页读法下芯片说「译文页」而画面上
  /// 一个中文都没有，那是最难发现的一类错。
  final PageSlice slice;

  /// 这一层可用的空间（逻辑尺寸，旋转坐标由外层 `RotatedBox` 负责）。
  final Size boxSize;

  @override
  State<TranslatedPageOverlay> createState() => _TranslatedPageOverlayState();

  /// 图层按「档名 + 页号」缓存在 widget 层。
  ///
  /// 为什么缓：滚动模式一页要重 build 很多次，而那份 JSON 是几百 KB 的解析。
  /// 为什么不做成全局单例：档名是**这本书 + 这份配置**的函数，换书不清就串页
  /// （本仓栽过两次，都是 per-book 状态住在单例里）—— 所以键里带档名，
  /// 而控制器的 `reset()` 会调 [clearCache] 把它整份丢掉。
  static final Map<String, TranslatedPageLayer?> _cache = {};

  static void clearCache() => _cache.clear();
}

class _TranslatedPageOverlayState extends State<TranslatedPageOverlay> {
  TranslatedPageLayer? _layer;
  String? _loadedKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(TranslatedPageOverlay old) {
    super.didUpdateWidget(old);
    if (old.pageIndex != widget.pageIndex ||
        old.boxSize != widget.boxSize ||
        old.slice != widget.slice) {
      _resolve();
    }
  }

  /// 控制器给得出档名才画。给不出（没按过「译」、或那一页走的是烘焙档）就是没叠层。
  String? _key() {
    final label = TranslatedPageController.instance.overlayLabelFor(
      widget.pageIndex,
    );
    return label == null ? null : '$label/p${widget.pageIndex}';
  }

  void _resolve() {
    final key = _key();
    if (key == null) {
      if (_layer != null || _loadedKey != null) {
        _schedule(() => setState(() {
          _layer = null;
          _loadedKey = null;
        }));
      }
      return;
    }
    if (_loadedKey == key) return;
    final hit = TranslatedPageOverlay._cache[key];
    if (hit != null) {
      _schedule(() => _adopt(key, hit));
      return;
    }
    // 读盘放在帧之后：`didChangeDependencies` 里同步 setState 会当场炸。
    _schedule(() async {
      final loaded = await _read(key);
      if (!mounted || _loadedKey == key) return;
      _adopt(key, loaded);
    });
  }

  void _schedule(void Function() body) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) body();
      });

  Future<TranslatedPageLayer?> _read(String key) async {
    final label = key.substring(0, key.lastIndexOf('/'));
    final file = await TranslatedPageCache.layerFile(
      label: label,
      pageIndex: widget.pageIndex,
    );
    if (!file.existsSync()) return null;
    // 解坏了返回 null，由裁决回落到别的来源 —— 不是拿半份数据硬画。
    final layer = TranslatedPageLayer.tryDecode(await file.readAsString());
    TranslatedPageOverlay._cache[key] = layer;
    return layer;
  }

  void _adopt(String key, TranslatedPageLayer? layer) {
    setState(() {
      _loadedKey = key;
      _layer = layer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layer = _layer;
    // 没这一页的图层就一个 widget 都不留，而不是画一张空层挡命中测试。
    if (layer == null || widget.boxSize.isEmpty) return const SizedBox.shrink();
    // 「对比原图」开着就什么都不画：旁路屏蔽的是增强图轨，而这一层不占轨、
    // 屏蔽不到它 —— 少这一句，用户按下对比原图看到的是「原图 + 中文」。
    if (TranslatedPageController.instance.bypassesOriginalPreview) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      size: widget.boxSize,
      painter: _OverlayPainter(layer: layer, slice: widget.slice),
    );
  }
}

/// 这一槽位显示的是**整页像素里的哪一块**。
///
/// 与底图那一路共用 `PageSlice.uvRect` 这一把尺（只切左右两半），所以「裁哪里」
/// 不会在 Flutter 侧与渲染侧各算一遍。
ui.Rect overlaySliceRect({
  required double pageWidth,
  required double pageHeight,
  required PageSlice slice,
}) {
  final uv = slice.uvRect;
  return ui.Rect.fromLTRB(
    pageWidth * uv[0],
    pageHeight * uv[1],
    pageWidth * uv[2],
    pageHeight * uv[3],
  );
}

///  contain-fit 的结果：底图实际画在画布的哪一块、按多大倍率。
typedef OverlayFit = ({Offset offset, double scale});

/// 这一层相对画布该落在哪、按多大倍率画。
///
/// 用 contain-fit 而不是直接铺满盒子：底图在阅读器里是按页宽/页高适配后**居中**
/// 显示的，盒子与底图不同比例时上下（或左右）会留边。叠层若按盒子铺满，中文会
/// 整体偏离气泡 —— 这种偏移在横长页与双页上最先露出来。两条渲染路都把底图按
/// contain 放，所以这一份算式对两边都成立。
///
/// 尺寸不合法（0、负、NaN）时返回 null = **什么都不画**，而不是猜个倍率把字画到框外。
OverlayFit? overlayPaintFit({
  required double boxWidth,
  required double boxHeight,
  required double baseWidth,
  required double baseHeight,
}) {
  if (!boxWidth.isFinite ||
      !boxHeight.isFinite ||
      !baseWidth.isFinite ||
      !baseHeight.isFinite ||
      boxWidth <= 0 ||
      boxHeight <= 0 ||
      baseWidth <= 0 ||
      baseHeight <= 0) {
    return null;
  }
  final scale = boxWidth / baseWidth < boxHeight / baseHeight
      ? boxWidth / baseWidth
      : boxHeight / baseHeight;
  return (
    offset: Offset(
      (boxWidth - baseWidth * scale) / 2,
      (boxHeight - baseHeight * scale) / 2,
    ),
    scale: scale,
  );
}

/// 把图层画进 `size` 这块盒子：先按 [slice] 裁，再 contain-fit。
///
/// 绘制器与测试共用这一个入口 —— 「裁哪一块、按多大倍率」只此一处算法，
/// 两边各写一遍就会出现「测试绿着、真机上左右半页各画一套」。
void paintTranslatedPageLayer(
  ui.Canvas canvas, {
  required TranslatedPageLayer layer,
  required ui.Size size,
  PageSlice slice = PageSlice.full,
}) {
  final crop = overlaySliceRect(
    pageWidth: layer.pageWidth.toDouble(),
    pageHeight: layer.pageHeight.toDouble(),
    slice: slice,
  );
  final fit = overlayPaintFit(
    boxWidth: size.width,
    boxHeight: size.height,
    baseWidth: crop.width,
    baseHeight: crop.height,
  );
  if (fit == null) return;
  canvas.clipRect(ui.Rect.fromLTRB(0, 0, size.width, size.height));
  canvas.save();
  canvas.translate(
    fit.offset.dx - crop.left * fit.scale,
    fit.offset.dy - crop.top * fit.scale,
  );
  // 倍率交给 `paintLayer`：框与字号按同一个倍率放大，断行结果与 1× 一致。
  TranslatedPageRenderer.paintLayer(canvas, layer, scale: fit.scale);
  canvas.restore();
}

/// 一层画什么。
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.layer, required this.slice});

  final TranslatedPageLayer layer;
  final PageSlice slice;

  @override
  void paint(ui.Canvas canvas, ui.Size size) => paintTranslatedPageLayer(
    canvas,
    layer: layer,
    size: size,
    slice: slice,
  );

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.layer != layer || old.slice != slice;
}
