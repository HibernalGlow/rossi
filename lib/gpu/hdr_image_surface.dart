import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;

import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/page_source.dart';

/// 真 HDR（EDR）画面节点。
///
/// # 为什么它不是 [ImageSurface] 的一个分支
///
/// 因为两者上屏的**物理通路不同**：
///
/// - [ImageSurface] 走 Flutter 外部纹理。macOS 引擎把这条通路的像素格式写死为
///   `MTLPixelFormatBGRA8Unorm`（引擎源码 `FlutterExternalTexture.mm`），8 位无符号
///   归一化的物理上限就是 1.0 —— 无论 Rust 侧算出多亮，都会被钳回 SDR 白点。
/// - 本节点走原生 `AppKitView` 平台视图，自带一个
///   `wantsExtendedDynamicRangeContent` 的扩展线性浮点图层，数值可以真正超过 1.0，
///   由 macOS 合成器交给显示器 EDR 头顶空间（本机外接屏实测 4.36x ≈ 436 nit）。
///
/// # 防黑是一条结构约束，不是几个 if
///
/// 这条通路上出现过两类「打开就是一片黑」，都不是渲染管线本身的问题：
///
/// 1. **空图层盖住了好画面**。平台视图从开始创建到真的能画之间有一段空白期，
///    而它一旦挂上去就是不透明的；接管之后若没有让控制器重推一帧，它更是永远空。
///    对策是结构性的：[ImageSurface]（已验证过的那条路，含 CPU 兜底）**永远在底层**，
///    EDR 图层只是盖在它上面。两种情况都退化成「看到底路的那一帧」，而不是一块黑。
/// 2. **创建失败后无人接手**。所以有 [creationTimeout]：超时就永久判定这条通路不可用，
///    整个节点回到底路，并且本次会话不再重试。
///
/// 还有一条硬要求：`hitTestBehavior` 必须是 `transparent`。默认的 `opaque` 会把画面
/// 区域的点击与滑动全部吃掉 —— 画面看着没问题，但翻页、呼出控制栏全失效。
class HdrImageSurface extends StatefulWidget {
  const HdrImageSurface({
    super.key,
    required this.source,
    required this.index,
    required this.presenter,
    this.onPathChanged,
  });

  final PageSource source;
  final int index;
  final GpuPresentController presenter;

  /// 底路的通路回调（转发给 [ImageSurface]）。
  final ValueChanged<ImageSurfacePath>? onPathChanged;

  /// 这条原生 EDR 通路在本机是否可用。
  static bool get isSupported =>
      !kIsWeb && Platform.isMacOS && GpuPresentBridge.isPlatformSupported;

  /// 与 `MainFlutterWindow` 里注册的工厂 id 一致。
  static const String viewType = 'rossi/hdr_surface';

  /// 平台视图创建超时。超过就判定这条通路不可用，永久回落地路。
  static const Duration creationTimeout = Duration(milliseconds: 2500);

  /// 这条通路在本进程里是否已被证明可用 / 不可用。
  static bool? edrVerified;
  static String edrFailureReason = '';

  static void _log(String message) {
    final String line =
        '${DateTime.now().millisecondsSinceEpoch} [dart] $message\n';
    try {
      File('/tmp/breeze_gpu.log')
          .writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // 写日志失败不该影响呈现。
    }
  }

  /// 自检报告：把这条通路上每一步的实际状态摊开。
  ///
  /// 存在的理由很具体：这条通路的失败模式都是「画面就是黑的，没别的线索」。
  /// 自检把「平台视图建没建、图层接没接管、输出是 4 字节还是 8 字节」一次问清。
  static Future<Map<String, dynamic>> selfCheck({
    required GpuPresentController presenter,
    String? path,
  }) async {
    const GpuPresentBridge bridge = GpuPresentBridge();
    final Map<String, dynamic> report = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'bridgeSupported': GpuPresentBridge.isPlatformSupported,
      'viewType': viewType,
      'hdrMode': LocalReadSession.instance.hdrMode,
      'hdrEnabled': LocalReadSession.instance.hdrEnabled,
      'presenterState': presenter.state.name,
      'canPresent': presenter.canPresent,
      'edrVerified': edrVerified,
      'edrFailureReason': edrFailureReason,
    };
    report['hdrStatus'] = await bridge.getHdrStatus();
    report['hdrDiagnostics'] = await bridge.getHdrDiagnostics();
    if (path != null && path.isNotEmpty) {
      try {
        final int pages = await bridge.open(path);
        report['openedPages'] = pages;
      } catch (error) {
        report['openError'] = '$error';
      }
    }
    _log('自检报告: $report');
    return report;
  }

  @override
  State<HdrImageSurface> createState() => _HdrImageSurfaceState();
}

