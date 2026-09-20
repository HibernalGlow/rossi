import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/main.dart' show logger;
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/super_resolution_input.dart';
import 'package:zephyr/reader/super_resolution_queue.dart';
import 'package:zephyr/reader/super_resolution_status.dart';

/// 一次完成呈现的身份与画布尺寸；共享纹理 id 本身不能证明里面是哪一页。
@immutable
class GpuPresentedFrame {
  const GpuPresentedFrame({
    required this.source,
    required this.index,
    required this.physicalSize,
    required this.textureId,
  });

  final PageSource source;
  final int index;
  final Size physicalSize;
  final int textureId;

  bool matches(PageSource source, int index, Size physicalSize) =>
      identical(this.source, source) &&
      this.index == index &&
      this.physicalSize.width.round() == physicalSize.width.round() &&
      this.physicalSize.height.round() == physicalSize.height.round();
}

/// GPU 呈现器的就绪状态与呈现目标 —— 从界面里搬出来的一份小状态机。
///
/// # 它管什么
///
/// 1. 后台创建进度（创建是异步的，见 `docs/texture-bridge-integration.md` §3.5）；
/// 2. 呈现目标的生命周期：按**物理**尺寸同步；尺寸变了让 native 侧重画当前页；
/// 3. 让 native 侧打开**与页面同一份**来源，并交叉校验页数。
///
/// # 它不管什么
///
/// 不管当前是第几页、也不管来源是什么 —— 那是 Reader 与 [PageSource] 的事。
/// 它只是在**镜像 native 侧的状态**（「那边现在打开的是哪一份、呈现的是哪一页、
/// 目标多大」），因为那三样恰好都是它自己推过去的东西。
/// 于是 [present] 是幂等的。
///
/// 这条界线就是「换显示节点」能成立的原因：节点只问「现在能不能给我一张纹理」，
/// 不关心书目与页序，因此阅读器接进来时不需要重写它。
///
/// # 两条容易写错的纪律（都踩过）
///
/// - **只在实际变化时通知**。`ImageSurface` 收到通知会重建、并在下一帧再次调
///   [present]，而 [present] 每次都会走到「写 textureId / state」那一步。
///   无条件通知会让两边互相触发，结果就是每帧重建。
/// - **[present] 必须先判「已经同步」再动手**。否则每帧都会过一次
///   MethodChannel（`tryInit`），白白吃掉一次跨语言往返。
class GpuPresentController extends ChangeNotifier {
  /// [bridge] 是位置可选参数而不是命名参数：字段私有，而命名参数不能以下划线开头。
  /// 正常调用点不传它（用默认实现），只有测试需要替换。
  GpuPresentController([this._bridge = const GpuPresentBridge()]) {
    RealSrSettings.modelChanges.addListener(_onModelChanged);
    RealSrSettings.prefetchChanges.addListener(_onPrefetchChanged);
    unawaited(_initUpscaleSetting());
  }

  Future<void> _initUpscaleSetting() async {
    try {
      final bool auto = await RealSrSettings.loadAutoUpscale();
      if (!_disposed && auto) {
        setUpscaleEnabled(true);
      }
    } catch (_) {}
  }

  final GpuPresentBridge _bridge;

  int _enhancementEpoch = 0;
  bool _modelRefreshPending = false;
  bool _openingSource = false;

  void _onModelChanged() {
    if (_disposed) return;
    SuperResolutionLog.add('模型配置变化：清除旧增强轨，重新处理当前页。');
    _enhancementQueue.clear();
    _enhancementEpoch++;
    _modelRefreshPending = true;
    _upscaleAttempts.clear();
    // 换了模型，旧产物不再代表「这一页的超分图」：阶段回到未落定、尺寸重算
    // （原图尺寸与模型无关，连「量过」的痕迹一起留着）。
    _mutate(() {
      _pagePhases.clear();
      _pageEnhancedSizes.clear();
      _enhancedSizeProbed.clear();
      _pageStatusRevision++;
    });
    unawaited(_refreshModel());
  }

  Future<void> _refreshModel() async {
    if (_disposed || _syncing || !_modelRefreshPending) return;
    final source = _lastPushedSource;
    final index = _pushedIndex;
    final size = _pushedSize;
    if (source == null || index == null || size == null) return;
    await present(source: source, index: index, physicalSize: size);
  }

  bool _acceptsEnhancement(int epoch) =>
      !_disposed &&
      epoch == _enhancementEpoch &&
      !_modelRefreshPending &&
      !_openingSource &&
      _isUpscaleEnabled &&
      !_originalPreview;

  /// 从 [start] 起算，用来量「这一处等了多久才就绪」。
  ///
  /// 它**不是** App 冷启动时间 —— 呈现器在 `flutter_window.cpp::OnCreate`
  /// 就开始建了，这里的起点只是「节点被挂上来的时刻」。
  final Stopwatch _since = Stopwatch();

  Timer? _statsTimer;
  bool _disposed = false;
  bool _syncing = false;
  GpuPresentedFrame? _presentedFrame;

  /// 只在 show 完成后有效；重新打开/调整尺寸/翻页期间没有可复用的完成帧。
  GpuPresentedFrame? get presentedFrame => _presentedFrame;
  bool get isPresenting => _syncing;

  GpuPresentState _state = GpuPresentState.loading;
  String _error = '';
  int? _textureId;
  int? _readyAfterMs;
  GpuPresentStats? _stats;

  // ── native 侧状态的镜像 ──
  /// native 侧当前打开的来源路径（我们推过去的那一个）。
  String? _pushedPath;

  /// native 侧当前呈现的页下标。
  int? _pushedIndex;

  /// 已推过去的呈现目标尺寸。
  Size? _pushedSize;
  int? _pushedWidth;
  int? _pushedHeight;

  /// init 成功时的画布尺寸。与最后成功 show 的尺寸分开，失败重试时不能混用。
  (int, int)? _initializedSize;

  /// 页数对不上的是**哪一个来源**（按实例身份，不按路径）。
  ///
  /// 按实例而不是按路径，是因为两种记账各有各的坏处：
  /// 记一个 bool → 一个坏来源把 GPU 路永久钉死，换了书也回不来；
  /// 记路径 → 「关掉再打开同一个文件」也永远回不来（路径没变）。
  /// 记实例则两种情形都对：同一个实例不重试（否则每帧重开一次文件），
  /// 重新打开得到新实例 → 自动获得重试机会。
  PageSource? _mismatchSource;
  String? _mismatchMessage;

