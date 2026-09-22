import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';

/// 当前在用哪条显示通路。
///
/// 两条路的意义完全不同，所以它是要被显示出来的一个事实而不是实现细节：
/// - [gpu]：像素全程在显存里，Dart 只拿到一个 `textureId`；
/// - [cpu]：`PageSource.load` → RGBA 过桥 → `ui.decodeImageFromPixels`。
///   它有**两种**用处，别把第二种当成"降级"：一是呈现器还没就绪、或这一份
///   来源在两侧对不上时的兜底（"别让人对着黑屏"）；二是**翻页时进场/退场
///   那两半的画面** —— 共享纹理只有一张、且归当前页用，滑动期间还没有谁
///   是"当前页"，两边都只能画自己那份位图。
enum ImageSurfacePath { gpu, cpu }

/// 非当前页那份位图的目标宽度系数（相对控件的物理宽度）。
///
/// # 为什么邻页那张要更小
///
/// 邻页那份位图的唯一用途是「翻页滑动时那两半里有画面」，而它**到达的时间**
/// 直接决定翻页那一瞬是不是黑：视口宽全解一次要 300–400 ms（大头是过桥与
/// `decodeImageFromPixels`，见 `_ensureCpuContent`），而**连翻的间隔只有两三百
/// 毫秒** —— 全宽解注定赶不上。赶不上就是两条路同时没料，于是透出阅读底色
/// （漫画默认黑底），也就是用户看到的那「黑一下」。
///
/// 面积按系数平方缩，过桥字节数跟着掉：0.5 ⇒ 位图只有 1/4 大、这一段降到
/// 百毫秒以内，翻页那一瞬间就已经有像素可画。**买的是「先有画面」**，
/// 代价只是滑动过程中那一份略糊 —— 它本来就在移动，且很快被全清的纹理帧换掉。
///
/// 当前页不吃这个系数（见 [ImageSurface.bitmapWidthScale] 的调用点）：
/// 它那份位图是留给**自己退场**时用的，那时候要清晰。
const double kNeighborBitmapWidthScale = 0.5;

/// 一页的显示节点 —— 两条上屏路径在这里**收敛成一个**。
///
/// # 为什么它必须是一个组件，而不是页面里的一个 if
///
/// 因为它要维持的是**与 native 侧的状态一致**：纹理有没有注册、那边打开的是哪一份
/// 来源、呈现的是哪一页、目标尺寸是多少。这些一旦散在页面里，
/// 「换书」「拖窗口」「就绪那一刻补一次」就会各写一份，然后互相打架
/// （典型症状：拖完窗口只剩底色；页码与画面对不上）。
/// 收敛成一个组件之后，页面只负责「打开哪一本、在第几页」，
/// 让画面追上那个状态是节点的职责。
///
/// # 它不拥有什么
///
/// 不拥有 [PageSource] 的生命周期（由 Reader 打开与关闭），也不决定页码。
/// 它只是一个消费者：拿一个已打开的来源和一个下标，把它画出来。
///
/// # 两条路共用一个来源
///
/// 这是「先收敛页来源、再换显示节点」里前半句要买的东西：页表、会话、关闭都只有
/// 一份，所以两条路不会各自数出不同的页数，也不会各自漏一个会话。
///
/// # 翻页时为什么两边都能出图
///
/// 因为共享纹理只有一张，滑动期间「旧页」与「新页」**谁都不是当前页**。
/// 老做法是让非当前页去画一个 `fontSize: 150` 的页码占位 —— 于是翻页时
/// 半屏先被一个大数字顶住，等滑动过半、当前页落定、`present` 回来才换成画面。
///
/// 现在每个 slot 都画**这一页自己的位图**（[ImageSurface.holdOwnBitmap]），
/// 于是：进场那一半在它还是邻页时就已经把位图解好了，退场那一半在它还是
/// 当前页时顺手解了一份留着。两边都有像素，翻页全程没有占位、也没有空窗。
class ImageSurface extends StatefulWidget {
  const ImageSurface({
    super.key,
    required this.source,
    required this.index,
    required this.presenter,
    this.drivesPresentation = true,
    this.holdOwnBitmap = false,
    this.bitmapWidthScale = 1.0,
    this.onPathChanged,
    this.onIntrinsicSize,
    this.slice = PageSlice.full,
  });

  /// 已打开的页面来源。
  final PageSource source;

  /// 要显示第几页（0 基）。
  final int index;

  /// 横长页分割切片。
  final PageSlice slice;

