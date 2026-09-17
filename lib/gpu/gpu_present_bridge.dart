import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// GPU 上屏路径的当前状态。
///
/// 分四个而不是两个，是因为调用方对它们的**动作不同**：
///
/// | 状态 | 调用方的动作 |
/// |---|---|
/// | [loading] | 走 CPU 兜底，并继续等 |
/// | [ready] | 挂 `Texture`，走 GPU 路径 |
/// | [failed] | 走 CPU 兜底，且**不再等** |
/// | [unsupported] | 连兜底都是终点（这条路径在本平台不存在） |
///
/// 把 [loading] 与 [failed] 合成一个"还没好"，调用方就只能在"一直等"和
/// "直接报错"之间二选一 —— 而这两件事恰好一个该等、一个该放弃。
enum GpuPresentState {
  /// 后台正在创建 wgpu device 与渲染管线（约 1 s）。
  loading,

  /// 可用。
  ready,

  /// 创建失败，或 native 侧整体不可用（DLL 缺失、缺符号……）。原因见 `error`。
  failed,

  /// 当前平台没有这条路径的实现。
  unsupported,
}

/// `init` / `status` 的返回。
///
/// 两个方法返回同一个类型：它们回答的是同一个问题（"这条路现在怎样"），
/// 只是 `init` 会顺带把呈现目标按给定尺寸准备好。
class GpuPresentStatus {
  const GpuPresentStatus({
    required this.state,
    this.textureId = -1,
    this.width = 0,
    this.height = 0,
    this.adapter = '',
    this.luidKnown = false,
    this.error = '',
  });

  final GpuPresentState state;

  /// 已注册的外部纹理 id。只有 [GpuPresentState.ready] 时有意义。
  final int textureId;

  /// 呈现目标的物理尺寸。
  final int width;
  final int height;

  /// Flutter 正在用的那块显卡。
  final String adapter;

  /// 有没有拿到 Flutter 的 adapter LUID。`false` 意味着 Rust 侧只能自己挑一块卡，
  /// 跨 adapter 共享可能失败或极慢 —— 这不是无关紧要的细节，所以要报出来。
  final bool luidKnown;

  /// 失败原因（[GpuPresentState.failed] 时非空）。
  final String error;

  bool get isReady => state == GpuPresentState.ready;

  factory GpuPresentStatus.fromMap(Map<Object?, Object?> map) {
    return GpuPresentStatus(
      state: parseGpuPresentState(map['state']),
      textureId: _asInt(map['textureId'], fallback: -1),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      adapter: '${map['adapter'] ?? ''}',
      luidKnown: map['luidKnown'] == true,
      error: '${map['error'] ?? ''}',
    );
  }

  @override
  String toString() => 'GpuPresentStatus(${state.name}, tex=$textureId, '
      '${width}x$height, adapter=$adapter, error=$error)';
}

/// 把 native 侧的状态字符串转成枚举。
///
/// 认不出的值一律当 [GpuPresentState.failed]：那说明两侧版本不一致，
/// **不能**当 [GpuPresentState.loading] —— 那会让调用方一直等一个永远不会到的信号。
GpuPresentState parseGpuPresentState(Object? raw) {
  switch ('$raw') {
    case 'ready':
      return GpuPresentState.ready;
    case 'loading':
      return GpuPresentState.loading;
    default:
      return GpuPresentState.failed;
  }
}

/// Rossi GPU 上屏桥（Windows / D3D12 共享纹理）。
///
/// # 它在整条链路里的位置
///
/// ```text
/// 归档 → [Rust] 解码 → [Rust] wgpu 渲染 → [Rust] GPU→GPU 拷贝 → 共享纹理
///                                              ↓ 只有句柄过桥
///                        [C++] 注册外部纹理 → [Dart] Texture(textureId)
/// ```
///
/// Dart 侧拿到的只有 **textureId**（一个 int）与统计数字。
/// 像素从不以 `Uint8List` 的形态到这一层 —— 这正是它相对
/// `ui.decodeImageFromPixels` 那条路径的意义：44.8 MPix 的一页是 179 MB，
/// 把它搬过语言边界再上传，实测要 1260 ms，而这一层是 0。
///
/// # 创建是异步的，所以调用方要处理 [GpuPresentState.loading]
///
/// native 侧的呈现器在**后台线程**上建（wgpu device + 管线约 1 s）。这个函数
/// 不阻塞，代价是调用方要面对"还没好"这个中间态：先走 CPU 兜底路径显示内容，
/// 轮询到 [GpuPresentState.ready] 之后再换成 `Texture(textureId)`。
///
/// 另有一条硬约束：**在 ready 之前不要构建 `Texture(textureId)`**。
/// 未就绪时引擎来要帧只会拿到空句柄，画面是黑的 —— 而兜底路径本来就是
/// 为了不让人看到那个黑屏。
///
/// # 平台边界
///
/// 只有 Windows 有 D3D12 共享纹理这条路。[isPlatformSupported] 是**能力探测**，
/// 不是"当前平台"的同义词：它同时还要求 native 侧真的把桥建起来了。
/// 调用方两个条件都要看 —— 于是 [tryInit] 会把平台不支持也表达成一个
/// 状态（[GpuPresentState.unsupported]），而不是抛异常。
class GpuPresentBridge {
  const GpuPresentBridge();

