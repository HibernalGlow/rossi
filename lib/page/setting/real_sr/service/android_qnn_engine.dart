import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_model_config.dart';
import 'package:zephyr/util/get_path.dart';

/// `realsr_super_resolution` MethodChannel 的 QNN 方法组封装。
///
/// 原生侧实现在 `android/.../realsr/RealSrQnnChannel.kt`；失败语义与
/// mihon_img_upscale 一致：显式选择 NPU 时**不回退** Vulkan，错误如实抛出，
/// 由调用方（`RealSrSuperResolution.upscale` 的产物校验契约）保留原图并重试。
abstract class AndroidQnnEngine {
  AndroidQnnEngine._();

  static const MethodChannel _channel = MethodChannel(
    'realsr_super_resolution',
  );

  /// 一次探测的结果。
  ///
  /// [supported] 为「运行时可加载且 HTP 架构在支持列表内」（v69/v73/v75/
  /// v79/v81），决定设置页是否允许选择 NPU 引擎。
  static bool _probeCacheLoaded = false;
  static AndroidQnnProbe? _probeCache;

  /// DLC 根目录：`<getFilePath()/super_resolution/qnn/`。
  static Future<String> get _dlcRoot async => p.join(
    await getFilePath(),
    'super_resolution',
    AndroidQnnModelConfig.dlcDirName,
  );

  static Future<AndroidQnnProbe?> probe() async {
    if (!Platform.isAndroid) return null;
    if (_probeCacheLoaded) return _probeCache;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('qnnProbe');
      final probe = raw == null ? null : AndroidQnnProbe.fromMap(raw);
      _probeCache = probe;
      _probeCacheLoaded = true;
      return probe;
    } catch (e) {
      logger.w('QNN probe 失败', error: e);
      return null;
    }
  }

  /// NPU 后端是否可用（运行时 + HTP 架构均通过）。
  static Future<bool> get isSupported async =>
      (await probe())?.supported ?? false;

  /// 指定模型的 DLC 与 manifest 是否已下载到位。
  static Future<bool> isModelDownloaded([AndroidQnnModel? target]) async {
    if (!Platform.isAndroid) return false;
    final model = target ?? AndroidQnnModelConfig.defaultModel;
    final root = await _dlcRoot;
    return File(p.join(root, '${model.id}.dlc')).existsSync() &&
        File(p.join(root, 'manifest.json')).existsSync();
  }

  /// 编译并缓存模型上下文（设置页「准备模型」按钮）。
  ///
  /// 返回 null 表示成功；否则为错误信息。
  static Future<String?> prepare({
    required AndroidQnnModel model,
    bool retry = false,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('qnnPrepare', {
      'modelRoot': await _dlcRoot,
      'modelName': model.id,
      'retry': retry,
    });
    if (raw == null) return 'qnnPrepare returned null';
    return (raw['success'] as bool? ?? false)
        ? null
        : (raw['error'] as String? ?? 'unknown');
  }

  /// 各模型的准备状态；键为模型名，state ∈ preparing/ready/failed。
  static Future<Map<String, AndroidQnnModelStatus>> status() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('qnnStatus');
    final models = raw?['models'];
    if (models is! Map) return {};
    return models.map(
      (name, value) => MapEntry(
        name.toString(),
        AndroidQnnModelStatus.fromMap(
          value is Map ? value.cast<String, dynamic>() : const {},
        ),
      ),
    );
  }

  /// 对一张 PNG 做端到端 NPU 超分。成功返回产物倍率；失败抛 [StateError]
  /// 并携带原生侧错误（不静默回退其它后端）。
  static Future<int> upscale({
    required String inputPath,
    required String outputPath,
    required AndroidQnnModel model,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('qnnUpscale', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'modelRoot': await _dlcRoot,
      'modelName': model.id,
      'padding': model.padding,
      'isPro': model.isPro,
    });
    final success = raw?['success'] as bool? ?? false;
    if (!success) {
      throw StateError(raw?['error'] as String? ?? 'QNN upscale failed');
    }
    return raw?['scale'] as int? ?? model.scale;
  }

  /// 交还 NPU 上下文（阅读会话结束；磁盘上已编译的上下文不受影响）。
  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('qnnRelease');
    } catch (e) {
      logger.w('QNN 上下文交还失败', error: e);
    }
  }
}

class AndroidQnnProbe {
  const AndroidQnnProbe({
    required this.libraryLoaded,
    required this.runtimeAvailable,
    this.architecture,
  });

  final bool libraryLoaded;

  /// `librealsr_qnn.so` 加载成功且 `libQnnHtp.so` 可用。stub 构建（无 QAIRT
  /// SDK 的 CI 产物）这里为 false。
  final bool runtimeAvailable;

  /// 实际 HTP 架构（69/73/75/79/81）；null = 探测失败或不受支持。
  final int? architecture;

  /// 运行时 + 架构都通过。
  bool get supported => runtimeAvailable && architecture != null;

  static AndroidQnnProbe fromMap(Map<String, dynamic> map) => AndroidQnnProbe(
    libraryLoaded: map['libraryLoaded'] as bool? ?? false,
    runtimeAvailable: map['runtimeAvailable'] as bool? ?? false,
    architecture: map['architecture'] as int?,
  );
}

class AndroidQnnModelStatus {
  const AndroidQnnModelStatus({required this.state, this.error});

  /// preparing / ready / failed / idle。
  final String state;
  final String? error;

  static AndroidQnnModelStatus fromMap(Map<String, dynamic> map) =>
      AndroidQnnModelStatus(
        state: map['state'] as String? ?? 'idle',
        error: map['error'] as String?,
      );
}