  /// GPU 呈现器的就绪状态与呈现目标。由调用方创建并 [GpuPresentController.start]。
  final GpuPresentController presenter;

  /// 本节点是否负责把这一页**推上共享纹理**（`present`）。
  ///
  /// 同一时刻**只能有一个**为真：外部纹理只有一张，两个节点都推就是 Ping-Pong
  /// 拔河（表现为红黄闪）。所以行模式里只有当前页传 `true`，邻页传 `false` ——
  /// 邻页只画自己那份位图，不去碰那条共享的呈现链路。
  final bool drivesPresentation;

  /// 是否**留着**这一页自己的位图。
  ///
  /// 留着的理由不是"画质"，是**翻页时的那两半都要有画面**：共享纹理只有一张，
  /// 新页一旦 `present` 就把它覆写了，而这时候旧页还在屏幕上滑出去（滑动过半时
  /// 两页各占一半）。旧页此时能画的只剩**它自己的**位图 —— 所以这一页在上屏期间
  /// 就得顺手把位图解好留着，等它退场时接上。
  ///
  /// 代价是每页多留一张**视口宽度**的位图（不是全尺寸：解码宽度按控件的物理宽度
  /// 给，见 [_ImageSurfaceState._ensureCpuContent]），换来的是翻页两侧都不空。
  /// 关掉即回到「上屏成功就释放位图」的老行为。
  final bool holdOwnBitmap;

  /// 这一份位图的**目标宽度系数**（相对控件的物理宽度），见
  /// [kNeighborBitmapWidthScale]。
  ///
  /// 1.0 = 与视口等宽。邻页传 [kNeighborBitmapWidthScale]，把自己那份位图的
  /// 到达时间压进"翻页瞬间"以内；当前页保持 1.0，因为它那份是留给自己
  /// **退场**时画的，那时候画面要清晰。
  ///
  /// 系数变了（邻页变当前页）会让 [_ImageSurfaceState._ensureCpuContent]
  /// 按新宽度重解一次 —— 而重解期间**旧位图一直挂着**（`_cpuImage` 只在新图
  /// 解好之后才换），所以那次升级不会制造空窗。
  final double bitmapWidthScale;

  /// 通路变化时的通知。界面用它显示「现在走的是哪条路」。
  final ValueChanged<ImageSurfacePath>? onPathChanged;

  /// 原始像素尺寸，供阅读器按真实宽高比计算缩放和旋转。
  final ValueChanged<Size>? onIntrinsicSize;

  @override
  State<ImageSurface> createState() => _ImageSurfaceState();
}

class _ImageSurfaceState extends State<ImageSurface> {
  ui.Image? _cpuImage;

  /// 已经解出来的位图属于哪个 `(来源, 页, 目标宽度)`。
  /// 三者任一变了就得重解 —— 宽度也算进去，因为降采样解码的结果与宽度绑定。
  PageSource? _loadedSource;
  int? _loadedIndex;
  int? _loadedWidth;

  /// 正在飞的那一次解码请求的目标。用来避免对**同一个目标**重复发请求；
  /// 目标不同（用户翻页了）就照发不误 —— 靠 [_loadToken] 丢弃过期结果，
  /// 而不是把新请求也挡在外面（那样会卡住不加载）。
  PageSource? _loadingSource;
  int? _loadingIndex;
  int? _loadingWidth;

  /// 最近一次失败是不是已经报过（避免每帧重复请求同一个解不出来的页）。
  PageSource? _failedSource;
  int? _failedIndex;
  String? _failureMessage;

  /// 「没轮到就作废」（`cancelled`）之后的重试。
  ///
  /// 这一类结果**不改任何状态**，所以不会再有下一次 `build` 把请求发出去 ——
  /// 不主动安排一次，这一页就停在没有像素的状态上，比从前"被永久拉黑"好不了多少。
  /// 上限只是防止某一页被反复作废时无限重试；到顶之后不拉黑，下一次布局照发。
  Timer? _cancelRetry;
  int _cancelRetries = 0;
  static const int _maxCancelRetries = 8;
  static const Duration _cancelRetryDelay = Duration(milliseconds: 120);

  /// 在飞请求的序号。回来时若已不是当前序号，说明这一页已经过期，丢掉结果。
  int _loadToken = 0;

  ImageSurfacePath _path = ImageSurfacePath.cpu;
  ImageSurfacePath? _reportedPath;

  Size? _physicalSize;
  (PageSource, int)? _sizeRequest;
  (PageSource, int, Size)? _reportedSize;

