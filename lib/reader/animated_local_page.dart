import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zephyr/reader/page_animation.dart';
import 'package:zephyr/reader/page_source.dart';

/// 本地页里「会动的那一类」的显示节点：会动就交给引擎的解码器，不会动原样交回 [child]。
///
/// # 为什么动图要走另一条路
///
/// 本地静图那条路是「Rust 解成一帧 RGBA → 过桥 → 上屏」，而 `image` crate 的
/// `load_from_memory` **只出第一帧**。于是动图走到那条路上不会报错，只会安静地
/// 变成一张不会动的图 —— 这正是这次要修的症状。
///
/// 引擎（Skia）的解码器出多帧，而 `Image` 配 `FileImage` / `MemoryImage` 会自己起
/// `MultiFrameImageStreamCompleter` 来播：帧时长、循环次数、GIF / WebP 的 disposal
/// 合成全在它那边，本节点一行都不碰。这也比 mImageViewer 的做法省 —— 它用
/// `image` crate **一次性展开全部帧**（`fs_animation.rs`），于是要自己钳帧长、
/// 要 clamp 纹理尺寸，而循环次数它压根没读（永远无限循环）。
///
/// # 代价，说清楚
///
/// 动图页**不进** GPU 呈现器、**不进**超分、**不做**横长页分割：三者都建立在
/// 「一页 = 一张位图」上。这与 mImageViewer 的口径一致（它把动画标成
/// playback-only，绕过 edit / final / 校正缓存）。
/// 另外 `targetWidth` 对动图**不生效**（实测见 `docs/animated-image.md`）：
/// 动图按原始尺寸逐帧解，超大动图会比静图那条路吃内存。
///
/// # 为什么它是装饰器，不是页表里的一个分支
///
/// 「会不会动」要么等文件头（异步），要么等 GPU 解出第一帧。做成装饰器之后，
/// 未判定与判定为静图期间 `child`（`ImageSurface`）照常上屏，判定完成才换 ——
/// 没有黑屏空窗，也不会在页表里塞进一个渲染层的决定。
class AnimatedLocalPage extends StatefulWidget {
  const AnimatedLocalPage({
    super.key,
    required this.source,
    required this.index,
    required this.child,
    this.isColumn = false,
    this.imageAlignment = Alignment.center,
    this.paintSize,
    this.onIntrinsicSize,
  });

  /// 已打开的本地来源：取直接路径或整条字节都靠它。
  final PageSource source;

  /// 页下标，与 [PageSource.pages] 同源。
  final int index;

  /// 静图那条路原本要画的 widget（`ImageSurface` 或占位）。
  final Widget child;

  final bool isColumn;
  final Alignment imageAlignment;

  /// 顶栏缩放/旋转面板算好的「这一页画多大」，语义与 `ImageDisplay` 的同名参数一致。
  final Size? paintSize;

  /// 原始像素尺寸。动图页报的是**画布**尺寸，与静图那条路报 `sourceWidth` 同义。
  final ValueChanged<Size>? onIntrinsicSize;

  @override
  State<AnimatedLocalPage> createState() => _AnimatedLocalPageState();
}

class _AnimatedLocalPageState extends State<AnimatedLocalPage> {
  /// 已经定案是静图（或取不到字节）：不再探第二遍 —— 每次 build 都重探就是每帧一次文件读。
  bool _settledStatic = false;

  /// 动图 provider。同一个实例复用到 `Image` 与尺寸监听 ——
  /// `MemoryImage` 的缓存键是**那段字节的对象标识**，换实例等于换键，
  /// 于是每次重建都会重解一遍并在 ImageCache 里多堆一条。
  ImageProvider<Object>? _provider;

  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;
  bool _sizeReported = false;

  /// 在飞那一次判定的序号。换页 / 换来源时递增，回来时对不上就丢掉。
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(AnimatedLocalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.index != widget.index) {
      _token++;
      _settledStatic = false;
      _sizeReported = false;
      _provider = null;
      _stopListeningSize();
      unawaited(_resolve());
    }
  }

  @override
  void dispose() {
    _token++;
    _stopListeningSize();
    super.dispose();
  }

  /// 这一页的名字。越界时返回空串，交给 `child` 去报它那份越界提示。
  String get _pageName {
    final pages = widget.source.pages;
    if (widget.index < 0 || widget.index >= pages.length) return '';
    return pages[widget.index].name;
  }

  Future<void> _resolve() async {
    final String name = _pageName;
    if (name.isEmpty || _settledStatic) return;
    final int token = ++_token;
    try {
      final bool animated = await localPageIsAnimated(
        name: name,
        directPath: () => widget.source.getPageFilePath(widget.index),
      );
      if (!mounted || token != _token) return;
      if (!animated) {
        setState(() => _settledStatic = true);
        return;
      }
      final provider = await _providerFor();
      if (!mounted || token != _token) return;
      if (provider == null) {
        // 字节取不到（归档条目读失败）。留给 `child` 报它自己的错：
        // 同一个失败显示两遍只会让人以为有两个问题。
        setState(() => _settledStatic = true);
        return;
      }
      setState(() => _provider = provider);
      _listenForSize(provider);
    } catch (_) {
      if (!mounted || token != _token) return;
      // 判定本身失败（文件读不到之类）：留在静图那条路上，不新增错误文案。
      setState(() => _settledStatic = true);
    }
  }

  Future<ImageProvider<Object>?> _providerFor() async {
    final path = await widget.source.getPageFilePath(widget.index);
    if (path != null) return FileImage(File(path));
    // 归档内的条目没有直接路径：整条字节过桥一次，交给引擎解帧。
    final Uint8List? bytes = await widget.source.getPageBytes(widget.index);
    if (bytes == null || bytes.isEmpty) return null;
    return MemoryImage(bytes);
  }

  void _listenForSize(ImageProvider<Object> provider) {
    _stopListeningSize();
    final stream = provider.resolve(ImageConfiguration.empty);
    _sizeStream = stream;
    _sizeListener = ImageStreamListener((ImageInfo info, bool _) {
      // 动图每帧都会回调一次，而原始尺寸只要报一遍。
      if (!mounted || _sizeReported) return;
      _sizeReported = true;
      widget.onIntrinsicSize?.call(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
    });
    stream.addListener(_sizeListener!);
  }

  void _stopListeningSize() {
    final stream = _sizeStream;
    final listener = _sizeListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _sizeStream = null;
    _sizeListener = null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return widget.child;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size? paintSize = widget.paintSize;
        // 列模式（长条）里铺满宽度、行模式 contain + 留边 —— 与 `ImageDisplay`
        // 同一套语义，这样动图与静图之间切换时画面不跳。
        return Image(
          image: provider,
          width: paintSize?.width ?? constraints.maxWidth,
          height: paintSize?.height,
          fit: paintSize != null
              ? BoxFit.fill
              : widget.isColumn
              ? BoxFit.fill
              : BoxFit.contain,
          alignment: widget.imageAlignment,
          gaplessPlayback: true,
          // 首帧之前继续画 `child`（静图那条路已经解好的那一帧），不闪黑。
          frameBuilder:
              (
                BuildContext context,
                Widget built,
                int? frame,
                bool wasSynchronouslyLoaded,
              ) {
                if (wasSynchronouslyLoaded || frame != null) return built;
                return widget.child;
              },
          // 动图这条路失败不该留下空白页：交回 `child`，它有自己的错误显示。
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  widget.child,
        );
      },
    );
  }
}