  /// 最近一次**真把一页交出去**的 [present] 往返耗时（毫秒）。
  ///
  /// 「往返」= 从进入 `present` 到它返回，**含**跨语言调用与 native 侧的全部工作
  /// （解码 → 上传 → 渲染 → `CopyResource` → 通知引擎）。翻页量具拿它当
  /// "这一页等了多久" —— 从 Dart 侧再往下（引擎何时合成这一帧）就观测不到了。
  ///
  /// **幂等早退与"没就绪"不更新它**：那些调用没有把页交出去，拿它们的耗时当延迟
  /// 会把数读小。所以这个字段只在 `show` 真的被调过之后才写。
  ///
  /// 它**不进 `_mutate` 的快照**：每个翻页都会变，进快照就会变成"每次翻页多一次
  /// 重建"，而重建又会走回 `_sync`。量具直接读它，不需要经监听。
  int? _lastPresentMs;

  /// [_lastPresentMs] 对应的页下标。
  int? _lastPresentIndex;

  /// 真的把页交出去过几次（单调递增）。理由见 [presentCount]。
  int _presentCount = 0;

  /// 呈现器自身的状态。
  GpuPresentState get state => _state;

  /// 失败原因（[GpuPresentState.failed] 时非空）。
  String get error => _error;

  /// 已注册的外部纹理 id。只有就绪时有意义。
  int? get textureId => _textureId;

  /// 从 [start] 到就绪过了多久。`null` = 还没就绪。
  int? get readyAfterMs => _readyAfterMs;

  /// 从 [start] 起已经过了多久（还没就绪时界面用它显示「等了多久」）。
  int get elapsedMs => _since.elapsedMilliseconds;

  /// native 侧的诊断快照（界面用）。
  GpuPresentStats? get stats => _stats;

  /// 最近一次真把一页交出去的 [present] 往返耗时（毫秒）。`null` = 还没交出去过。
  int? get lastPresentMs => _lastPresentMs;

  /// [lastPresentMs] 对应的页下标。
  int? get lastPresentIndex => _lastPresentIndex;

  /// 呈现器就绪 —— 这条路存在，有资格试着走。
  ///
  /// **只回答「就绪了没有」，不回答「纹理注册了没有」**。后者要等第一次
  /// [present] 去 `init` 才会有，而 [present] 又要调用方先问过 [canPresent] ——
  /// 把两者合成一个 bool 就是一个死循环：调用方永远等不到 `textureId`，
  /// 于是永远停在兜底路上，native 侧连 `init` 都没被调过。
  /// 这个 bug 真出现过，症状是 `handleOpened` 恒为 0、目标尺寸恒为 `0x0`。
  /// 「纹理有没有」由 [present] 的**返回值**回答，见那里。
  ///
  /// **也不把「页数一致」算进来**：那是**每个来源**各自的性质，见 [mismatchFor]。
  /// 把它折进一个全局 bool，就会变成「换书之后仍然不能用」。
  bool get canPresent => _state == GpuPresentState.ready;

  /// 这个来源在两侧对不上时的说明；对得上（或没查过）返回 `null`。
  ///
  /// 两侧页数不一致时**不能猜哪边对**：纹理是有的、也画得出来，但画的可能是另一页，
  /// 而那种错误在阅读器里的表现是「页码和画面对不上」，事后极难查。
  /// 所以这里只记账，由显示节点回落 CPU 兜底 —— 兜底路走的是页面这一份，
  /// 至少页码与画面是自洽的。
  String? mismatchFor(PageSource source) =>
      identical(_mismatchSource, source) ? _mismatchMessage : null;

  /// 当前平台有没有这条路的实现。
  static bool get isPlatformSupported => GpuPresentBridge.isPlatformSupported;