  /// 与 `windows/runner/gpu_present_bridge.cpp` 里的 channel 名一致。
  static const MethodChannel channel = MethodChannel('rossi/gpu_present');

  /// 这个平台有没有这条路径的**实现**（Windows / macOS 均支持 GPU 外部纹理硬件上屏）。
  static bool get isPlatformSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  /// 让 native 侧按 [width] / [height]（**物理像素**）确保呈现目标存在。
  ///
  /// 传物理像素而不是逻辑像素：Flutter 的纹理按物理像素合成。给逻辑尺寸的话，
  /// 在 1.5x / 2x 缩放的屏幕上会得到一张被放大渲染的模糊图 —— 而且更糟的是
  /// 引擎随后会用另一个尺寸来问 `SurfaceCallback`，两边永远对不上，形成反复重建。
  ///
  /// **未就绪不是异常**：那时返回 [GpuPresentState.loading]，调用方继续走兜底即可。
  Future<GpuPresentStatus> tryInit({required int width, required int height}) async {
    if (!isPlatformSupported) {
      return const GpuPresentStatus(
        state: GpuPresentState.unsupported,
        error: '当前平台没有 D3D12 共享纹理这条路',
      );
    }
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('init', <String, Object?>{
      'width': width,
      'height': height,
    });
    return GpuPresentStatus.fromMap(result ?? const <Object?, Object?>{});
  }

  /// 只问状态。
  ///
  /// 与 [stats] 分开：`stats` 会去要一份完整诊断快照（解码档位、分段耗时……），
  /// 那些在等待期全是零。轮询用这个。
  Future<GpuPresentStatus> status() async {
    if (!isPlatformSupported) {
      return const GpuPresentStatus(
        state: GpuPresentState.unsupported,
        error: '当前平台没有 D3D12 共享纹理这条路',
      );
    }
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('status');
    return GpuPresentStatus.fromMap(result ?? const <Object?, Object?>{});
  }

  /// 让 **GPU 路径**打开本地来源（散图文件夹 / CBZ / CBR），返回页数。
  ///
  /// 只有呈现器就绪后才有意义。未就绪时 native 侧回 `not-ready`（[PlatformException]），
  /// 那时该用的是 CPU 兜底路径 —— 它走的是 `local_core` 的 FRB 接口，与本桥无关。
  ///
  /// 两条路各开一份来源，是这个方案已知的代价：就绪后要重新 open 一次才能切过去。
  /// 归档目录的解析只值几毫秒，所以这次重复是可接受的；但接线进真正的阅读器时
  /// 页来源应当统一，见 `docs/texture-bridge-integration.md`。
  Future<int> open(String path) async {
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('open', <String, Object?>{
      'path': path,
    });
    final Object? count = result?['pageCount'];
    if (count is! int) {
      throw StateError('打开失败，native 侧没有返回页数: $result');
    }
    return count;
  }

  /// 呈现第 [index] 页。返回即表示像素已经落在共享纹理里，且引擎已被通知来取。
  Future<void> show(int index) async {
    _trace('show-enter idx=$index');
    try {
      await channel.invokeMethod<bool>('show', <String, Object?>{'index': index});
      _trace('show-done idx=$index');
    } catch (error) {
      _trace('show-error idx=$index err=$error');
      rethrow;
    }
  }

