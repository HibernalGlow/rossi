import 'dart:io';
import 'package:zephyr/page/comic_info/method/export_comic.dart'
    show detectImageExtension;

import 'package:zephyr/page/setting/real_sr/service/image_denoise_model.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/service/sr_session_guard.dart';
import 'package:zephyr/reader/page_animation.dart';
import 'package:zephyr/src/rust/api/image.dart';
import 'package:zephyr/src/rust/api/mimage_onnx.dart';

/// 沿用 mImageViewer denoise -> upscale 的 1× 分块流程，后端由既有 ONNX 执行器提供。
abstract final class ImageDenoisePipeline {
  static Future<bool> isAvailable() async =>
      await ImageDenoiseModel.installedSize() > 0;

  /// 所有入口共享模型传输与状态。force 仍保留为旧调用方的兼容参数。
  static Future<void> download({
    void Function(int received, int total)? onProgress,
    bool force = false,
  }) async {
    if (!force && await isAvailable()) return;
    final downloads = ImageDenoiseModel.downloads;
    void report() => onProgress?.call(downloads.received, downloads.total);
    downloads.addListener(report);
    try {
      await downloads.download();
      if (downloads.error != null) throw StateError(downloads.error!);
    } finally {
      downloads.removeListener(report);
    }
  }

  /// 对原图执行 1x JPEG 降噪，成功时输出与输入同尺寸的独立 PNG。
  static Future<bool> process({
    required String inputPath,
    required String outputPath,
    int? tileSize,
    ImageDenoiseOptions? options,
    required Future<bool> Function(Future<bool> Function()) withResource,
    bool Function()? shouldRun,
  }) async {
    options ??= await ImageDenoiseSettings.loadOptions();
    final config = options;
    if (!supportsMImageOnnx) return false;
    final input = File(inputPath);
    if (config.jpegOnly && await input.exists()) {
      final format = (await detectImageExtension(input)).toLowerCase();
      if (format != '.jpg' && format != '.jpeg') {
        if (await animatedFileHead(input)) return false;
        await convertImageToPng(inputPath: inputPath, outputPath: outputPath);
        return await File(outputPath).exists();
      }
    }
    if (!await input.exists() ||
        !{
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
        }.contains((await detectImageExtension(input)).toLowerCase()) ||
        await animatedFileHead(input)) {
      return false;
    }
    if (!await isAvailable()) return false;
    return withResource(() async {
      if (shouldRun != null && !shouldRun()) return false;
      final inputSize = await RealSrSuperResolution.imageSizeOf(inputPath);
      if (inputSize == null) return false;
      final modelPath = (await ImageDenoiseModel.file).path;
      SrSessionGuard.markOnnxHeld();
      await mimageOnnxUpscale(
        inputPath: inputPath,
        outputPath: outputPath,
        modelPath: modelPath,
        modelId: MImageOnnxModelConfig.denoiseModelId,
        tileSize: tileSize ?? config.tileSize,
      );
      final output = File(outputPath);
      if (!await output.exists() || await output.length() == 0) return false;
      final outputSize = await RealSrSuperResolution.imageSizeOf(outputPath);
      return outputSize == inputSize;
    });
  }
}
