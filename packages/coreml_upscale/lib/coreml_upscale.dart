import 'package:flutter/services.dart';

/// CoreML 图片超分插件。
///
/// 目前支持 macOS / iOS，模型通过绝对路径传入。
class CoreMLUpscale {
  static const MethodChannel _channel = MethodChannel('coreml_upscale');

  /// 对单张图片做超分。
  ///
  /// [modelPath] 为 .mlmodel 或 .mlpackage 的绝对路径。
  /// [modelType] 可选 `multiarray`（默认）或 `image`。
  /// [config] 透传给原生模型，例如 `{"blockSize": 156, "shrinkSize": 7, "scale": 2}`。
  static Future<void> upscale({
    required String inputPath,
    required String outputPath,
    required String modelPath,
    String modelType = 'multiarray',
    Map<String, dynamic>? config,
  }) async {
    await _channel.invokeMethod('upscale', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'modelPath': modelPath,
      'modelType': modelType,
      'config': config,
    });
  }

  /// 释放原生侧常驻的模型实例（`ModelManager.imageModelCache`）。
  ///
  /// 调用时机 = 离开阅读器（`LocalReadSession.dispose`，与 ONNX 侧
  /// `mimageOnnxReleaseSessions` 同点）。磁盘上的编译产物不受影响，
  /// 下次 `upscale` 重载即可。没建过模型的进程调用它没有副作用。
  static Future<void> releaseModels() async {
    await _channel.invokeMethod('releaseModels');
  }
}
