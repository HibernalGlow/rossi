import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

/// Android 两条超分后端的执行体（从 `real_sr_super_resolution.dart` 抽出，
/// 该文件已超千行；队列 / 缓存 / 就绪判定留在原处）。
///
/// - [upscaleAndroidVulkanCli]：外部 waifu2x CLI 进程（ncnn + Vulkan），历史路线。
/// - [upscaleAndroidQnn]：进程内 JNI 的 Qualcomm QNN / HTP NPU 推理。
///   失败时抛错并保留原图，**不回退** Vulkan —— 调用方与用户需要知道
///   NPU 路线没有生效，而不是悄悄换了个后端出图。
abstract class AndroidUpscaleEngines {
  AndroidUpscaleEngines._();

  static const MethodChannel _channel = MethodChannel(
    'realsr_super_resolution',
  );

  /// Android 通过 bundled waifu2x CLI（Vulkan）超分。
  ///
  /// [modelRoot] 为 `<getFilePath()/super_resolution`；输出必须是 PNG
  /// 扩展名（CLI 按扩展名识别输出格式）。
  static Future<void> upscaleAndroidVulkanCli({
    required String inputPath,
    required String outputPath,
    required NcnnModelVariant variant,
    required int tileSize,
    required String modelRoot,
  }) async {
    final exePath = await _prepareAndroidCli();
    final modelPath = p.join(modelRoot, variant.modelDir);

    final result = await Process.run(
      exePath,
      [
        '-i',
        inputPath,
        '-o',
        outputPath,
        '-s',
        variant.scale.toString(),
        '-n',
        variant.noise.toString(),
        '-m',
        modelPath,
        '-g',
        '0',
        '-t',
        tileSize.toString(),
      ],
      runInShell: false,
      workingDirectory: modelRoot,
    );

    if (result.exitCode != 0) {
      throw StateError(
        'waifu2x CLI 失败 (exitCode=${result.exitCode})\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
      );
    }
  }

  static String? _androidCliPath;

  /// 获取 APK 中 bundled 的 waifu2x CLI 路径（位于 nativeLibraryDir）。
  static Future<String> _prepareAndroidCli() async {
    if (_androidCliPath != null) return _androidCliPath!;

    final path = await _channel.invokeMethod<String>('getWaifu2xCliPath');
    if (path == null || path.isEmpty) {
      throw StateError('getWaifu2xCliPath returned empty path');
    }
    _androidCliPath = path;
    return path;
  }

  /// Android 通过 QNN（Qualcomm HTP NPU）超分，返回实际产物倍率。
  ///
  /// [dlcRoot] 为 QNN 模型目录（`<modelRoot>/qnn`）。首次调用会触发设备端
  /// 上下文编译（约 1-2 s）并持久化，之后直接复用。
  static Future<int> upscaleAndroidQnn({
    required String inputPath,
    required String outputPath,
    required AndroidQnnModel model,
    required String modelRoot,
  }) async {
    final scale = await AndroidQnnEngine.upscale(
      inputPath: inputPath,
      outputPath: outputPath,
      model: model,
    );
    SuperResolutionLog.add(
      'QNN NPU 推理完成：${model.label}，${scale}× → $outputPath',
    );
    return scale;
  }
}