  GpuPresentState? _lastKnownState;
  int? _lastKnownTextureId;
  int _lastKnownPresentCount = 0;
  bool _lastKnownPresenting = false;
  bool _syncing = false;
  (GpuPresentController, PageSource, int, Size)? _failedGpuRequest;

  @override
  void initState() {
    super.initState();
    _lastKnownState = widget.presenter.state;
    _lastKnownTextureId = widget.presenter.textureId;
    _lastKnownPresentCount = widget.presenter.presentCount;
    _lastKnownPresenting = widget.presenter.isPresenting;
    widget.presenter.addListener(_onPresenterChanged);
  }

  @override
  void didUpdateWidget(ImageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter)) {
      oldWidget.presenter.removeListener(_onPresenterChanged);
      _lastKnownState = widget.presenter.state;
      _lastKnownTextureId = widget.presenter.textureId;
      _lastKnownPresentCount = widget.presenter.presentCount;
      _lastKnownPresenting = widget.presenter.isPresenting;
      widget.presenter.addListener(_onPresenterChanged);
    }
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.index != widget.index) {
      // 换来源或翻页：失败记录不再适用，在飞的解码也要作废。
      // **必须立刻作废**，否则切页瞬间会拿旧序号的结果当新页画出来。
      _loadToken++;
      _failedSource = null;
      _failedIndex = null;
      _failureMessage = null;
      _cancelRetry?.cancel();
      _cancelRetry = null;
      _cancelRetries = 0;
      _releaseCpuImage();
    }
    if (oldWidget.holdOwnBitmap && !widget.holdOwnBitmap) {
      // 这一个开关关掉之后不再替「退场时那一半」留画面，位图没必要继续占着。
      _releaseCpuImage();
    }
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChanged);
    _loadToken++;
    _cancelRetry?.cancel();
    _cancelRetry = null;
    _cpuImage?.dispose();
    _cpuImage = null;
    super.dispose();
  }

  /// 安排一次「被作废之后」的重试，见 [_cancelRetry]。
  void _scheduleCancelRetry() {
    if (_cancelRetries >= _maxCancelRetries) {
      return;
    }
    _cancelRetries++;
    _cancelRetry?.cancel();
    _cancelRetry = Timer(_cancelRetryDelay, () {
      if (!mounted) {
        return;
      }
      final Size? size = _physicalSize;
      if (size == null) {
        return;
      }
      unawaited(_sync(size));
    });
  }

  void _onPresenterChanged() {
    if (!mounted) {
      return;
    }
    final GpuPresentState newState = widget.presenter.state;
    final int? newTex = widget.presenter.textureId;
    final int newCount = widget.presenter.presentCount;
    final bool presenting = widget.presenter.isPresenting;
    final bool finishedPresenting = _lastKnownPresenting && !presenting;
    if (newState != _lastKnownState ||
        newTex != _lastKnownTextureId ||
        newCount != _lastKnownPresentCount ||
        presenting != _lastKnownPresenting) {
      if (newState != _lastKnownState || newTex != _lastKnownTextureId) {
        _failedGpuRequest = null;
      }
      _lastKnownState = newState;
      _lastKnownTextureId = newTex;
      _lastKnownPresentCount = newCount;
      _lastKnownPresenting = presenting;
      setState(() {});
      if (finishedPresenting) {
        // 等待旧节点上屏的最新页直接接棒，省去 build → 下一帧回调的等待。
        // 用微任务退出控制器通知栈，尺寸/页码仍由 _sync 再次核对。
        scheduleMicrotask(() {
          final size = _physicalSize;
          if (mounted && size != null) unawaited(_sync(size));
        });
      }
    }
  }

  /// 把目标推给 native；完成后的来源、页码和尺寸必须仍是当前请求。
  /// mimage 的旧帧有独立纹理和布局；这里的共享纹理会被覆盖，不能作为旧帧占位。
  Future<void> _sync(Size physicalSize) async {
    if (!mounted || _physicalSize != physicalSize || _syncing) {
      return;
    }
    final PageSource source = widget.source;
    final int index = widget.index;
    final presenter = widget.presenter;
    final request = (presenter, source, index, physicalSize);
    bool isCurrent() =>
        mounted &&
        identical(widget.presenter, presenter) &&
        identical(widget.source, source) &&
        widget.index == index &&
        _physicalSize == physicalSize;

    if (_indexOutOfRange) {
      // 父层算错了下标。**不要去取页**：越界请求会返回一条与真实原因无关的
      // 失败文案（"字节损坏"之类），把调用方的 bug 伪装成数据问题。
      _switchTo(ImageSurfacePath.cpu);
      return;
    }

    if (widget.drivesPresentation &&
        presenter.canPresent &&
        presenter.mismatchFor(source) == null &&
        _failedGpuRequest != request) {
      // 另一节点的旧请求仍在飞。完成通知会重建当前节点并补推最新目标。
      if (presenter.isPresenting) return;
      _syncing = true;
      final bool ready;
      try {
        ready = await presenter.present(
          source: source,
          index: index,
          physicalSize: physicalSize,
        );
      } finally {
        _syncing = false;
      }
      if (!isCurrent()) {
        // 布局/页码已变化，直接补推最后的目标；过期结果不会挂回显示树。
        final latestSize = _physicalSize;
        if (mounted && latestSize != null) unawaited(_sync(latestSize));
        return;
      }
      if (ready) {
        _switchTo(ImageSurfacePath.gpu);
        unawaited(_reportGpuSize(source, index));
        if (!widget.holdOwnBitmap) {
          // 兜底那张位图没有理由继续留着（单页可达 179 MB）。
          // 顺带作废在飞的那次兜底解码：GPU 路马上会拿画面，它回来时该自弃。
          _loadToken++;
          _releaseCpuImage();
          return;
        }
        // 留着：这一页退场时（翻页滑动过半、共享纹理已经被新页覆写）它还要靠
        // 自己的位图把画面撑住。**不 await** —— 它在后台解，不在上屏关键路径上；
        // 而且解完之前画面已经由共享纹理负责，没有空窗。
        unawaited(_ensureCpuContent(source, index, physicalSize));
        return;
      }
      if (presenter.isPresenting) return;
      _failedGpuRequest = request;
    }

    _switchTo(ImageSurfacePath.cpu);
    await _ensureCpuContent(source, index, physicalSize);
  }

  /// 父层给的页码超出了这个来源的范围。
  bool get _indexOutOfRange =>
      widget.index < 0 || widget.index >= widget.source.pageCount;

  Future<void> _reportGpuSize(PageSource source, int index) async {
    if (widget.onIntrinsicSize == null ||
        _sizeRequest == (source, index) ||
        (_reportedSize?.$1 == source && _reportedSize?.$2 == index)) {
      return;
    }
    _sizeRequest = (source, index);
    try {
      final size = await widget.presenter.sourceSizeFor(source, index);
      if (size != null) _reportSize(source, index, size);
    } finally {
      if (_sizeRequest == (source, index)) _sizeRequest = null;
    }
  }

  void _reportSize(PageSource source, int index, Size size) {
    if (!mounted ||
        !identical(widget.source, source) ||
        widget.index != index ||
        size.width <= 0 ||
        size.height <= 0 ||
        _reportedSize == (source, index, size)) {
      return;
    }
    _reportedSize = (source, index, size);
    widget.onIntrinsicSize?.call(size);
  }

  // ───────────────────────── 兜底路 ─────────────────────────

  /// 把当前页解成一张位图。
  ///
  /// 解码宽度按控件的**物理**宽度乘 [ImageSurface.bitmapWidthScale] 给，
  /// 不给全尺寸：一页 44.8 MPix 解出 170.8 MB 位图、这一段要 1526 ms
  /// （其中解码只占 17%，其余全是过桥与 `decodeImageFromPixels`）；
  /// 给了宽度之后位图缩到几 MB，整段掉到 300–400 ms。降采样解码在这里**不是画质选项，
  /// 是可用性前提**。
  ///
  /// 系数是第二层，只对**邻页**生效：它那份位图要在"用户翻过去的那一瞬间"就已就位，
  /// 而 300–400 ms 比连翻的间隔还长。理由与推导见 [kNeighborBitmapWidthScale]。
  Future<void> _ensureCpuContent(
    PageSource source,
    int index,
    Size physicalSize,
  ) async {
    final int targetWidth = (physicalSize.width * widget.bitmapWidthScale)
        .round();
    if (targetWidth < 1) {
      return;
    }
    final bool alreadyLoaded =
        identical(_loadedSource, source) &&
        _loadedIndex == index &&
        _loadedWidth == targetWidth &&
        _cpuImage != null;
    if (alreadyLoaded) {
      return;
    }
    // 同一个目标已经在飞了就不重复发；目标不同则照发（见 [_loadingSource] 注释）。
    final bool inFlight =
        identical(_loadingSource, source) &&
        _loadingIndex == index &&
        _loadingWidth == targetWidth;
    if (inFlight) {
      return;
    }
    if (identical(_failedSource, source) && _failedIndex == index) {
      return;
    }

    _loadingSource = source;
    _loadingIndex = index;
    _loadingWidth = targetWidth;
    final int token = ++_loadToken;
    try {
      final PageLoadOutcome outcome = await source.load(
        index,
        targetWidth: targetWidth,
        // 谁来等这一页决定许可等级，不是随手给的：驱动上屏的那一个（当前页）
        // 是**用户在等**，别让它排在任何预取后面；邻页只是提前把位图备好，
        // 用 prefetch —— 调度器为此留了许可给交互那一档，见 `PageLoadIntent`。
        intent: widget.drivesPresentation
            ? PageLoadIntent.interactive
            : PageLoadIntent.prefetch,
      );
      if (!mounted || token != _loadToken) {
        return;
      }

      switch (outcome) {
        case PageLoadFailed(:final kind, :final message):
          if (kind == PageLoadFailureKind.cancelled) {
            // **「没轮到就作废了」不是这一页的属性**：它完全解得出来，只是那一刻
            // 没人要了。把它像真错误那样记进 [_failedSource]，会让这一页**永久**不再
            // 尝试（那个早退就在本方法开头），于是下次翻到它就是一片空白，而且
            // 再也回不来 —— 一个纯调度事件被当成了数据损坏。
            //
            // 也不能只是"什么都不记"：这类结果**不改任何状态**，所以不会再有
            // 下一次 `build` 来把请求发出去，这一页就停在空白上。所以自己安排重试；
            // 试完仍然不轮到，才给一句中性的说明 —— 说的是"这一次没轮到"，
            // 不是"这一页坏了"，更不把这一页钉死（下一次布局照发）。
            if (_cancelRetries < _maxCancelRetries) {
              _scheduleCancelRetry();
              return;
            }
            setState(() {
              _failureMessage = '这一页的加载已经过期';
            });
            return;
          }
          setState(() {
            _failedSource = source;
            _failedIndex = index;
            _failureMessage = message;
          });
          return;

        case PageLoaded(:final content):
          // 目前只有位图页。视频页加进来时这个 switch 会**编译不过**
          // （sealed 联合没有别的分支），那时必须在此决定怎么显示它，
          // 而不是把它当静态图画出来 —— 这正是把内容做成封闭联合要买的东西。
          final Future<ui.Image> decoding = switch (content) {
            RasterPageContent(:final rgba, :final width, :final height) =>
              _decodeRgba(rgba, width, height),
          };
          final ui.Image image = await decoding;
          if (!mounted || token != _loadToken) {
            image.dispose();
            return;
          }
          final ui.Image? stale = _cpuImage;
          // 这一页已经拿到像素了：作废重试的账本归零，别让一个已经安排好的
          // 重试在成功之后再发一次多余请求。
          _cancelRetries = 0;
          _cancelRetry?.cancel();
          _cancelRetry = null;
          setState(() {
            _cpuImage = image;
            _loadedSource = source;
            _loadedIndex = index;
            _loadedWidth = targetWidth;
            _failureMessage = null;
          });
          _reportSize(source, index, switch (content) {
            RasterPageContent(:final sourceWidth, :final sourceHeight) => Size(
              sourceWidth.toDouble(),
              sourceHeight.toDouble(),
            ),
          });
          // 先换再释放：反过来会让这一帧的绘制拿到一个已 dispose 的位图。
          if (stale != null && !identical(stale, image)) {
            stale.dispose();
          }
          return;
      }
    } catch (error) {
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _failedSource = source;
        _failedIndex = index;
        _failureMessage = '解码第 ${index + 1} 页失败: $error';
      });
    } finally {
      if (identical(_loadingSource, source) &&
          _loadingIndex == index &&
          _loadingWidth == targetWidth) {
        _loadingSource = null;
        _loadingIndex = null;
        _loadingWidth = null;
      }
    }
  }

  Future<ui.Image> _decodeRgba(Uint8List rgba, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// 释放兜底位图。
  ///
  /// **先摘引用、延后一帧再 dispose**：调用点可能正好在「已 setState、
  /// 但这一帧还没绘制」之间，立刻 dispose 会让正在走的那一帧拿到已释放的位图；
  /// 而先摘掉 [_cpuImage] 则保证它不可能被重新挂回界面。
  void _releaseCpuImage() {
    final ui.Image? doomed = _cpuImage;
    if (doomed == null) {
      return;
    }
    _cpuImage = null;
    _loadedSource = null;
    _loadedIndex = null;
    _loadedWidth = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => doomed.dispose());
  }

  void _switchTo(ImageSurfacePath path) {
    if (_path != path) {
      _path = path;
      if (mounted) {
        setState(() {});
      }
    }
    if (_reportedPath != path) {
      _reportedPath = path;
      widget.onPathChanged?.call(path);
    }
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size physicalSize = Size(
          constraints.maxWidth * devicePixelRatio,
          constraints.maxHeight * devicePixelRatio,
        );
        _physicalSize = physicalSize;
        if (physicalSize.width >= 1 && physicalSize.height >= 1) {
          // 不能在 build 里直接 await：下一帧再安排。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_sync(physicalSize));
          });
        }
        return _buildContent(constraints, physicalSize);
      },
    );
  }

  /// 画这一页。**按"这一份像素到底画的是不是本页"排序，而不是按路径排序**。
  ///
  /// 共享纹理只有一张，而且它归**当前页**用。所以对任何一个节点来说，
  /// "纹理里装着本页"都是一个**会变**的事实：翻页滑动过半时新页 `present`，
  /// 旧页节点手里那张纹理里立刻就是别人的画面了。这时候**不能照画**
  /// （画出来就是页码与画面对不上），只能退回它自己的位图。
  ///
  /// 优先级：
  /// 1. 纹理里确实是本页 → 画纹理（像素不过桥，画质最高）；
  /// 2. 否则有本页的位图 → 画位图。**这一条就是翻页时那两半都有画面的原因**：
  ///    进场那一半靠它（还不是当前页、拿不到纹理），退场那一半也靠它
  ///    （纹理已经被新页覆写）；
  /// 3. 都没有 → 该报错就报错，不该报错就留白（透出阅读底色）等下一帧。
  Widget _buildContent(BoxConstraints constraints, Size physicalSize) {
    final frame = widget.presenter.presentedFrame;
    if (frame != null &&
        frame.matches(widget.source, widget.index, physicalSize) &&
        _path == ImageSurfacePath.gpu) {
      // 纹理铺满整个盒子是**故意**的：页的等比缩放与留边在 Rust 侧的着色器里
      // 完成，所以这张纹理本来就已经是"屏幕上的那一幅"。
      // 这里再套一层 AspectRatio 或 BoxFit 只会引入第二次缩放。
      return _wrapSlice(
        SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Texture(textureId: frame.textureId),
        ),
        constraints,
      );
    }

    final ui.Image? image = _cpuImage;
    if (image == null) {
      if (!_indexOutOfRange &&
          _failureMessage == null &&
          widget.presenter.canPresent &&
          widget.presenter.mismatchFor(widget.source) == null) {
        return const SizedBox.expand();
      }
      return _hint(_cpuHint());
    }
    // 位图路没有着色器，留边只能交给 `BoxFit.contain` —— 用同一个语义
    // （等比缩放 + 留边），这样两条路切换时画面不会跳。
    return _wrapSlice(
      SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: RawImage(
          image: image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
      constraints,
    );
  }

  Widget _wrapSlice(Widget child, BoxConstraints constraints) {
    if (!widget.slice.isHalf) return child;
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    return ClipRect(
      child: SizedBox(
        width: w,
        height: h,
        child: OverflowBox(
          minWidth: w * 2,
          maxWidth: w * 2,
          minHeight: h,
          maxHeight: h,
          alignment: widget.slice == PageSlice.left
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }

  String _cpuHint() {
    if (_indexOutOfRange) {
      return '页码越界：要第 ${widget.index + 1} 页，但这份来源只有 '
          '${widget.source.pageCount} 页。';
    }
    final String? failure = _failureMessage;
    if (failure != null) {
      return failure;
    }
    if (!GpuPresentController.isPlatformSupported) {
      return '当前平台没有 GPU 上屏这条路。\n\n'
          'GPU 上屏目前支持 Windows (D3D12 共享纹理) 与 macOS (Metal / CVPixelBuffer 硬件零拷贝)；\n'
          'Linux / 移动端走各自的上屏路径（尚未实现）。';
    }
    final String? mismatch = widget.presenter.mismatchFor(widget.source);
    if (mismatch != null) {
      return mismatch;
    }
    return '正在解码第 ${widget.index + 1} 页…';
  }

  Widget _hint(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8B949E)),
        ),
      ),
    );
  }
}
