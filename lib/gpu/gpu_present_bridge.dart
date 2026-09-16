import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

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
/// # 平台边界
///
/// 只有 Windows 有 D3D12 共享纹理这条路。[isPlatformSupported] 是**能力探测**，
/// 不是"当前平台"的同义词：它同时还要求 native 侧真的注册上了纹理
/// （见 [stats] 的 `ok`）。调用方两个条件都要看。
class GpuPresentBridge {
  const GpuPresentBridge();

  /// 与 `windows/runner/gpu_present_bridge.cpp` 里的 channel 名一致。
  static const MethodChannel channel = MethodChannel('rossi/gpu_present');

  /// 这个平台有没有这条路径的**实现**。
  ///
  /// 注意它与"能不能用"不是一回事：Windows 上 native 侧仍可能因为缺
  /// `rossi_gpu_present.dll`（cargo 没构建）而不可用，那要看 [stats] 的 `ok` 与 `error`。
  static bool get isPlatformSupported => Platform.isWindows;

  /// 让 native 侧按 [width] / [height]（**物理像素**）确保呈现目标存在，返回 textureId。
  ///
  /// 传物理像素而不是逻辑像素：Flutter 的纹理按物理像素合成。给逻辑尺寸的话，
  /// 在 1.5x / 2x 缩放的屏幕上会得到一张被放大渲染的模糊图 —— 而且更糟的是
  /// 引擎随后会用另一个尺寸来问 `SurfaceCallback`，两边永远对不上，形成反复重建。
  Future<int> init({required int width, required int height}) async {
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('init', <String, Object?>{
      'width': width,
      'height': height,
    });
    final Object? textureId = result?['textureId'];
    if (textureId is! int || textureId < 0) {
      throw StateError('GPU 呈现桥没有返回可用的 textureId: $result');
    }
    return textureId;
  }

  /// 打开本地来源（散图文件夹 / CBZ / CBR），返回页数。
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
    await channel.invokeMethod<bool>('show', <String, Object?>{'index': index});
  }

  Future<GpuPresentStats> stats() async {
    final Map<Object?, Object?>? result =
        await channel.invokeMethod<Map<Object?, Object?>>('stats');
    return GpuPresentStats.fromMap(result ?? const <Object?, Object?>{});
  }
}

/// native 侧的诊断快照。
///
/// 字段分成两半，来源不同、含义也不同：
/// - C++ 侧上报的：纹理注册状态、引擎来取过几次帧；
/// - Rust 侧上报的（[probe]，一段 JSON）：解码档位、分段耗时、拷贝路径。
///
/// 不把两半拍平成一个结构体，是因为它们的**变更节奏**不一样：
/// Rust 侧加一个计时字段不该逼着 C++ 的 map 也跟着改。
class GpuPresentStats {
  const GpuPresentStats({
    required this.ok,
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
    required this.probe,
    required this.probeRaw,
  });

  /// native 侧自己是否认为这条路径可用。
  final bool ok;
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
      error: '${map['error'] ?? ''}',
      textureId: _asInt(map['textureId']),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      adapter: '${map['adapter'] ?? ''}',
      luidKnown: map['luidKnown'] == true,
      framesMarked: _asInt(map['framesMarked']),
      handleOpened: _asInt(map['handleOpened']),
      resizes: _asInt(map['resizes']),
      pageCount: _asInt(map['pageCount']),
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

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return -1;
  }
}
