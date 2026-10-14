/// 放大镜层：跟着指针在画面上摆一颗取样透镜。
///
/// 门序逐条对齐上游 mImageViewer 的 `draw_fs_loupe_if_active`
/// （`vendor/mimageviewer/src/ui_fullscreen.rs:41723-41845`）：
/// 先判开关，再判「有没有要跟的指针」，再判「取样窗口里还有没有画面」，
/// 再判旋转，最后才是几何与画。**任何一道不过就整块不画**，
/// 不留上一帧的焦点（上游那几条都是 `return`）。
///
/// 与上游的两处有意偏离，都写在自己的注释里：
/// 1. 窗口形状是**圆**而不是方 —— 本仓是触屏优先，圆的才读作「镜头」；
/// 2. 输入用 `Listener` 观察而不是挂 `GestureDetector` —— 见下面「不吃手势那一条」。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:zephyr/page/comic_read/model/reader_magnifier.dart';
import 'package:zephyr/page/comic_read/widgets/magnifier/reader_magnifier_source.dart';

/// 双击透镜切换锁止的判定窗口（时间 + 落点距离）。
///
/// 本层只有 `Listener`，拿不到框架的 `DoubleTapGestureRecognizer`，
/// 所以这两条阈值自己写死：300ms / 24 逻辑像素 —— 与框架缺省的双击档一致。
const Duration _kDoubleTapWindow = Duration(milliseconds: 300);
const double _kDoubleTapSlop = 24;

/// 一次绘制的三块几何：窗口、源矩形（位图像素）、落位矩形（层局部坐标）。
typedef _LoupeFrame = ({Rect loupeRect, Rect src, Rect dst});

/// 焦点处该不该画透镜。
///
/// 上游 `hit_test_or_nearest_in_window(cursor, LOUPE_SAMPLE_WINDOW)`：
/// 焦点稍微移出页面时，只要**以焦点为中心、取样窗口为边长**的那个方框里还有画面，
/// 就继续画。检端部像素本来就得往外挪一点，只按页面命中判会让透镜在那一瞬间整块丢掉
/// （上游实机结论 `実機 2026-08-09`）。
///
/// 抽成顶层纯函数是为了能直接断言，也让门序与绘制分开测试。
bool readerLoupeFocalHasPage({
  required Rect pageRect,
  required Offset focal,
  required double loupeSize,
  required double zoomPercent,
}) {
  // 上游那一句还有个 `rect.is_positive()`：退化矩形（宽或高为 0，含 Rect.zero）在
  // `Rect.overlaps` 的判据下算「重叠」，但它没有一像素可取 —— 必须先拦掉。
  // 用 `!(x > 0)` 而不是 `x <= 0`：NaN 与任何数比较都是 false，前者连 NaN 一起拦。
  if (!(pageRect.width > 0) || !(pageRect.height > 0) || !focal.isFinite) {
    return false;
  }
  final size = normalizeReaderLoupeSize(loupeSize);
  final zoom = normalizeReaderLoupeZoomPercent(zoomPercent);
  final sample = readerLoupeSampleWindow(loupeSize: size, zoom: zoom);
  return Rect.fromCenter(
    center: focal,
    width: sample,
    height: sample,
  ).overlaps(pageRect);
}

/// 阅读器放大镜层。
///
/// **不吃手势那一条**（关键）：这层铺满整个阅读区，绝不能把页面点击与翻页滚动吞掉。
/// 所以观察指针只用 [Listener]（`HitTestBehavior.translucent`）+ [MouseRegion]
/// （`opaque: false`）：两者都只是**观察者**，不进手势竞技场、不把命中判成自己，
/// 下层页面的点击/滚动手势原样收到。也正因如此，手指跟焦走的是
/// `onPointerDown/Move/Up` 而不是 `onPanStart/Update/End` —— 语义等价（按下才跟、
/// 抬手即收），但 `Pan` 识别器会在拖拽时**赢掉竞技场**，把翻页滚动抢走。
///
/// 重绘口径：焦点每变一次只动 [_repaint] 这个 `ValueNotifier`，
/// `CustomPainter` 在 `paint()` 里现读字段 —— 指针移动**不触发任何 widget 重建**。
/// 解码也不在 build 里：只有真的按下/悬停到一页上才 `ensureImage()`。
class ReaderMagnifierLayer extends StatefulWidget {
  const ReaderMagnifierLayer({
    super.key,
    required this.source,
    required this.enabled,
    required this.mode,
    required this.zoomPercent,
    required this.sizeLogical,
    required this.locked,
    this.onLockChanged,
  });