  /// 起后台轮询与定时取统计。重复调用无副作用。
  void start() {
    if (_disposed || _statsTimer != null) {
      return;
    }
    _since.start();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refreshStats()),
    );
    unawaited(_awaitReady());
  }

  /// 盯住后台创建进度，就绪后置状态。
  ///
  /// 用轮询而不是让 native 侧回调：回调要从后台线程 post 到平台线程再 invoke，
  /// 而这里等的是**一次性**信号，~1 s 窗口里每 120 ms 问一次的代价可以忽略。
  /// 少一条跨线程路径就少一类「析构顺序」的 bug。
  ///
  /// # 它必须可以被重新武装（否则整本书都走兜底）
  ///
  /// 从前它只会被 `start()` 叫一次，而且一旦置了非 loading 状态就 `return`。
  /// 这与 [`present`] 里的降级撞在一起就是一个醒不来的死局：
  ///
  /// 1. macOS 的 `status` 是**硬编码 ready**（它只查 dylib 加载），所以第一轮
  ///    轮询就把状态置成 ready；
  /// 2. 而 Rust 侧的后台线程还在建呈现器（实测 ~150 ms），于是紧接着的第一次
  ///    `tryInit` 报 loading，把状态**降回 loading**；
  /// 3. 此时看门狗已经 `return` 了，**再无人把它升回去**。
  ///
  /// 后果很隐蔽：`canPresent` 永远是假 → `ImageSurface` 永远走 CPU 兜底 →
  /// 每页现场解 300–400 ms、而且**完全不碰 native 预取**。
  /// 现象就是「解码变慢了、没有预加载了、每页都要等」，但看代码怎么都看不出问题。
  bool _watchdogRunning = false;

  Future<void> _awaitReady() async {
    if (_watchdogRunning) {
      return;
    }
    _watchdogRunning = true;
    try {
      await _awaitReadyLoop();
    } finally {
      _watchdogRunning = false;
    }
  }

  Future<void> _awaitReadyLoop() async {
    if (!GpuPresentBridge.isPlatformSupported) {
      _mutate(() {
        _state = GpuPresentState.unsupported;
        _error = '当前平台未支持 GPU 共享纹理呈现';
      });
      return;
    }

    while (!_disposed && _state == GpuPresentState.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_disposed) {
        return;
      }

      final GpuPresentStatus status;
      try {
        status = await _bridge.status();
      } catch (error) {
        if (_disposed) {
          return;
        }
        _mutate(() {
          _state = GpuPresentState.failed;
          _error = '查询呈现器状态失败: $error';
        });
        return;
      }
      if (_disposed || status.state == GpuPresentState.loading) {
        continue;
      }

      _mutate(() {
        _state = status.state;
        _error = status.error;
        if (status.state == GpuPresentState.ready) {
          _readyAfterMs = _since.elapsedMilliseconds;
        }
      });
      return;
    }
  }

  /// 让 native 侧达到「来源 = [source]、页 = [index]、目标 = [physicalSize]」。
  ///
  /// # 返回值 = 「这一页现在能不能交给 GPU 路」
  ///
  /// `true` 表示呈现目标已建好、纹理已注册，调用方可以挂 `Texture` 了。
  /// `false` 的每一种情形（还没就绪 / 尺寸非法 / 下标越界 / 正在推上一次 /
  /// 这一份来源两侧对不上）对调用方的动作是**同一个**：这一帧继续走兜底，
  /// 下一帧再问。所以不必细分，但**绝不能**把它当「大概好了」猜 ——
  /// 猜错的后果是画的是另一页，这种错（页码与画面对不上）事后极难查。
  ///
  /// 只有 [present] 会去 `init`，也只有它会产生 `textureId`，所以调用方
  /// 不能拿 `textureId != null` 当入场条件（那会死循环，见 [canPresent]）。
  ///
  /// # 幂等
  ///
  /// 三样都已经是这个状态、且来源已校验过，就立刻返回（不做任何跨语言调用）。
  ///
  /// 尺寸必须是**物理**像素：Flutter 的纹理按物理像素合成。给逻辑尺寸会在
  /// 1.5x / 2x 缩放的屏幕上得到一张被拉伸的模糊图；更糟的是引擎随后会用
  /// **另一个**尺寸来问 `SurfaceCallback`，两边永远对不上，于是反复重建 ——
  /// 症状是拖窗口时画面闪烁。
  ///
  /// 尺寸变化时**必须重画当前页**：native 侧重建目标后内容就没了，
  /// 不补一次呈现，拖窗口时会看到一片底色。
  Future<bool> present({
    required PageSource source,
    required int index,
    required Size physicalSize,
  }) async {
    if (_disposed || _syncing || !GpuPresentBridge.isPlatformSupported) {
      return false;
    }
    final int width = physicalSize.width.round();
    final int height = physicalSize.height.round();
    if (width < 1 || height < 1) {
      return false;
    }
    // 越界不推：调用方可能正拿着上一份来源的下标，那是过期输入而非错误。
    if (source.rasterTargetFor(index) == null) {
      return false;
    }

    // ── 已经同步就什么都不做（不然每帧一次 MethodChannel 往返）──
    if (identical(_lastPushedSource, source) &&
        _pushedPath == source.path &&
        !_modelRefreshPending &&
        _pushedIndex == index &&
        _pushedWidth == width &&
        _pushedHeight == height &&
        _mismatchSource == null &&
        _presentedFrame != null) {
      return _textureId != null;
    }

    _mutate(() {
      _syncing = true;
      _presentedFrame = null;
    });
    // 从"决定干活"到"页真的交出去了"的整段，就是翻页的那一刻延迟。
    final Stopwatch roundTrip = Stopwatch()..start();
    bool pushed = false;
    try {
      if (_initializedSize != (width, height) ||
          _textureId == null ||
          !canPresent) {
        final GpuPresentStatus status = await _bridge.tryInit(
          width: width,
          height: height,
        );
        if (_disposed) return false;
        if (status.state != GpuPresentState.ready) {
          _initializedSize = null;
          // 未就绪就维持现状：兜底路径继续显示，等看门狗那边报信。
          //
          // 两处细节都不能少：
          // - **不把 ready 降回 loading**。`tryInit` 报 loading 往往是「刚建完呈现器、
          //   Rust 后台线程还没收工」的正常竞态（~150 ms）。降级会让 `canPresent` 立刻
          //   翻假，而 `canPresent` 正是「还会不会再调 [`present`]」的开关。
          // - **重新武装看门狗**。它是唯一能把状态升回去的东西，而它可能已经退出过。
          _mutate(() {
            if (_state != GpuPresentState.ready) {
              _state = status.state;
            }
            _error = status.error;
          });
          unawaited(_awaitReady());
          return false;
        }

        _initializedSize = (width, height);
        _mutate(() {
          _textureId = status.textureId;
          _state = GpuPresentState.ready;
          _error = '';
          _readyAfterMs ??= _since.elapsedMilliseconds;
        });
      }

      // ── 来源：两侧各开一份（像素不过桥的代价），所以页数必须对得上 ──
      if (!identical(_lastPushedSource, source) ||
          _pushedPath != source.path ||
          _modelRefreshPending) {
        // open 同一路径也会清空 native 增强轨。仅切书或换模型时执行，
        // 普通翻页继续使用预取缓存，不等待超分。
        _modelRefreshPending = false;
        _enhancementEpoch++;
        final int nativeCount;
        _openingSource = true;
        try {
          nativeCount = await _bridge.open(source.path);
        } finally {
          _openingSource = false;
        }
        if (_disposed) {
          return false;
        }
        if (nativeCount != source.pageCount) {
          // 前提（两侧跑同一份枚举代码）失效了。只记账不动手，见 [mismatchFor]。
          _mutate(() {
            _mismatchSource = source;
            _mismatchMessage =
                '两侧页数不一致：页面来源 ${source.pageCount} 页，'
                '呈现器 $nativeCount 页。已回落 CPU 兜底路径。';
            _pushedPath = null;
            _pushedIndex = null;
            _pushedSize = null;
            _pushedWidth = null;
            _pushedHeight = null;
            // 这一份来源用不了，它的记账也没有意义了。
            _resetPageStatus();
          });
          return false;
        }
        _mutate(() {
          _mismatchSource = null;
          _mismatchMessage = null;
          _pushedPath = source.path;
          // 换了来源，超分那边的记账全部作废：页号含义都变了。
          _upscaleAttempts.clear();
          _upscaleInProgress.clear();
          _resetPageStatus();
          // 刚 open，native 侧还没有当前页，强制走一次呈现。
          _pushedIndex = null;
          _pushedSize = null;
          _pushedWidth = null;
          _pushedHeight = null;
        });
      }

      // 未命中完成帧缓存就必须 show，包括只差 1 px 的尺寸变化和失败后的重试。
      await _bridge.show(index);
      if (_disposed) return false;
      pushed = true;
      roundTrip.stop();
      _mutate(() {
        _pushedIndex = index;
        _pushedSize = physicalSize;
        _pushedWidth = width;
        _pushedHeight = height;
        _lastPushedSource = source;
        _presentedFrame = GpuPresentedFrame(
          source: source,
          index: index,
          physicalSize: Size(width.toDouble(), height.toDouble()),
          textureId: _textureId!,
        );
        _lastPresentMs = roundTrip.elapsedMilliseconds;
        _lastPresentIndex = index;
        _presentCount++;
      });

      if (_isUpscaleEnabled) {
        unawaited(_scheduleEnhancements(source, index, width, height));
      }
      return _textureId != null;
    } catch (error) {
      // native 出错后重新确认目标，不能沿用可能已失效的 init 缓存。
      _initializedSize = null;
      if (!_disposed) {
        _mutate(() => _error = '呈现失败: $error');
      }
      return false;
    } finally {
      _mutate(() => _syncing = false);
      if (_modelRefreshPending && pushed) unawaited(_refreshModel());
    }
  }

  /// 真的把页交出去过几次（单调递增）。
  ///
  /// [#lastPresentMs] / [#lastPresentIndex] 只说"上一次交出去的是什么"，**没说是不是
  /// 这一次** —— 页号会重复（连翻绕回第一页、反复点同一页），所以单靠"页号对得上"
  /// 会把上一轮的延迟算到这一轮头上。量具用这个计数判断"这一轮到底交了没有"。
  int get presentCount => _presentCount;

  /// 超分替换和原图对比也会覆写共享纹理，必须与翻页/调整画布共用上屏锁。
  Future<bool> _redrawCurrentPage(int index) async {
    if (_disposed ||
        _syncing ||
        _pushedIndex != index ||
        _presentedFrame == null) {
      return false;
    }
    _mutate(() => _syncing = true);
    try {
      await _bridge.show(index);
      if (_disposed) return false;
      _mutate(() => _presentCount++);
      return true;
    } finally {
      _mutate(() => _syncing = false);
      if (_modelRefreshPending) unawaited(_refreshModel());
    }
  }

  /// 已呈现页的原始尺寸，用于布局；不依赖是否开启超分，也不重新解码图片。
  Future<Size?> sourceSizeFor(PageSource source, int index) async {
    if (_disposed || !identical(_lastPushedSource, source)) return null;
    final cached = _pageSourceSizes[index];
    if (cached != null) return cached;
    try {
      final stats = await _bridge.stats();
      if (_disposed || !identical(_lastPushedSource, source)) return null;
      // macOS 和 Windows 的页下标字段名称不同。
      final pageIndex = stats['currentIndex'] ?? stats['pageIndex'];
      final width = stats.probeInt('sourceWidth');
      final height = stats.probeInt('sourceHeight');
      if (pageIndex != index || width <= 0 || height <= 0) return null;
      final size = Size(width.toDouble(), height.toDouble());
      _markSourceSize(index, size);
      return size;
    } catch (_) {
      return null;
    }
  }

  /// 开关 native 侧的后台预取。
  ///
  /// 默认是开的（native 侧默认开）—— 它就是修翻页延迟的那件事：真页解码要
  /// 400–500 ms，而用户停在某一页的时间是秒级，**趁这段时间把下一页解好**是
  /// 唯一能把这个数打下来的办法（`docs/texture-bridge-integration.md` §6.3）。
  ///
  /// 留这个入口是为了 A/B（同一份二进制只差这一处）与将来的"离开阅读器就关掉"。
  /// 返回是否被接受；没被接受时**继续按原状态跑**，不抛异常。
  Future<bool> setPrefetchEnabled(bool enabled) async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return false;
    }
    try {
      return await _bridge.setPrefetchEnabled(enabled);
    } catch (_) {
      return false;
    }
  }

  /// 只预取某一页（**不上屏**）。
  ///
  /// 给阅读器的邻页 slot 用。它以前靠自己挂 `ImageSurface` 去 `show` 把下一页提前
  /// 解好，但那会抢走当前页唯一那张纹理（Ping-Pong 拔河 → 红黄闪），于是被改成
  /// 只显示占位；副作用是下一页退回「翻到它才开始解」，每页都要等 400–500 ms。
  /// 这个方法把「准备」与「上屏」拆开，两边都能到位。
  ///
  /// [source] 与 [present] 一样由调用方给（控制器不拥有页来源）。
  /// 失败不抛异常也不影响画面：它本来就不上屏。
  Future<bool> prepareNeighbor({
    required PageSource source,
    required int index,
    required Size physicalSize,
  }) async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return false;
    }
    // 两侧页数对不上时**不要**去预取：native 侧的页序与页面这一份可能不同，
    // 预取回来的可能是另一页 —— 那就白白把磁盘和 CPU 花在错的东西上。
    if (mismatchFor(source) != null) {
      return false;
    }
    final int width = physicalSize.width.round();
    final int height = physicalSize.height.round();
    if (index < 0 || index >= source.pageCount || width < 1 || height < 1) {
      return false;
    }
    // native 侧还没被 open 过就没什么可预取的（锚点/页数都还没建立）。
    if (_pushedPath != source.path) {
      return false;
    }
    try {
      return await _bridge.prepare(index: index, width: width, height: height);
    } catch (_) {
      return false;
    }
  }

  /// 是否处于原图对比旁路状态（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）。
  bool get isOriginalPreview => _originalPreview;
  bool _originalPreview = false;

  /// 设置原图对比旁路状态。
  Future<bool> setOriginalPreview(bool active) {
    return _enqueueOriginalPreview(active);
  }

  Future<bool> _enqueueOriginalPreview(
    bool active, {
    bool ensureEnhanced = true,
  }) {
    final Future<bool> operation = _previewQueue.then(
      (_) => _setOriginalPreview(active, ensureEnhanced: ensureEnhanced),
    );
    _previewQueue = operation.then<void>((_) {}).catchError((_) {});
    return operation;
  }

  Future<void> _previewQueue = Future<void>.value();

  Future<bool> _setOriginalPreview(
    bool active, {
    required bool ensureEnhanced,
  }) async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return false;
    }
    final bool ok = await _bridge.setOriginalPreview(active: active);
    SuperResolutionLog.add('原图对比=$active；呈现器接受=$ok');
    if (ok) {
      // 原图旁路只改变 native 侧的选轨标志，不会自动改写已经提交的纹理。
      // 当前页存在时立即重画一次，否则从原图切回超分后画面会一直停在旧帧，
      // 直到用户再次翻页才会看到正确的轨道。
      final int? index = _pushedIndex;
      final bool wasOriginal = _originalPreview;
      if (index != null && _textureId != null) {
        try {
          await _redrawCurrentPage(index);
          if (_disposed) return false;
        } catch (_) {
          // 旁路状态本身已经切换成功；下一次正常 present 会补画当前页。
        }
      }
      _mutate(() {
        _originalPreview = active;
      });

      // 原图对比期间不做增强；切回后用现有缓存或继续未完成的推理补当前页。
      if (wasOriginal &&
          !active &&
          ensureEnhanced &&
          _isUpscaleEnabled &&
          _lastPushedSource != null &&
          index != null) {
        unawaited(
          _scheduleEnhancements(
            _lastPushedSource!,
            index,
            _pushedWidth ?? 0,
            _pushedHeight ?? 0,
          ),
        );
      }
    }
    return ok;
  }

  /// 翻转原图对比旁路状态（按下/松开或一键对比）。
  Future<bool> toggleOriginalPreview() => setOriginalPreview(!_originalPreview);

  /// 当前是否已启用超分增强。
  bool get isUpscaleEnabled => _isUpscaleEnabled;
  bool _isUpscaleEnabled = false;

  /// 正在跑超分流水线的页（防同一页并发跑两遍）。
  final Set<(int, int)> _upscaleInProgress = <(int, int)>{};

  /// 每一页已经尝试过几次推理（失败也计，缓存复用不消耗次数）。上限见 [_maxUpscaleAttempts]。
  final Map<int, int> _upscaleAttempts = <int, int>{};

  /// 同一页最多重试几次推理。到顶就停下并说明，
  /// 而不是每翻一页刷一次日志、每次重新跑一遍几百毫秒的推理。
  static const int _maxUpscaleAttempts = 3;

  PageSource? _lastPushedSource;

  // ── 当前页超分状态的记账（顶栏那枚芯片要看的）──
  //
  // 三份表按**页下标**记账，因为「这一页走到哪一步了」是每一页各自的性质：
  // 预超分让邻页也有状态，翻过去时就不用从「待超分」重新爬一遍。
  //
  // 纪律：**只写真的走到的那一步**。不写「我调过 `upscale`」这种推断 ——
  // 推断出来的状态会在失败时撒谎，而这条流水线最要命的毛病就是虚报
  // （见 `_applyEnhancedToPresenter` 的注释）。

  /// 每一页的超分阶段。
  final Map<int, SuperResolutionPagePhase> _pagePhases =
      <int, SuperResolutionPagePhase>{};

  /// 每一页送进超分的原图尺寸（量出来才写；量不出就没有这一项）。
  final Map<int, Size> _pageSourceSizes = <int, Size>{};

  /// 每一页超分产物的尺寸。按页记账，换模型 / 换来源时整表作废。
  final Map<int, Size> _pageEnhancedSizes = <int, Size>{};

  /// 已经**量过**这些页（量出来可能是 `null`）。
  ///
  /// 与上面两张表分开记，是因为「没量到」也得记住：文件头读不出来时若不留痕，
  /// 每次翻到这一页都会再全量读一遍那个文件，日志里也会反复刷同一条警告。
  final Set<int> _sourceSizeProbed = <int>{};
  final Set<int> _enhancedSizeProbed = <int>{};

  /// 界面靠这个自增号知道「记账动过」。
  ///
  /// 上面三份都是 `Map`，直接放进 [_snapshot] 会按**实例**比较：原地改一格就通知不到
  /// （症状是芯片卡在旧状态），改成每次浅拷贝又是给将来的自己挖坑（漏拷一处就静默少通知）。
  /// 一个版本号把这两种坑一起绕过去。
  int _pageStatusRevision = 0;

  /// 写入一页的阶段。同值不写 —— 免得流水线里的重复打点变成一次界面重建。
  void _markPhase(int index, SuperResolutionPagePhase phase) {
    if (_pagePhases[index] == phase) return;
    _mutate(() {
      _pagePhases[index] = phase;
      _pageStatusRevision++;
    });
  }

  /// 记下一页的原图尺寸（量到了才记）。
  void _markSourceSize(int index, Size? size) {
    if (_sourceSizeProbed.contains(index) && size == null) return;
    _sourceSizeProbed.add(index);
    if (size == null || _pageSourceSizes[index] == size) return;
    _mutate(() {
      _pageSourceSizes[index] = size;
      _pageStatusRevision++;
    });
  }

  /// 量一次超分产物的尺寸并记账。**每页只量一次** —— 量的是图片头，
  /// 但 `ImmutableBuffer.fromFilePath` 会把整个文件读进来，重复量等于重复读盘。
  Future<void> _recordEnhancedSize(int index, String outPath) async {
    if (_enhancedSizeProbed.contains(index)) return;
    _enhancedSizeProbed.add(index);
    final Size? size = await RealSrSuperResolution.imageSizeOf(outPath);
    if (size == null) return;
    _mutate(() {
      _pageEnhancedSizes[index] = size;
      _pageStatusRevision++;
    });
  }

  /// **呈现器正在显示的那一页**的超分状态：状态 + 原图/超分后分辨率。
  ///
  /// 只读快照，界面可以直接在 `ListenableBuilder` 里取。取不到当前页（还没推过任何
  /// 一页）时下标为 `-1`，尺寸都是 `null` —— 不编数字。
  SuperResolutionPageStatus get currentPageUpscaleStatus =>
      upscaleStatusForPage(_pushedIndex ?? -1);

  /// 某一页的超分状态。
  ///
  /// 界面只用当前页；这个入口多出来是为了「**预超分**跑完的那一页」也能被问到 ——
  /// 邻页的状态在它被翻到之前，从当前页那个入口一个字都看不到。
  SuperResolutionPageStatus upscaleStatusForPage(int index) =>
      resolveSuperResolutionStatus(
        index: index,
        // 用**平台能力**而不是 `canPresent`：后者在后台建呈现器的 ~150 ms 里是假，
        // 那段时间报「不支持」是胡话。
        platformSupported: GpuPresentBridge.isPlatformSupported,
        upscaleEnabled: _isUpscaleEnabled,
        originalPreview: _originalPreview,
        recorded: _pagePhases[index],
        sourceSize: _pageSourceSizes[index],
        enhancedSize: _pageEnhancedSizes[index],
      );

  /// 记账整体作废：换了来源或换了模型时页号/缓存键的含义都变了。
  ///
  /// 必须在 `_mutate` 里调 —— 它要顺带把版本号推一格，界面才知道要重新读。
  void _resetPageStatus() {
    _pagePhases.clear();
    _pageSourceSizes.clear();
    _pageEnhancedSizes.clear();
    _sourceSizeProbed.clear();
    _enhancedSizeProbed.clear();
    _pageStatusRevision++;
  }

  /// 设置是否开启超分。
  Future<void> setUpscaleEnabled(bool enabled) {
    if (_isUpscaleEnabled == enabled) return Future<void>.value();
    SuperResolutionLog.add('超分开关=$enabled');
    // 保持旧调用点的同步状态语义：UI 不需要 await 才能马上反映开关。
    _mutate(() {
      _isUpscaleEnabled = enabled;
    });
    final Future<void> operation = _upscaleToggleQueue.then(
      (_) => _setUpscaleEnabled(enabled),
    );
    _upscaleToggleQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _upscaleToggleQueue = Future<void>.value();

  Future<void> _setUpscaleEnabled(bool enabled) async {
    // 必须等待旁路切换及当前页重绘完成，再启动超分注入。否则 native
    // 仍处于 bypass_enhanced=true 时，超分图虽已注入也会被原图帧覆盖。
    await _enqueueOriginalPreview(!enabled, ensureEnhanced: false);

    if (enabled &&
        _isUpscaleEnabled &&
        _pushedPath != null &&
        _pushedIndex != null &&
        _lastPushedSource != null) {
      await _scheduleEnhancements(
        _lastPushedSource!,
        _pushedIndex!,
        _pushedWidth ?? 0,
        _pushedHeight ?? 0,
      );
    }
  }

  /// 翻转超分启用状态。
  void toggleUpscale() => setUpscaleEnabled(!_isUpscaleEnabled);

  /// 注入异步超分完成的图像并预渲染进 Presenter 缓存。
  ///
  /// 返回 `true` **只表示呈现器收下了这份像素**，不表示画面上已经换了 ——
  /// 后者要等一次 `show` 之后再问呈现器（[_presenterUsesEnhanced]）才算数。
  Future<bool> setEnhancedImage(
    int index,
    String imagePath, {
    int? width,
    int? height,
  }) async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return false;
    }
    return _bridge.setEnhancedImage(
      index,
      imagePath,
      width: width,
      height: height,
    );
  }

  final _enhancementQueue = SuperResolutionQueue<(int, int)>();
  final Set<Future<void>> _enhancementSchedules = {};
  int _scheduleRevision = 0;
  Set<int> _enhancementTargets = {};

  /// 退出后可等待已开始的调度和推理收尾，避免清理缓存时仍有后台写入。
  Future<void> get enhancementsIdle async {
    while (_enhancementSchedules.isNotEmpty) {
      await Future.wait(_enhancementSchedules.toList());
    }
    await _enhancementQueue.idle;
  }

  void _onPrefetchChanged() {
    final source = _lastPushedSource;
    final index = _pushedIndex;
    if (source != null && index != null) {
      unawaited(
        _scheduleEnhancements(
          source,
          index,
          _pushedWidth ?? 0,
          _pushedHeight ?? 0,
        ),
      );
    }
  }

  Future<void> _scheduleEnhancements(
    PageSource source,
    int index,
    int width,
    int height,
  ) {
    final operation = _scheduleEnhancementsSafely(source, index, width, height);
    _enhancementSchedules.add(operation);
    return operation.whenComplete(
      () => _enhancementSchedules.remove(operation),
    );
  }

  Future<void> _scheduleEnhancementsSafely(
    PageSource source,
    int index,
    int width,
    int height,
  ) async {
    final revision = ++_scheduleRevision;
    final epoch = _enhancementEpoch;
    bool isCurrent() =>
        revision == _scheduleRevision &&
        _acceptsEnhancement(epoch) &&
        _pushedPath == source.path;
    try {
      // 翻页立刻清除待执行的旧预超分，配置读取不占用原图呈现路径。
      _enhancementQueue.clear();
      _enhancementTargets = {index};
      if (!_acceptsEnhancement(epoch)) return;
      final (forward, back) = await RealSrSettings.loadPrefetch();
      if (!isCurrent()) return;
      final targets = superResolutionTargets(
        index,
        source.pageCount,
        forward,
        back,
      );
      _enhancementTargets = targets.toSet();
      // 已落盘的当前页不排在正在执行的预超分后面：直接恢复增强轨。
      final cacheKey = await RealSrSettings.loadCacheKey();
      if (!isCurrent()) return;
      final cache = await _srCacheDir();
      if (!isCurrent()) return;
      final cached = await File(
        p.join(cache.path, 'sr_${source.path.hashCode}_${index}_$cacheKey.png'),
      ).exists();
      if (!isCurrent()) return;
      if (cached) await _ensureEnhancedForIndex(source, index, width, height);
      if (!isCurrent()) return;
      if (cached) targets.remove(index);
      // 「排队中」只打给**真的会被处理**的那些页（已落盘的当前页不在其中），
      // 且只打给还没落定的页：已经「无需超分 / 失败 / 已超分」的页不该被
      // 下一次调度按回「排队中」—— 那会让界面上刚说清楚的结论又变得含糊。
      for (final target in targets) {
        final SuperResolutionPagePhase? recorded = _pagePhases[target];
        if (recorded == null ||
            recorded == SuperResolutionPagePhase.queued ||
            recorded == SuperResolutionPagePhase.running) {
          _markPhase(target, SuperResolutionPagePhase.queued);
        }
      }
      _enhancementQueue.replace([
        for (final target in targets)
          (
            (epoch, target),
            () async {
              if (!_acceptsEnhancement(epoch) || _pushedPath != source.path) {
                return;
              }
              await _ensureEnhancedForIndex(source, target, width, height);
            },
          ),
      ]);
    } catch (error, stackTrace) {
      if (isCurrent()) {
        SuperResolutionLog.add(
          '第 ${index + 1} 页：预超分调度失败',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// 让「第 [index] 页显示成超分图」这件事成真 —— 该注入就注入、该推理就推理。
  ///
  /// # 顺序（每一条都必要）
  ///
  /// 1. **先问呈现器**："这一页现在用的是超分轨吗"。它自己回答（`probe.usedEnhanced`
  ///    + `currentIndex`），而不是由 Dart 侧记的账推断 —— 这一条就是修「超分完成了
  ///    却替换不上去」的关键：Dart 的账与呈现器的实际状态是**两份**，任何时候都可能
  ///    分叉（最典型的是呈现器按保留集把超分图淘汰了：翻到远处再翻回来时就发生）；
  /// 2. **已经有产物**（`rossi_sr_cache` 里那张 PNG）→ 只注入，不重跑推理；
  /// 3. **没有产物** → 跑推理，再注入。
  ///
  /// 只在**真的把一页推出去之后**调（`present` 里 `pushed == true` 那一段），
  /// 所以这里的跨语言往返是"每次翻页一次"，不是"每帧一次"。
  Future<void> _ensureEnhancedForIndex(
    PageSource source,
    int index,
    int targetW,
    int targetH,
  ) async {
    final epoch = _enhancementEpoch;
    bool acceptsWork() =>
        _acceptsEnhancement(epoch) && _enhancementTargets.contains(index);
    if (!acceptsWork() ||
        !GpuPresentBridge.isPlatformSupported ||
        _pushedPath != source.path) {
      return;
    }
    final job = (epoch, index);
    if (!_upscaleInProgress.add(job)) return;
    File? tempFile;
    File? pendingOutput;
    try {
      if (_pushedIndex == index) {
        final presenterUses = await _presenterUsesEnhanced(index);
        if (!acceptsWork()) return;
        if (presenterUses == true) {
          // 呈现器自己说这一帧来自超分轨 —— 这与 `_applyEnhancedToPresenter` 里那句
          // 「已超分」是**同一份证据**，只是这一次不用我们动手它就已经换上了
          // （最常见的情形：预超分时注入过，翻过来直接就是超分图）。
          // 不记这一笔，芯片就会停在上一步的「已生成」上，把已经发生的事说小。
          _markPhase(index, SuperResolutionPagePhase.applied);
          return;
        }
        // 判不了（呈现器没就绪 / 上一次呈现已经不是这一页）：不动记账，也不继续，
        // 等下一次呈现再说。
        if (presenterUses == null) return;
      }
      final appleProfile = (Platform.isMacOS || Platform.isIOS)
          ? await RealSrSettings.loadAppleProfile()
          : null;
      final cacheKey =
          appleProfile?.cacheKey ?? await RealSrSettings.loadCacheKey();
      if (!acceptsWork()) return;
      final srCacheDir = await _srCacheDir();
      if (!acceptsWork()) return;
      final outPath = p.join(
        srCacheDir.path,
        'sr_${source.path.hashCode}_${index}_$cacheKey.png',
      );
      if (await File(outPath).exists()) {
        if (!acceptsWork()) return;
        await _recordEnhancedSize(index, outPath);
        if (!acceptsWork()) return;
        logger.i('[Rossi AI] 第 $index 页复用模型 $cacheKey 的超分图: $outPath');
        // 产物在盘上 = 这一页有超分图可用了（至于这一帧用没用上，看下一步）。
        _markPhase(index, SuperResolutionPagePhase.ready);
        if (_pushedIndex != index) return;
        SuperResolutionLog.outputReady(outPath, page: index, model: cacheKey);
        await _applyEnhancedToPresenter(
          index,
          outPath,
          targetW,
          targetH,
          epoch,
        );
        return;
      }

      final attempts = _upscaleAttempts[index] ?? 0;
      if (attempts >= _maxUpscaleAttempts) {
        // 到顶就停下（不再重跑几百毫秒的推理）。这件事界面上必须说出来，
        // 否则用户看到的是「一直停在待超分」；但 `skipped`（无需超分）是另一条
        // 结论，别用「失败」把它盖掉。
        if (_pagePhases[index] != SuperResolutionPagePhase.skipped) {
          _markPhase(index, SuperResolutionPagePhase.failed);
        }
        return;
      }
      final prefetch = _pushedIndex != index;
      if (prefetch) {
        SuperResolutionLog.add('第 ${index + 1} 页：后台预超分开始；$cacheKey');
      }
      String? inputPath = await source.getPageFilePath(index);
      if (!acceptsWork()) return;
      if (inputPath == null ||
          !File(inputPath).existsSync() ||
          requiresSuperResolutionDecode(source, index)) {
        final extension = superResolutionInputExtension(source, index);
        SuperResolutionLog.add(
          '第 ${index + 1} 页：准备输入；来源=${source.path}\n'
          '原生解码=${requiresSuperResolutionDecode(source, index)}；输入格式=$extension',
        );
        tempFile = File(
          p.join(srCacheDir.path, 'temp_in_${const Uuid().v4()}$extension'),
        );
        await writeSuperResolutionInput(source, index, tempFile);
        inputPath = tempFile.path;
      }
      if (!acceptsWork()) return;
      // 量一次尺寸，两处用：判阈值（免得同一个文件被读第二遍）与顶栏上显示
      // 「超分后是多少」。量不出来（拿不到路径、格式认不得）就是没有数字，
      // 不编一个出来。
      final inputSize =
          _pageSourceSizes[index] ??
          await RealSrSuperResolution.imageSizeOf(inputPath);
      if (!acceptsWork()) return;
      _markSourceSize(index, inputSize);
      if (!await RealSrSuperResolution.shouldUpscale(
        inputPath,
        knownSize: inputSize,
      )) {
        _upscaleAttempts[index] = _maxUpscaleAttempts;
        _markPhase(index, SuperResolutionPagePhase.skipped);
        SuperResolutionLog.add('第 ${index + 1} 页：达到设置的分辨率阈值或无法解析尺寸，跳过超分。');
        return;
      }
      if (!acceptsWork()) return;
      // 旧任务不能覆盖切换模型后产生的缓存，先写独立文件再发布。
      pendingOutput = File(
        p.join(srCacheDir.path, 'pending_${const Uuid().v4()}.png'),
      );
      logger.i('[Rossi AI] 第 $index 页开始超分，模型=$cacheKey');
      SuperResolutionLog.add(
        '第 ${index + 1} 页：开始推理；模型=$cacheKey\n输入=$inputPath',
      );
      _upscaleAttempts[index] = attempts + 1;
      // 真开始推理了才说「超分中」—— `upscale` 之前还有好几道早退。
      _markPhase(index, SuperResolutionPagePhase.running);
      final produced = await RealSrSuperResolution.upscale(
        inputPath: inputPath,
        outputPath: pendingOutput.path,
        appleProfile: appleProfile,
        shouldRun: acceptsWork,
      );
      if (!_acceptsEnhancement(epoch)) {
        SuperResolutionLog.add('第 ${index + 1} 页：任务已过期或处于原图对比，忽略本次结果。');
        return;
      }
      if (!produced) {
        _markPhase(index, SuperResolutionPagePhase.failed);
        SuperResolutionLog.add('第 ${index + 1} 页：未产出超分图片，继续显示原图。');
        logger.w('[Rossi AI] 第 $index 页未生成超分图，保留原图');
        return;
      }
      await pendingOutput.rename(outPath);
      await _recordEnhancedSize(index, outPath);
      // 产物落盘 = 这一页有超分图了；接下来才谈「有没有换到画面上」。
      _markPhase(index, SuperResolutionPagePhase.ready);
      if (_pushedIndex != index) {
        SuperResolutionLog.outputReady(
          outPath,
          page: index,
          model: cacheKey,
          prefetched: true,
        );
        return;
      }
      SuperResolutionLog.outputReady(outPath, page: index, model: cacheKey);
      if (!_acceptsEnhancement(epoch)) return;
      await _applyEnhancedToPresenter(index, outPath, targetW, targetH, epoch);
    } catch (e, s) {
      _markPhase(index, SuperResolutionPagePhase.failed);
      SuperResolutionLog.add('第 ${index + 1} 页：超分失败', error: e, stackTrace: s);
      logger.w('[Rossi AI] 第 $index 页超分执行异常', error: e, stackTrace: s);
    } finally {
      _upscaleInProgress.remove(job);
      for (final file in [tempFile, pendingOutput]) {
        if (file != null) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  Directory? _srCacheDirCache;

  Future<Directory> _srCacheDir() async {
    final Directory? cached = _srCacheDirCache;
    if (cached != null && cached.existsSync()) {
      return cached;
    }
    final Directory cacheDir = await getTemporaryDirectory();
    final Directory srCacheDir = Directory(
      p.join(cacheDir.path, 'rossi_sr_cache'),
    );
    if (!srCacheDir.existsSync()) {
      await srCacheDir.create(recursive: true);
    }
    logger.i('[Rossi AI] 超分缓存目录: ${srCacheDir.path}');
    _srCacheDirCache = srCacheDir;
    return srCacheDir;
  }

  /// 把超分产物交给呈现器，并**按实际结果**汇报。
  ///
  /// # 为什么要拆成两段、为什么两段都要看返回值
  ///
  /// 用户眼里的「替换成功」= 画面上换成了超分图。而在代码里，从「超分跑完」到
  /// 「画面上真的换了」中间有两道闸，各自会失败，而且**后者不能由前者推出来**：
  ///
  /// 1. **注入**：[setEnhancedImage] 把像素放进呈现器的双轨缓存。可能失败
  ///    （呈现器未就绪、大图解码失败、这个平台没有这条实现……）；
  /// 2. **上屏**：`show` 之后那一帧**确实取自超分轨**。它同样可能失败 —— 最典型的
  ///    是注入之后该页的原图轨又被预取线程写回，把超分轨整条覆盖掉。
  ///
  /// 从前这两件事和「文件生成了」被写成一句「第 N 页超分成功 …… 已触发原子平滑
  /// 替换呈现」，第 2 段失败时日志照打：**日志说成功、画面还是原图**（虚报）。
  ///
  /// 现在的纪律：
  /// - 上屏后向呈现器要**证据**（`probe.usedEnhanced`），拿不到证据就既不声称成功
  ///   也不声称失败；
  /// - 证据说"这次用的还是原图轨"时**如实报失败**（下次呈现该页会重来一遍，
  ///   而那时盘上已有产物，重来的代价只是注入）。
  ///
  /// 返回是否真的在画面上替换了（`false` = 这次没换上，或已注入、等下一次呈现）。
  Future<bool> _applyEnhancedToPresenter(
    int index,
    String outPath,
    int targetW,
    int targetH,
    int epoch,
  ) async {
    if (!_acceptsEnhancement(epoch)) return false;
    SuperResolutionLog.add('第 ${index + 1} 页：向呈现器注入增强图\n$outPath');
    final bool injected = await setEnhancedImage(
      index,
      outPath,
      width: targetW > 0 ? targetW : null,
      height: targetH > 0 ? targetH : null,
    );
    if (!_acceptsEnhancement(epoch)) return false;
    if (!injected) {
      SuperResolutionLog.add('第 ${index + 1} 页：呈现器拒绝注入，替换失败。');
      logger.w('[Rossi AI] 第 $index 页超分图注入呈现器失败');
      return false;
    }
    if (_pushedIndex != index) {
      SuperResolutionLog.add(
        '第 ${index + 1} 页：已注入缓存，当前正在显示第 ${(_pushedIndex ?? -1) + 1} 页。',
      );
      return false;
    }

    // `show` 与 native 预取线程共用一条队列。注入完成后让队列先跑完当前
    // 帧，再核对像素来源；若恰好读到了前一帧的诊断，立即再重画一次。
    for (var pass = 0; pass < 3; pass++) {
      if (!_acceptsEnhancement(epoch) || _pushedIndex != index) return false;
      if (!await _redrawCurrentPage(index)) return false;
      if (!_acceptsEnhancement(epoch)) return false;
      if (pass > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final bool? confirmed = await _presenterUsesEnhanced(index);
      SuperResolutionLog.add(
        '第 ${index + 1} 页：第 ${pass + 1} 次上屏核对；'
        '使用增强图=$confirmed；原图对比=$_originalPreview；当前页=${(_pushedIndex ?? -1) + 1}',
      );
      if (!_acceptsEnhancement(epoch)) return false;
      if (confirmed == true) {
        // 呈现器自己说这一帧取自超分轨 —— 这句话是「已超分」唯一的依据。
        _markPhase(index, SuperResolutionPagePhase.applied);
        SuperResolutionLog.add('第 ${index + 1} 页：替换成功，呈现器确认当前画面来自超分图。');
        _upscaleAttempts.remove(index);
        logger.i('[Rossi AI] 第 $index 页超分图已替换上屏（呈现器确认本次呈现取自超分轨）');
        return true;
      }
      if (confirmed == null || _originalPreview || _pushedIndex != index) {
        logger.i('[Rossi AI] 第 $index 页注入后暂时无法核对显示来源: $confirmed');
        return false;
      }
      if (pass < 2) {
        logger.w('[Rossi AI] 第 $index 页注入后仍检测到原图轨，立即重画重试（${pass + 2}/3）');
      }
    }
    logger.w('[Rossi AI] 第 $index 页注入后仍显示原图，已保留缓存并等待下一次呈现重试');
    SuperResolutionLog.add('第 ${index + 1} 页：文件已生成，但呈现器仍显示原图，替换失败。');
    return false;
  }

  /// 问呈现器：「第 [index] 页现在用的是超分轨吗？」
  ///
  /// `null` = **判不了**（呈现器没就绪、或上一次呈现已经不是这一页了）。判不了时
  /// 既不报成功也不报失败 —— 把不确定说成其中之一，正是这次要修的那个 bug。
  ///
  /// 证据来自 Rust 侧 `MacPresenter::show_into_buffer` 的 `usedEnhanced`：它由
  /// **这一帧的像素从哪来**决定，而不是由"我们调用过 show"推断。所以它既能确认
  /// 「替换真的上屏了」，也能在**没换上去**时把这件事说出来 —— 而 Dart 侧自己
  /// 记的账做不到后者（它只知道自己调过注入）。
  Future<bool?> _presenterUsesEnhanced(int index) async {
    try {
      final GpuPresentStats stats = await _bridge.stats();
      final usedEnhanced = stats['usedEnhanced'];
      if (stats['currentIndex'] != index ||
          (usedEnhanced != 0 && usedEnhanced != 1)) {
        return null;
      }
      return usedEnhanced == 1;
    } catch (_) {
      return null;
    }
  }

  /// 取一份 native 侧诊断快照。
  Future<void> refreshStats() async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return;
    }
    try {
      final GpuPresentStats stats = await _bridge.stats();
      if (_disposed) {
        return;
      }
      _mutate(() => _stats = stats);
    } catch (_) {
      // 统计取不到不该影响画面：它是诊断，不是功能。
      // 真正要紧的失败已经在 `state` / `error` / `mismatchFor` 里报了。
    }
  }

  /// 通知状态里会被观察到的那些字段。**只拿它做比较**，不对外暴露。
  ///
  /// 用 record 而不是逐字段比较：record 是结构相等的，所以
  /// 「快照没变」= 一个 `!=` 就能判出来，不会因为漏了某个字段而变成静默的
  /// 少通知（症状是界面卡住不刷新）或多通知（症状是每帧重建）。
  Object get _snapshot => (
    _state,
    _error,
    _textureId,
    _readyAfterMs,
    _stats,
    _pushedPath,
    _pushedIndex,
    _pushedSize,
    _mismatchSource,
    _mismatchMessage,
    _originalPreview,
    _isUpscaleEnabled,
    _presentCount,
    _presentedFrame,
    _syncing,
    // 超分记账的版本号：三份 Map 原地改，靠它把「改过」带进快照里。
    _pageStatusRevision,
  );

  /// 改状态并在**真的变了**的时候通知。
  void _mutate(VoidCallback change) {
    if (_disposed) {
      return;
    }
    final Object before = _snapshot;
    change();
    if (before != _snapshot) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_onModelChanged);
    RealSrSettings.prefetchChanges.removeListener(_onPrefetchChanged);
    _enhancementQueue.dispose();
    _disposed = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    super.dispose();
  }
}
