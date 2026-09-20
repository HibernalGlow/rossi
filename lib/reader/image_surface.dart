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
///   它是**兜底**，存在的唯一理由是「呈现器还没就绪、或这一份来源在两侧对不上时，
///   别让人对着黑屏」。
enum ImageSurfacePath { gpu, cpu }

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
class ImageSurface extends StatefulWidget {
  const ImageSurface({
    super.key,
    required this.source,
    required this.index,
    required this.presenter,
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
      _releaseCpuImage();
    }
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChanged);
    _loadToken++;
    _cpuImage?.dispose();
    _cpuImage = null;
    super.dispose();
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

    if (presenter.canPresent &&
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
        // 兜底那张位图（单页可达 179 MB）没有理由继续留着。
        // 顺带作废在飞的那次兜底解码：GPU 路马上会拿画面，它回来时该自弃
        // （`_releaseCpuImage` 只管已经解出来的那张，管不到在飞的）。
        _loadToken++;
        _releaseCpuImage();
        unawaited(_reportGpuSize(source, index));
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
  /// 解码宽度按控件的**物理**宽度给，不给全尺寸：一页 44.8 MPix 解出 170.8 MB
  /// 位图、这一段要 1526 ms（其中解码只占 17%，其余全是过桥与 `decodeImageFromPixels`）；
  /// 给了宽度之后位图缩到几 MB，整段掉到 300–400 ms。降采样解码在这里**不是画质选项，
  /// 是可用性前提**。
  Future<void> _ensureCpuContent(
    PageSource source,
    int index,
    Size physicalSize,
  ) async {
    final int targetWidth = physicalSize.width.round();
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
      );
      if (!mounted || token != _loadToken) {
        return;
      }

      switch (outcome) {
        case PageLoadFailed(:final kind, :final message):
          setState(() {
            _failedSource = source;
            _failedIndex = index;
            // `cancelled` 不是错误：这一页完全可能解得出，只是没人要了。
            // 显示成「解不了」会让用户以为这本打不开，那是错的结论。
            _failureMessage = kind == PageLoadFailureKind.cancelled
                ? '这一页的加载已经过期'
                : message;
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

  Widget _buildContent(BoxConstraints constraints, Size physicalSize) {
    if (_path == ImageSurfacePath.gpu) {
      final frame = widget.presenter.presentedFrame;
      if (frame == null ||
          !frame.matches(widget.source, widget.index, physicalSize)) {
        return const SizedBox.expand();
      }
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
    // CPU 路没有着色器，留边只能交给 `BoxFit.contain` —— 用同一个语义
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