  /// 排查用：把 `show` 的发起与返回落到盘上。
  ///
  /// # 为什么 C++ 侧那份跟踪不够
  ///
  /// 桥里的 `ROSSI_GPU_SHOW_TRACE` 只能证明"平台上发生了什么"，
  /// **证明不了"应答有没有回到 Dart"**。而"投回平台线程的任务没跑"与
  /// "平台线程答了但 Dart 没收到"这两件事的排查方向完全不同 ——
  /// 在 GUI 子系统下两条通道都看不见，只能各自落盘。
  ///
  /// 设 `ROSSI_GPU_SHOW_TRACE_DART=<路径>` 才写；没设时是空分支。
  /// 单 isolate 写文件，不会互相盖行，所以同步写就够（一次翻页两行）。
  static void _trace(String line) {
    final String path =
        (Platform.environment['ROSSI_GPU_SHOW_TRACE_DART'] ?? '').trim();
    if (path.isEmpty) {
      return;
    }
    try {
      File(path).writeAsStringSync(
        '${DateTime.now().millisecondsSinceEpoch} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 跟踪写不出去不该影响呈现 —— 它是诊断，不是功能。
    }
  }

  /// 开关后台预取。
  ///
  /// 返回 `false` = native 侧没接受（还没就绪，或这个 DLL 没有这个导出）。
  /// **不抛异常**：这是个可选的性能开关，调用方不该为它写 try/catch；
  /// 而且"没接受"和"关了"必须能分辨 —— 混在一起会让 A/B 的对照组是假的。
  Future<bool> setPrefetchEnabled(bool enabled) async {
    final bool? accepted = await channel
        .invokeMethod<bool>('setPrefetch', <String, Object?>{'enabled': enabled});
    return accepted ?? false;
  }

  Future<GpuPresentStats> stats() async {
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('stats');
    return GpuPresentStats.fromMap(result ?? const <Object?, Object?>{});
  }

  /// 设置 GPU 实时 HDR 逆色调映射 (Inverse Tone Mapping) 与 SDR 增强。
  ///
  /// [mode]: 0: 关闭, 1: 扩展线性 HDR (scRGB/RGBA16F, 突破 1.0 白点), 2: SDR 增强 (软肩压缩)
  /// [boost]: 高光与白点扩展倍率 (1.0 ~ 16.0，推荐 1.5 ~ 3.0)
  /// [peak]: 显示器可用峰值倍率 (0.0 表示自动探测系统 EDR Headroom)
  Future<Map<String, dynamic>?> setHdr({
    required int mode,
    double boost = 1.5,
    double peak = 0.0,
  }) async {
    if (!isPlatformSupported) return null;
    try {
      final Map<Object?, Object?>? result = await channel.invokeMethod<Map<Object?, Object?>>(
        'setHdr',
        <String, Object?>{
          'mode': mode,
          'boost': boost,
          'peak': peak,
        },
      );
      return result?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// 查询当前屏幕的 EDR / HDR 硬件能力与当前呈现器色彩格式。
  Future<Map<String, dynamic>?> getHdrStatus() async {
    if (!isPlatformSupported) return null;
    try {
      final Map<Object?, Object?>? result =
          await channel.invokeMethod<Map<Object?, Object?>>('hdrStatus');
      return result?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// 把 EDR（真 HDR）平台视图接管给底层呈现器。
  ///
  /// 传一个有效的 [viewId] 后，native 侧会把后续所有帧渲染进那个原生图层的
  /// 半精度浮点缓冲区（数值可以超过 1.0，由 macOS 合成器交给显示器 EDR 头顶空间）。
  /// 传 `-1` 表示释放接管，退回 8 位 Flutter 纹理通路。
  ///
  /// 返回是否接管成功；失败时**不要**假定 HDR 生效了。
  Future<bool> attachHdrView(int viewId) async {
    if (!isPlatformSupported) return false;
    try {
      final Map<Object?, Object?>? result = await channel
          .invokeMethod<Map<Object?, Object?>>('attachHdrView', <String, Object?>{
        'viewId': viewId,
      });
      return result?['attached'] == true;
    } catch (_) {
      return false;
    }
  }

  /// HDR 通路诊断快照：图层是否接管、输出每像素字节数、当前模式与屏幕 EDR 余量。
  Future<Map<String, dynamic>?> getHdrDiagnostics() async {
    if (!isPlatformSupported) return null;
    try {
      final Map<Object?, Object?>? result =
          await channel.invokeMethod<Map<Object?, Object?>>('hdrDiagnostics');
      return result?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}

/// native 侧的诊断快照。
///
/// 字段分成两半，来源不同、含义也不同：
/// - C++ 侧上报的：状态、纹理注册情况、引擎来取过几次帧；
/// - Rust 侧上报的（[probe]，一段 JSON）：解码档位、分段耗时、拷贝路径。
///
/// 不把两半拍平成一个结构体，是因为它们的**变更节奏**不一样：
/// Rust 侧加一个计时字段不该逼着 C++ 的 map 也跟着改。
class GpuPresentStats {
  const GpuPresentStats({
    required this.ok,
    required this.state,
    required this.error,
    required this.textureId,
    required this.width,
    required this.height,
    required this.adapter,
    required this.luidKnown,
    required this.framesMarked,
    required this.handleOpened,
    required this.resizes,
    required this.pageCount,
    required this.showAsync,
    required this.showBusyRejected,
    required this.probe,
    required this.probeRaw,
  });

  /// native 侧这条路径**有实现**（DLL 在、符号齐、呈现器对象建出来了）。
  ///
  /// **不等于"现在能用"** —— 能不能用看 [state]。把这两件事压进一个 bool，
  /// 正是 `loading` 与 `failed` 分不开的根源。
  final bool ok;

  /// 现在能不能用。
  final GpuPresentState state;

  final String error;
  final int textureId;
  /// 呈现目标的当前尺寸（物理像素）。
  final int width;
  final int height;
  /// Flutter 正在用的那块显卡名。
  final String adapter;
  /// 有没有拿到 Flutter 的 adapter LUID。
  ///
  /// `false` 意味着 Rust 侧只能自己挑一块卡，跨 adapter 共享可能失败或极慢。
  /// 这不是无关紧要的细节，所以要显示出来。
  final bool luidKnown;
  /// 我们通知引擎来取帧的次数。
  final int framesMarked;
  /// **引擎打开共享句柄的次数**。
  ///
  /// 这是"链路真的通了"的唯一硬证据：引擎只有确实把这张纹理拿去合成了，
  /// 才会去打开句柄。`framesMarked` 只说明我们通知了，不说明有人来取。
  final int handleOpened;
  /// 呈现目标被重建的次数（拖动窗口会增长）。
  final int resizes;
  /// 最近一次打开的来源有几页。
  final int pageCount;

  /// `show` 是不是在桥自己的工作线程上跑的（`ROSSI_GPU_SHOW_ASYNC=0` 可以关掉）。
  ///
  /// 报出来是因为 A/B 要**先证明开关生效了**：开关没生效时两组读数几乎一样，
  /// 而那个"一样"会被读成"这个改动没用"。
  final bool showAsync;

  /// 因为"上一页还在呈现"而被拒掉的 `show` 次数。正常恒为 0。
  final int showBusyRejected;
  /// Rust 侧上报的 JSON，已解析。
  final Map<String, Object?> probe;
  /// 上面那份 JSON 的原文，用来在解析失败时还能给人看。
  final String probeRaw;

  factory GpuPresentStats.fromMap(Map<Object?, Object?> map) {
    final Object? rawProbe = map['probe'];
    final String probeRaw = rawProbe is String ? rawProbe : '';
    Map<String, Object?> probe = const <String, Object?>{};
    if (probeRaw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(probeRaw);
        if (decoded is Map<String, Object?>) {
          probe = decoded;
        }
      } catch (_) {
        // 解析失败不清空：原文留着，界面上能直接看到 Rust 侧报了什么。
      }
    }

    return GpuPresentStats(
      ok: map['ok'] == true,
      state: parseGpuPresentState(map['state']),
      error: '${map['error'] ?? ''}',
      textureId: _asInt(map['textureId'], fallback: -1),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      adapter: '${map['adapter'] ?? ''}',
      luidKnown: map['luidKnown'] == true,
      framesMarked: _asInt(map['framesMarked']),
      handleOpened: _asInt(map['handleOpened']),
      resizes: _asInt(map['resizes']),
      pageCount: _asInt(map['pageCount']),
      showAsync: map['showAsync'] == true,
      showBusyRejected: _asInt(map['showBusyRejected']),
      probe: probe,
      probeRaw: probeRaw,
    );
  }

  /// Rust 侧的一个字段。
  Object? operator [](String key) => probe[key];

  double probeDouble(String key) {
    final Object? value = probe[key];
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  int probeInt(String key) {
    final Object? value = probe[key];
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

}

/// 从 native 侧回传的 map 里取一个整数。
///
/// 收 `num` 而不是 `int`：Dart 的整数过 MethodChannel 可能以 int32 / int64 /
/// double 三种形态到达。`fallback` 用来区分"字段缺失"与"字段就是 0" ——
/// 纹理 id 缺失用 -1 表示，而"id 是 0"是另一件事。
int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}
