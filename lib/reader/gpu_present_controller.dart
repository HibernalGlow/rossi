import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/main.dart' show logger;
import 'package:zephyr/reader/ambient_palette.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_policy_service.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/super_resolution_input.dart';
import 'package:zephyr/reader/super_resolution_queue.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
part 'parts/gpu_present_enhance_part.dart';
part 'parts/gpu_present_frame_part.dart';


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

  final GpuPresentBridge _bridge;

  int _enhancementEpoch = 0;
  bool _modelRefreshPending = false;
  bool _openingSource = false;

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
          final message =
              '两侧页数不一致：页面来源 ${source.pageCount} 页，'
              '呈现器 $nativeCount 页。已回落 CPU 兜底路径。';
          _mutate(() {
            _mismatchSource = source;
            _mismatchMessage = message;
            _pushedPath = null;
            _pushedIndex = null;
            _pushedSize = null;
            _pushedWidth = null;
            _pushedHeight = null;
            // 这一份来源用不了，它的记账也没有意义了。
            _resetPageStatus();
          });
          // 这条一旦成立，`_pushedIndex` 会一直是 null，于是每一页的超分产物都被判成
          // 「预取完成、翻页再复用」，注入永远不发生 —— 之前这里只记 UI 文案、
          // 不进超分日志，所以画面没换而日志看着一切正常。
          SuperResolutionLog.add('第 ${index + 1} 页：$message');
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
        // 换了来源，上一本那一页的配色不能留给这一本用：页号的含义都变了，
        // 而且新书首页的取色要等它自己那次 `present` 回来。
        // 不在这里清，换书后的头几帧会是上一本的背景色。
        ReaderAmbientStore.instance.clear();
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

      // 阅读背景的取色。放在**这一页真的交出去之后**，而且下面那次探针读取
      // 刻意不 await：它不该把 `present` 的往返时间拖长 —— 那个数正是翻页延迟。
      if (readSettingSnapshot.readerAmbientEnabled) {
        unawaited(_refreshAmbientPalette(index));
      }

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

  /// 取一次阅读背景的调色板并发布到 [ReaderAmbientStore]。
  ///
  /// # 为什么频率是「一次翻页一次」
  ///
  /// 探针（`stats`）是**唯一**能看到呈现器内部状态的入口，取它不是免费的
  /// （一次跨语言往返）。放在这里意味着它的频率跟着翻页走，而不是跟着帧走 ——
  /// 与超分那条流水线同一条纪律：**每次翻页一次，不是每帧一次**。
  ///
  /// # 关掉功能就完全不调它
  ///
  /// 采样本身在 Rust 侧已经随解码做掉了（成本与图片尺寸无关，也不在翻页关键路径上，
  /// 见 `ambient` 模块），但**这次跨语言往返是可以省的** ——
  /// 于是"关掉这个功能"省下的是一趟真实的往返，而不是"算了不用"。
  ///
  /// # 必须核对 `currentIndex`
  ///
  /// 探针里的颜色属于**呈现器当前那一页**，而我们期望的是刚 `show` 的**这一页**。
  /// 连翻时两者会错开一拍，直接用就会把上一页的配色配到这一页的画面上 ——
  /// 那个现象看起来不像竞态，像"取色不准"，事后极难查。
  ///
  /// 核对不过就**什么都不发布**：背景层继续用上一份并自己插值过去，
  /// 那比发一份错的要好。
  ///
  /// 返回的 `null`（Rust 侧报 `null` = 这一页没采到）也是**照发**的：
  /// "这一页没有自适应颜色"是一个真实结论，界面要按它退回静态底色，
  /// 而不是停在上一页的颜色上。
  Future<void> _refreshAmbientPalette(int index) async {
    if (_disposed || !GpuPresentBridge.isPlatformSupported) {
      return;
    }
    try {
      final GpuPresentStats stats = await _bridge.stats();
      if (_disposed || stats.probeInt('currentIndex') != index) {
        return;
      }
      ReaderAmbientStore.instance.publish(
        ReaderAmbientPalette.fromProbe(stats.probe['ambient']),
      );
    } catch (_) {
      // 取色失败不该影响阅读：它只是背景的观感。真正要紧的失败
      // 已经在 `state` / `error` / `mismatchFor` 里报了。
    }
  }

  /// 真的把页交出去过几次（单调递增）。
  ///
  /// [#lastPresentMs] / [#lastPresentIndex] 只说"上一次交出去的是什么"，**没说是不是
  /// 这一次** —— 页号会重复（连翻绕回第一页、反复点同一页），所以单靠"页号对得上"
  /// 会把上一轮的延迟算到这一轮头上。量具用这个计数判断"这一轮到底交了没有"。
  int get presentCount => _presentCount;

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
  /// 上一次记过的「超分前置条件不满足」原因，用来去重。
  ///
  /// 这类闸每次调度都会对好几页命中，全打会把日志刷满；可是一条都不打，
  /// 「超分图没换上屏」就成了无从判断的黑箱 —— 所以按原因去重，只在原因变化时记。
  String? _lastEnhancementBailReason;

  void _logEnhancementBail(int index, bool taskValid) {
    final reason =
        '任务有效=$taskValid；平台支持=${GpuPresentBridge.isPlatformSupported}；'
        '已推页=${_pushedIndex ?? "无"}；模型刷新中=$_modelRefreshPending；'
        '原图对比=$_originalPreview；开关=$_isUpscaleEnabled';
    if (reason == _lastEnhancementBailReason) return;
    _lastEnhancementBailReason = reason;
    SuperResolutionLog.add('第 ${index + 1} 页：超分前置条件不满足，跳过。$reason');
  }

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
      _logEnhancementBail(index, acceptsWork());
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
      final engineProfile = hasSuperResolutionEngineChoice
          ? await RealSrSettings.loadProfile()
          : null;
      final cacheKey =
          engineProfile?.cacheKey ?? await RealSrSettings.loadCacheKey();
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
      final isConditional = await RealSrSettings.loadConditionalEnabled();
      // 条件超分命中时按那条条件的分块走；没开条件才用全局那份。
      // 这条链路以前**两个都不传**，`upscale` 就用签名默认 0 跑了，
      // 于是设置页改分块大小对阅读器实时超分从来没有作用过。
      int? conditionTileSize;
      if (isConditional) {
        final trigger = prefetch
            ? SuperResolutionPolicyTrigger.preload
            : SuperResolutionPolicyTrigger.auto;
        final decision = await RealSrSuperResolution.decidePolicy(
          inputPath: inputPath,
          knownSize: inputSize,
          bookPath: source.path,
          trigger: trigger,
        );
        if (!decision.shouldRun) {
          _upscaleAttempts[index] = _maxUpscaleAttempts;
          _markPhase(index, SuperResolutionPagePhase.skipped);
          final desc = decision.conditionName != null
              ? '命中条件 [${decision.conditionName}]（${decision.reason}）'
              : '原因：${decision.reason}';
          SuperResolutionLog.add('第 ${index + 1} 页：条件超分判定跳过；$desc');
          return;
        }
        // `tileSize == null` 是策略侧「这条条件不分块」的表示，落到引擎就是 0。
        conditionTileSize = decision.tileSize;
      } else {
        if (!await RealSrSuperResolution.shouldUpscale(
          inputPath,
          knownSize: inputSize,
        )) {
          _upscaleAttempts[index] = _maxUpscaleAttempts;
          _markPhase(index, SuperResolutionPagePhase.skipped);
          SuperResolutionLog.add('第 ${index + 1} 页：达到设置的分辨率阈值或无法解析尺寸，跳过超分。');
          return;
        }
      }
      final tileSize = isConditional
          ? (conditionTileSize ?? 0)
          : await RealSrSettings.loadTileSize();
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
        engineProfile: engineProfile,
        tileSize: tileSize,
        knownInputSize: inputSize,
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
    // 离开阅读器：背景层不该继续挂着一份属于这本书的颜色。
    ReaderAmbientStore.instance.clear();
    _disposed = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    super.dispose();
  }
}