class _HdrImageSurfaceState extends State<HdrImageSurface> {
  static const GpuPresentBridge _bridge = GpuPresentBridge();

  /// 平台视图创建后拿到的 id；`null` 表示原生图层还没就绪。
  int? _viewId;

  /// 这条通路已判定不可用（创建失败或超时）。判定之后本会话不再重试。
  bool _edrFailed = false;

  Timer? _creationTimer;

  /// 上一次推给 native 的 (来源, 页, 物理尺寸)。
  PageSource? _pushedSource;
  int? _pushedIndex;
  String? _pushedSize;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    LocalReadSession.instance.addListener(_onExternalChange);
    // 关键：也要听呈现器。`canPresent` 是从 loading 迁到 ready 的，
    // 不听它就会一直停在「还不可以」那一刻，HDR 永远不会真的上线。
    widget.presenter.addListener(_onExternalChange);
    _edrFailed = HdrImageSurface.edrVerified == false;
    _armCreationTimerIfNeeded();
  }

  @override
  void didUpdateWidget(HdrImageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter)) {
      oldWidget.presenter.removeListener(_onExternalChange);
      widget.presenter.addListener(_onExternalChange);
    }
    if (!identical(oldWidget.source, widget.source) || oldWidget.index != widget.index) {
      _pushedSource = null;
      _pushedIndex = null;
    }
    _armCreationTimerIfNeeded();
  }

  @override
  void dispose() {
    _creationTimer?.cancel();
    LocalReadSession.instance.removeListener(_onExternalChange);
    widget.presenter.removeListener(_onExternalChange);
    _detachIfNeeded();
    super.dispose();
  }

  /// 把图层交还给 native 侧。
  ///
  /// **不只该在 dispose 调**：只要本节点不再走 EDR 通路（HDR 被关、呈现器退回
  /// loading、自检判定失败……），就必须交还。否则 native 侧会继续把每一帧都渲染到
  /// 那个图层，而 Flutter 这边的 `Texture` 永远拿不到新帧 —— 表现是「画面停在很久
  /// 以前的那一帧」，而日志里只看到一条「进入 EDR 通路」，看不出谁在抢。
  void _detachIfNeeded() {
    if (_viewId == null) {
      return;
    }
    _viewId = null;
    unawaited(_bridge.attachHdrView(-1));
  }

  void _onExternalChange() {
    if (!mounted) {
      return;
    }
    if (!_hdrPathWanted) {
      _detachIfNeeded();
    }
    setState(() {});
    _armCreationTimerIfNeeded();
  }

  bool get _hdrPathWanted =>
      HdrImageSurface.isSupported &&
      !_edrFailed &&
      LocalReadSession.instance.hdrEnabled &&
      widget.presenter.canPresent;

  /// 只有在真的要走这条通路、却迟迟拿不到平台视图时才计时。
  ///
  /// 计时起点不能放在 `initState`：呈现器往往还没就绪，那段等待是正常的，
  /// 从那时算起会把「还没轮到这条路」误判成「这条路坏了」。
  void _armCreationTimerIfNeeded() {
    if (!_hdrPathWanted || _viewId != null || _edrFailed) {
      _creationTimer?.cancel();
      _creationTimer = null;
      return;
    }
    if (_creationTimer != null) {
      return;
    }
    HdrImageSurface._log(
      '平台视图开始等待（超时 ${HdrImageSurface.creationTimeout.inMilliseconds}ms）',
    );
    _creationTimer = Timer(HdrImageSurface.creationTimeout, () {
      if (!mounted) {
        return;
      }
      _failEdr(
        '平台视图在 ${HdrImageSurface.creationTimeout.inMilliseconds}ms 内未创建'
        '（工厂未注册 / 引擎未接管）',
      );
    });
  }

  void _failEdr(String reason) {
    if (_edrFailed) {
      return;
    }
    HdrImageSurface._log('EDR 通路失败，永久回落底路: $reason');
    HdrImageSurface.edrVerified = false;
    HdrImageSurface.edrFailureReason = reason;
    _edrFailed = true;
    _creationTimer?.cancel();
    _creationTimer = null;
    _detachIfNeeded();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onViewCreated(int viewId) async {
    HdrImageSurface._log('平台视图已创建 id=$viewId，准备接管');
    _creationTimer?.cancel();
    _creationTimer = null;
    final bool attached = await _bridge.attachHdrView(viewId);
    if (!mounted) {
      return;
    }
    if (!attached) {
      _failEdr('attachHdrView 返回 false');
      return;
    }
    HdrImageSurface.edrVerified = true;
    HdrImageSurface._log('EDR 图层接管成功 id=$viewId');
    // 接管之后**必须让控制器重推一次**。`present()` 是幂等的（来源/页码/尺寸都没变
    // 就早退），而「上屏端换了一个图层」对它不可见 —— 不重推，新图层就一直是空的。
    widget.presenter.invalidate();
    _pushedSource = null;
    _pushedIndex = null;
    setState(() => _viewId = viewId);
  }

  /// 把「来源 / 页码 / 物理尺寸」推给 native 侧。
  ///
  /// 物理尺寸而不是逻辑尺寸：底部是按物理像素分配缓冲区的，给逻辑尺寸会让
  /// Rust 侧按错误的视口算 Letterbox，画面会偏。
  ///
  /// 注意底路 [ImageSurface] 自己也会推（它是幂等的），这里是给「接管之后必须
  /// 立刻重推一次」用的那一次补充。两边各推一次不会打架。
  Future<void> _sync(Size physicalSize) async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      final int width = physicalSize.width.round();
      final int height = physicalSize.height.round();
      if (width < 1 || height < 1) {
        return;
      }
      final PageSource source = widget.source;
      final int index = widget.index;
      if (index < 0 || index >= source.pageCount) {
        return;
      }
      if (source.rasterTargetFor(index) == null) {
        return;
      }
      final String sizeKey = '${width}x$height';
      if (identical(_pushedSource, source) &&
          _pushedIndex == index &&
          _pushedSize == sizeKey) {
        return;
      }
      if (!widget.presenter.canPresent) {
        return;
      }
      final bool ok = await widget.presenter.present(
        source: source,
        index: index,
        physicalSize: physicalSize,
      );
      if (!mounted) {
        return;
      }
      if (ok) {
        _pushedSource = source;
        _pushedIndex = index;
        _pushedSize = sizeKey;
        HdrImageSurface._log('已推送 page=$index 物理尺寸=$sizeKey');
      }
    } catch (error) {
      HdrImageSurface._log('_sync 抛异常: $error');
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 底下永远是底路：它是被验证过的那条通路（含 CPU 兜底）。
    // EDR 图层只在真的就绪之后才盖上去 —— 见类注释里的「防黑是结构约束」。
    final Widget base = ImageSurface(
      source: widget.source,
      index: widget.index,
      presenter: widget.presenter,
      onPathChanged: widget.onPathChanged,
    );

    if (!_hdrPathWanted) {
      return base;
    }

    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size physicalSize = Size(
          constraints.maxWidth * devicePixelRatio,
          constraints.maxHeight * devicePixelRatio,
        );
        if (physicalSize.width >= 1 && physicalSize.height >= 1 && _viewId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_sync(physicalSize));
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            base,
            // 铺满整个盒子是故意的：等比缩放与留边在 Rust 侧着色器里完成，
            // 原生图层拿到的本来就是「屏幕上的那一幅」，这里再缩放就是第二次缩放。
            AppKitView(
              viewType: HdrImageSurface.viewType,
              // 必须 transparent：默认的 opaque 会吃掉整个画面区域的点击与滑动，
              // 后果是翻页、呼出顶/底控制栏全失效 —— 画面看着没问题，
              // 但阅读器变成一张图。transparent 让事件穿透到 Flutter 那边。
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              onPlatformViewCreated: (int id) => unawaited(_onViewCreated(id)),
            ),
          ],
        );
      },
    );
  }
}