  /// 当前页像素与落位的来源（宿主 per-route 造，见 `ReaderMagnifierScope`）。
  final ReaderMagnifierSource source;

  /// 总开关。关掉时这层直接返回零尺寸：不挂监听、不留指针回调。
  final bool enabled;

  /// 触发方式；`auto` 由**正在被跟踪的那根指针的类型**解析，不猜平台。
  final ReaderMagnifierMode mode;

  /// 放大倍率（百分比）。
  final int zoomPercent;

  /// 窗口边长（逻辑像素）。
  final int sizeLogical;

  /// 锁止：指针离开/抬手后窗口不消失，且窗口本身可拖。
  final bool locked;

  /// 双击透镜切换锁止时回调；null = 不提供这个入口。
  final ValueChanged<bool>? onLockChanged;

  @override
  State<ReaderMagnifierLayer> createState() => _ReaderMagnifierLayerState();
}

class _ReaderMagnifierLayerState extends State<ReaderMagnifierLayer> {
  /// 只驱动重绘的信号；值本身没有意义，+1 就是「该重画了」。
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  /// 焦点（层自己的局部坐标）。null = 现在没有要跟的指针。
  Offset? _focalLocal;

  /// 层的左上角在全局坐标的位置：用来把 `source.globalPageRect` 搬进局部空间。
  /// 每个指针事件刷新一次 —— 只在事件派发期算（`paint()` 期取 `localToGlobal` 不安全）。
  Offset _origin = Offset.zero;

  /// 上一帧**真的画出来**的透镜矩形：抓窗口与双击的命中判都按它，
  /// 也就是用户眼前那颗，而不是按当前尺寸重算一遍。
  Rect? _paintedLoupeRect;

  bool _grabbingWindow = false;
  Offset _grabOffset = Offset.zero;
  Duration? _lastTapAt;
  Offset? _lastTapLocal;

  ReaderMagnifierSource? _listened;

  @override
  void initState() {
    super.initState();
    _syncSourceListening();
  }

