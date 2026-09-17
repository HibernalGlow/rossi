import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/reader/page_source.dart';

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
  GpuPresentController([this._bridge = const GpuPresentBridge()]);

  final GpuPresentBridge _bridge;

  /// 从 [start] 起算，用来量「这一处等了多久才就绪」。
  ///
  /// 它**不是** App 冷启动时间 —— 呈现器在 `flutter_window.cpp::OnCreate`
  /// 就开始建了，这里的起点只是「节点被挂上来的时刻」。
  final Stopwatch _since = Stopwatch();

  Timer? _statsTimer;
  bool _disposed = false;
  bool _syncing = false;

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
  Future<void> _awaitReady() async {
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
    if (_pushedPath == source.path &&
        _pushedIndex == index &&
        _pushedSize == physicalSize &&
        _mismatchSource == null) {
      return _textureId != null;
    }

    _syncing = true;
    // 从"决定干活"到"页真的交出去了"的整段，就是翻页的那一刻延迟。
    final Stopwatch roundTrip = Stopwatch()..start();
    bool pushed = false;
    try {
      final GpuPresentStatus status = await _bridge.tryInit(
        width: width,
        height: height,
      );
      if (_disposed) {
        return false;
      }
      if (status.state != GpuPresentState.ready) {
        // 未就绪就维持现状：兜底路径继续显示，等 `_awaitReady` 那边报信。
        _mutate(() {
          _state = status.state;
          _error = status.error;
        });
        return false;
      }

      _mutate(() {
        _textureId = status.textureId;
        _state = GpuPresentState.ready;
        _error = '';
        _readyAfterMs ??= _since.elapsedMilliseconds;
      });

      // ── 来源：两侧各开一份（像素不过桥的代价），所以页数必须对得上 ──
      if (_pushedPath != source.path) {
        final int nativeCount = await _bridge.open(source.path);
        if (_disposed) {
          return false;
        }
        if (nativeCount != source.pageCount) {
          // 前提（两侧跑同一份枚举代码）失效了。只记账不动手，见 [mismatchFor]。
          _mutate(() {
            _mismatchSource = source;
            _mismatchMessage = '两侧页数不一致：页面来源 ${source.pageCount} 页，'
                '呈现器 $nativeCount 页。已回落 CPU 兜底路径。';
            _pushedPath = null;
            _pushedIndex = null;
            _pushedSize = null;
          });
          return false;
        }
        _mutate(() {
          _mismatchSource = null;
          _mismatchMessage = null;
          _pushedPath = source.path;
          // 刚 open，native 侧还没有当前页，强制走一次呈现。
          _pushedIndex = null;
          _pushedSize = null;
        });
      }

      if (_pushedSize != physicalSize || _pushedIndex != index) {
        await _bridge.show(index);
        if (_disposed) {
          return false;
        }
        pushed = true;
        _mutate(() {
          _pushedIndex = index;
          _pushedSize = physicalSize;
        });
      }
      return _textureId != null;
    } catch (error) {
      if (!_disposed) {
        _mutate(() => _error = '呈现失败: $error');
      }
      return false;
    } finally {
      _syncing = false;
      roundTrip.stop();
      // 只有真的把页交出去了才记 —— 早退那些调用没有延迟可言。
      if (pushed) {
        _lastPresentMs = roundTrip.elapsedMilliseconds;
        _lastPresentIndex = index;
        _presentCount++;
      }
    }
  }

  /// 真的把页交出去过几次（单调递增）。
  ///
  /// [#lastPresentMs] / [#lastPresentIndex] 只说"上一次交出去的是什么"，**没说是不是
  /// 这一次** —— 页号会重复（连翻绕回第一页、反复点同一页），所以单靠"页号对得上"
  /// 会把上一轮的延迟算到这一轮头上。量具用这个计数判断"这一轮到底交了没有"。
  int get presentCount => _presentCount;

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
    _disposed = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    super.dispose();
  }
}
