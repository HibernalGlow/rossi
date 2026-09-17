import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
  });

  /// 已打开的页面来源。
  final PageSource source;

  /// 要显示第几页（0 基）。
  final int index;

  /// GPU 呈现器的就绪状态与呈现目标。由调用方创建并 [GpuPresentController.start]。
  final GpuPresentController presenter;

  /// 通路变化时的通知。界面用它显示「现在走的是哪条路」。
  final ValueChanged<ImageSurfacePath>? onPathChanged;

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

  @override
  void initState() {
    super.initState();
    widget.presenter.addListener(_onPresenterChanged);
  }

  @override
  void didUpdateWidget(ImageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter)) {
      oldWidget.presenter.removeListener(_onPresenterChanged);
      widget.presenter.addListener(_onPresenterChanged);
    }
    if (!identical(oldWidget.source, widget.source) || oldWidget.index != widget.index) {
      // 换来源或翻页：上一页的位图与失败记录都不再适用。
      // **必须立刻失效**，否则切页瞬间会拿旧序号的结果当新页画出来。
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
    // 就绪那一刻可能没有新的布局来驱动同步，所以这里补一次重建 + 同步。
    setState(() {});
    final Size? size = _physicalSize;
    if (size != null) {
      unawaited(_sync(size));
    }
  }

  /// 每帧布局后调一次：把「来源 / 页码 / 目标尺寸」推给 native 侧，
  /// 或者在还没就绪（或这一份来源不可用）时把兜底位图准备好。
  ///
  /// # 顺序：先推、后决定走哪条路
  ///
  /// 「纹理注册了没有」只有 [GpuPresentController.present] 能回答（`init` 是在
  /// 那里面调的）。所以不能先判「有没有纹理」再决定推不推 —— 那是个环，
  /// 结果是永远停在兜底路、native 侧一次都没被调过。
  /// 正确的顺序是：**就绪就推；推成功才切 GPU**。
  ///
  /// 于是一次 `_sync` 里可能出现三种结局，它们对界面的含义完全不同：
  /// - 推成功 → 走 GPU；
  /// - 推不成功但**纹理还在、来源也没问题** → 留在 GPU 不动。这多半是上一次推
  ///   还在飞（同一帧里 `build` 与 [GpuPresentController] 的通知都会调到这里）。
  ///   此时拆掉 GPU 路去解一张兜底位图，会在拖窗口时闪一下 —— 那正是要避免的；
  /// - 其余 → 走 CPU 兜底。
  Future<void> _sync(Size physicalSize) async {
    if (!mounted) {
      return;
    }
    _physicalSize = physicalSize;
    final PageSource source = widget.source;
    final int index = widget.index;

    if (_indexOutOfRange) {
      // 父层算错了下标。**不要去取页**：越界请求会返回一条与真实原因无关的
      // 失败文案（"字节损坏"之类），把调用方的 bug 伪装成数据问题。
      _switchTo(ImageSurfacePath.cpu);
      return;
    }

    if (widget.presenter.canPresent && widget.presenter.mismatchFor(source) == null) {
      final bool ready = await widget.presenter.present(
        source: source,
        index: index,
        physicalSize: physicalSize,
      );
      if (!mounted) {
        return;
      }
      if (ready) {
        _switchTo(ImageSurfacePath.gpu);
        // 兜底那张位图（单页可达 179 MB）没有理由继续留着。
        // 顺带作废在飞的那次兜底解码：GPU 路马上会拿画面，它回来时该自弃
        // （`_releaseCpuImage` 只管已经解出来的那张，管不到在飞的）。
        _loadToken++;
        _releaseCpuImage();
        return;
      }
      // 推不成功时**重新问一次**：`present` 自己也可能刚记下一个"两侧对不上"，
      // 那必须回落兜底 —— 拿一张可能属于另一份来源的纹理当画面，
      // 表现就是「页码和画面对不上」。
      if (widget.presenter.textureId != null &&
          widget.presenter.mismatchFor(source) == null) {
        _switchTo(ImageSurfacePath.gpu);
        return;
      }
    }

    _switchTo(ImageSurfacePath.cpu);
    await _ensureCpuContent(source, index, physicalSize);
  }

  /// 父层给的页码超出了这个来源的范围。
  bool get _indexOutOfRange =>
      widget.index < 0 || widget.index >= widget.source.pageCount;

  // ───────────────────────── 兜底路 ─────────────────────────

  /// 把当前页解成一张位图。
  ///
  /// 解码宽度按控件的**物理**宽度给，不给全尺寸：一页 44.8 MPix 解出 170.8 MB
  /// 位图、这一段要 1526 ms（其中解码只占 17%，其余全是过桥与 `decodeImageFromPixels`）；
  /// 给了宽度之后位图缩到几 MB，整段掉到 300–400 ms。降采样解码在这里**不是画质选项，
  /// 是可用性前提**。
  Future<void> _ensureCpuContent(PageSource source, int index, Size physicalSize) async {
    final int targetWidth = physicalSize.width.round();
    if (targetWidth < 1) {
      return;
    }

    final bool alreadyLoaded = identical(_loadedSource, source) &&
        _loadedIndex == index &&
        _loadedWidth == targetWidth &&
        _cpuImage != null;
    if (alreadyLoaded) {
      return;
    }
    // 同一个目标已经在飞了就不重复发；目标不同则照发（见 [_loadingSource] 注释）。
    final bool inFlight = identical(_loadingSource, source) &&
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
      final PageLoadOutcome outcome = await source.load(index, targetWidth: targetWidth);
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
        if (physicalSize.width >= 1 && physicalSize.height >= 1) {
          // 不能在 build 里直接 await：下一帧再安排。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_sync(physicalSize));
          });
        }
        return _buildContent(constraints);
      },
    );
  }

  Widget _buildContent(BoxConstraints constraints) {
    if (_path == ImageSurfacePath.gpu) {
      final int? textureId = widget.presenter.textureId;
      if (textureId == null) {
        return _hint('呈现目标还没建好…');
      }
      // 纹理铺满整个盒子是**故意**的：页的等比缩放与留边在 Rust 侧的着色器里
      // 完成，所以这张纹理本来就已经是"屏幕上的那一幅"。
      // 这里再套一层 AspectRatio 或 BoxFit 只会引入第二次缩放。
      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Texture(textureId: textureId),
      );
    }

    final ui.Image? image = _cpuImage;
    if (image == null) {
      return _hint(_cpuHint());
    }
    // CPU 路没有着色器，留边只能交给 `BoxFit.contain` —— 用同一个语义
    // （等比缩放 + 留边），这样两条路切换时画面不会跳。
    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
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