  @override
  void didUpdateWidget(covariant ReaderMagnifierLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      // 换来源 = 换了一次阅读会话：上一份焦点不属于这里的任何一页。
      _focalLocal = null;
      _paintedLoupeRect = null;
    }
    if (!widget.locked) {
      _grabbingWindow = false;
    }
    if (oldWidget.enabled != widget.enabled ||
        !identical(oldWidget.source, widget.source)) {
      _syncSourceListening();
    }
    if (oldWidget.zoomPercent != widget.zoomPercent ||
        oldWidget.sizeLogical != widget.sizeLogical ||
        oldWidget.locked != widget.locked ||
        !identical(oldWidget.source, widget.source)) {
      _repaint.value = _repaint.value + 1;
    }
  }

  @override
  void dispose() {
    _detachSourceListening();
    _repaint.dispose();
    super.dispose();
  }

  /// 开/关与换来源时对齐监听。
  ///
  /// 约定：来源的生命周期**不短于本层**（宿主在路由 pop 之后才 dispose 它）。
  /// 关掉时不挂监听 —— 「关了就既没有监听、也没有重建压力」是这一层的一部分。
  void _syncSourceListening() {
    _detachSourceListening();
    if (!widget.enabled) return;
    _listened = widget.source..addListener(_onSourceChanged);
  }

  void _detachSourceListening() {
    _listened?.removeListener(_onSourceChanged);
    _listened = null;
  }

  /// 换页 / 位图刚解出来：几何要重算一次。
  void _onSourceChanged() {
    if (!mounted) return;
    _repaint.value = _repaint.value + 1;
  }

  // ──────────────────────────── 输入 ────────────────────────────

  /// 悬停档认的设备。上游唯一的输入就是 `hover_pos`，而 `hover_pos` 只有
  /// 指针类设备会产生；触屏笔按「手指那一档」处理（它是按下去才画的那种）。
  bool _isPointerDevice(ui.PointerDeviceKind kind) =>
      kind == ui.PointerDeviceKind.mouse ||
      kind == ui.PointerDeviceKind.trackpad;

  /// `auto` 的解析结果：看**这根指针自己的类型**。
  ///
  /// 不用 `kIsWeb`/`defaultTargetPlatform` 猜：触屏笔记本、外接鼠标的平板、
  /// 用键盘的桌面窗口，三种平台判断都会判错。
  ReaderMagnifierMode _resolvedMode(ui.PointerDeviceKind kind) =>
      switch (widget.mode) {
        ReaderMagnifierMode.auto =>
          _isPointerDevice(kind)
              ? ReaderMagnifierMode.hover
              : ReaderMagnifierMode.touch,
        ReaderMagnifierMode.hover => ReaderMagnifierMode.hover,
        ReaderMagnifierMode.touch => ReaderMagnifierMode.touch,
      };

  void _onPointerHover(PointerHoverEvent event) {
    _origin = event.position - event.localPosition;
    if (_resolvedMode(event.kind) != ReaderMagnifierMode.hover) return;
    _setFocal(event.localPosition);
  }

  void _onMouseExit(PointerExitEvent event) {
    // 上游那句 `let Some(cursor) = hover else { return }` 的对应物：
    // 指针离开画面 = 没有焦点可跟了。锁止时留着。
    _origin = event.position - event.localPosition;
    if (widget.locked) return;
    _clearFocal();
  }

  void _onPointerDown(PointerDownEvent event) {
    _origin = event.position - event.localPosition;
    final local = event.localPosition;
    final lens = _paintedLoupeRect;
    if (lens != null && lens.contains(local)) {
      _maybeToggleLockByDoubleTap(event);
      // 锁止态落在透镜里 = 抓窗口（见下面 `_grabOffset`），不再跟焦点。
      final focal = _focalLocal;
      if (widget.locked && focal != null) {
        _grabbingWindow = true;
        _grabOffset = local - focal;
        return;
      }
    }
    if (_resolvedMode(event.kind) != ReaderMagnifierMode.touch) return;
    _setFocal(local);
  }

  void _onPointerMove(PointerMoveEvent event) {
    _origin = event.position - event.localPosition;
    final local = event.localPosition;
    if (_grabbingWindow) {
      _setFocal(local - _grabOffset);
      return;
    }
    final mode = _resolvedMode(event.kind);
    if (mode == ReaderMagnifierMode.touch) {
      // 没按下过的手指移动不该凭空造出一颗透镜。
      if (_focalLocal == null) return;
      _setFocal(local);
      return;
    }
    // 悬停档：鼠标按着拖的时候框架不再发 `PointerHoverEvent`，移动事件补上这一格。
    _setFocal(local);
  }

  void _onPointerUp(PointerUpEvent event) {
    _origin = event.position - event.localPosition;
    _grabbingWindow = false;
    if (widget.locked) return;
    // 悬停档由 `_onMouseExit` 收；这里只管「手指抬起即收」。
    if (_resolvedMode(event.kind) != ReaderMagnifierMode.touch) return;
    _clearFocal();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _grabbingWindow = false;
    if (widget.locked) return;
    _clearFocal();
  }

  /// 双击透镜 = 切锁止。
  ///
  /// 手写计时而不是挂识别器：这层是观察者，任何 `GestureDetector` 都会把落点
  /// 下方的翻页点击吃进竞技场。
  void _maybeToggleLockByDoubleTap(PointerDownEvent event) {
    final onLockChanged = widget.onLockChanged;
    if (onLockChanged == null) return;
    final previousAt = _lastTapAt;
    final previousLocal = _lastTapLocal;
    final isDouble =
        previousAt != null &&
        previousLocal != null &&
        event.timeStamp - previousAt <= _kDoubleTapWindow &&
        (event.localPosition - previousLocal).distance <= _kDoubleTapSlop;
    if (isDouble) {
      _lastTapAt = null;
      _lastTapLocal = null;
      onLockChanged(!widget.locked);
      return;
    }
    _lastTapAt = event.timeStamp;
    _lastTapLocal = event.localPosition;
  }

  void _setFocal(Offset local) {
    _focalLocal = local;
    // 懒解码：只有真的要看了才解，而且报告新矩形（每帧都在报）不重解。
    if (!widget.source.hasImage) {
      unawaited(widget.source.ensureImage());
    }
    _repaint.value = _repaint.value + 1;
  }

  void _clearFocal() {
    if (_focalLocal == null) return;
    _focalLocal = null;
    _paintedLoupeRect = null;
    _grabbingWindow = false;
    _repaint.value = _repaint.value + 1;
  }

  // ──────────────────────────── 几何 ────────────────────────────

  /// 门序与上游一致：焦点 → 有没有像素 → 窗口里还有没有画面 → 退化页 → 三块几何。
  _LoupeFrame? _computeFrame(Size layerSize) {
    final focal = _focalLocal;
    if (focal == null) return null;
    final source = widget.source;
    final image = source.image;
    if (image == null || !source.canSample) return null;
    final pageGlobal = source.globalPageRect;
    if (pageGlobal == null) return null;

    final pageRect = pageGlobal.shift(-_origin);
    final size = normalizeReaderLoupeSize(widget.sizeLogical.toDouble());
    final zoom = normalizeReaderLoupeZoomPercent(widget.zoomPercent.toDouble());
    if (!readerLoupeFocalHasPage(
      pageRect: pageRect,
      focal: focal,
      loupeSize: size,
      zoomPercent: zoom,
    )) {
      return null;
    }

    final uvCenter = readerLoupeUvCenter(
      focalGlobal: focal,
      pageRect: pageRect,
    );
    final halfUv = readerLoupeHalfUv(
      loupeSize: size,
      zoomPercent: zoom,
      displayedPageSize: pageGlobal.size,
    );
    if (halfUv.dx <= 0 || halfUv.dy <= 0) return null;

    final loupeRect = readerLoupeWindowRect(
      focalGlobal: focal,
      loupeSize: size,
      viewport: Offset.zero & layerSize,
    );
    final mapping = readerLoupeSampleMapping(
      uvCenter: uvCenter,
      halfUv: halfUv,
      loupeRect: loupeRect,
    );
    final bitmapUv = readerLoupeBitmapUvRect(
      mapping.uvRect,
      source.bitmapUvSubRect,
    );
    final src = Rect.fromLTRB(
      bitmapUv.left * image.width,
      bitmapUv.top * image.height,
      bitmapUv.right * image.width,
      bitmapUv.bottom * image.height,
    );
    if (src.width <= 0 || src.height <= 0) return null;
    return (loupeRect: loupeRect, src: src, dst: mapping.drawRect);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onPointerHover,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        opaque: false,
        onExit: _onMouseExit,
        // IgnorePointer 是**必须**的：这层铺满阅读区，只要它参与命中判，
        // Stack 从上往下测到它就停 —— 页面点击与翻页滚动当场失效。
        child: IgnorePointer(
          child: CustomPaint(
            // 焦点只动 painter 自己带着的那个 notifier（见 `_ReaderLoupePainter`
            // 的构造）：paint 直接读字段，widget 一棵都不重建。
            painter: _ReaderLoupePainter(this),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _ReaderLoupePainter extends CustomPainter {
  _ReaderLoupePainter(this._owner) : super(repaint: _owner._repaint);

  final _ReaderMagnifierLayerState _owner;

  static const Color _backdrop = Color(0xFF000000);
  static const Color _border = Color(0xFFFFFFFF);
  static const Color _grip = Color(0xE6FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = _owner._computeFrame(size);
    // 抓窗口/双击的命中判按**这一帧真正画出来的**那颗。
    _owner._paintedLoupeRect = frame?.loupeRect;
    final image = _owner.widget.source.image;
    if (frame == null || image == null) return;

    final lens = frame.loupeRect;
    // 上游：`rect_filled(loupe_rect.expand(3.0), 4.0, BLACK)`。
    canvas.drawOval(lens.inflate(3), Paint()..color = _backdrop);

    canvas.save();
    // 偏离上游的方窗：圆透镜。本仓触屏优先，圆的才读作「镜头」。
    canvas.clipPath(Path()..addOval(lens));
    canvas.drawImageRect(image, frame.src, frame.dst, _imagePaint);
    canvas.restore();

    // 上游 `rect_stroke(loupe_rect, 2.0, WHITE, Outside)`：描边在窗口**外面**，
    // 所以这里让描边的中心线外移半个线宽，两档的可见外沿才对得上。
    canvas.drawOval(
      lens.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _border,
    );

    if (_owner.widget.locked) {
      // 锁止时窗口本身可以拖着走；这颗环就是那个把手的可见提示（不画出来的话
      // 「按窗口拖动」这件事只能靠读文档知道）。放在上沿是因为透镜中心那颗像素
      // 正是用户要看的东西，不能被把手盖住。
      final grip = Offset(lens.center.dx, lens.top + 14);
      canvas.drawCircle(grip, 6, Paint()..color = _backdrop);
      canvas.drawCircle(
        grip,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _grip,
      );
    }
  }

  /// 近邻取样 = `FilterQuality.none`。
  ///
  /// 上游走 egui 纹理，缺省 MAG filter 得到的就是近邻；放大镜的目的正是**检像素**，
  /// 高倍率下换 `low`/`medium` 会把该看见的锯齿与色带抹平 —— 那是「好看」而不是「诚实」。
  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.none;

  @override
  bool shouldRepaint(covariant _ReaderLoupePainter oldDelegate) => false;
}
