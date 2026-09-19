import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/util/coreml_model_config.dart';

/// 下载并解压 iOS/macOS CoreML 超分模型。
///
/// 仓库里模型被打包成 `MacOS-iOS.7z`，下载后通过 Rust 侧的 `decompress7Z`
/// 解压到临时目录；社区 Real-ESRGAN 使用独立 ZIP，再返回本地模型路径。
class CoreMLModelLoader {
  CoreMLModelLoader._();

  /// 返回指定模型的本地路径。
  ///
  /// [fileName] 是模型文件名，例如：
  /// - `waifu2x_photo_noise0_scale2x.mlmodel`
  /// - `RealCUGAN_2x_no-denoise_block156.mlpackage`
  ///
  /// [onProgress] 可选，会收到已下载字节数和总字节数。
  static Future<String> prepareModel(
    String fileName, {
    void Function(int received, int total)? onProgress,
  }) async {
    for (final family in CoreMLModelConfig.families) {
      for (final variant in family.variants) {
        if (variant.fileName == fileName && variant.downloadUrl != null) {
          return _prepareZipModel(variant, onProgress: onProgress);
        }
      }
    }
    final tempDir = await getTemporaryDirectory();
    final modelsDir = Directory(p.join(tempDir.path, 'coreml_models'));
    final extractedDir = Directory(
      p.join(modelsDir.path, CoreMLModelConfig.archiveSubDir),
    );
    final archiveFile = File(
      p.join(modelsDir.path, CoreMLModelConfig.archiveName),
    );
    final modelPath = p.join(extractedDir.path, fileName);

    // 已经存在就直接返回
    if (_modelExists(modelPath)) {
      return modelPath;
    }

    await modelsDir.create(recursive: true);

    const maxAttempts = 2;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      // 没有压缩包（或上一次下载不完整）就重新下载
      if (!archiveFile.existsSync() || attempt > 0) {
        final client = WindHttp();
        final url =
            '${CoreMLModelConfig.binaryRepoBaseUrl}/${CoreMLModelConfig.archiveName}';
        logger.i('下载 CoreML 模型压缩包: $url');
        await client.download(
          url,
          archiveFile.path,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received, total);
          },
        );
      }

      // 用 Rust 解压 7z
      logger.i('解压 CoreML 模型压缩包...');
      final staging = await modelsDir.createTemp('.breeze-');
      try {
        await decompress7Z(
          archivePath: archiveFile.path,
          destPath: staging.path,
        );
        final unpacked = Directory(
          p.join(staging.path, CoreMLModelConfig.archiveSubDir),
        );
        await extractedDir.create(recursive: true);
        await for (final entry in unpacked.list()) {
          final destination = p.join(extractedDir.path, p.basename(entry.path));
          if (_modelExists(destination)) continue;
          if (await FileSystemEntity.type(destination) !=
              FileSystemEntityType.notFound) {
            if (await FileSystemEntity.isDirectory(destination)) {
              await Directory(destination).delete(recursive: true);
            } else {
              await File(destination).delete();
            }
          }
          await entry.rename(destination);
        }
        break;
      } catch (e, s) {
        logger.w('CoreML 压缩包解压失败，可能是下载不完整，准备重新下载', error: e, stackTrace: s);
        if (archiveFile.existsSync()) {
          try {
            await archiveFile.delete();
          } catch (_) {}
        }
        if (attempt == maxAttempts - 1) rethrow;
      } finally {
        await staging.delete(recursive: true);
      }
    }

    // 解压完成后删除压缩包节省空间
    try {
      await archiveFile.delete();
    } catch (_) {}

    if (!_modelExists(modelPath)) {
      throw Exception('模型不存在: $modelPath');
    }

    return modelPath;
  }

  static Future<String> _prepareZipModel(
    CoreMLModelVariant variant, {
    void Function(int received, int total)? onProgress,
  }) async {
    final models = await CoreMLModelConfig.modelsDirectory;
    final target = Directory(p.join(models.path, variant.fileName));
    if (_modelExists(target.path)) return target.path;
    await models.create(recursive: true);
    final staging = await models.createTemp('.download-');
    try {
      final archive = p.join(staging.path, 'model.zip');
      await WindHttp().download(
        variant.downloadUrl!,
        archive,
        onReceiveProgress: (received, total) =>
            onProgress?.call(received, total),
      );
      await compute(_extractModelZip, (archive, staging.path));
      final extracted = Directory(p.join(staging.path, variant.fileName));
      if (!_modelExists(extracted.path)) {
        throw StateError('下载的 CoreML 模型不完整：${variant.fileName}');
      }
      if (!_modelExists(target.path)) {
        if (await target.exists()) await target.delete(recursive: true);
        await extracted.rename(target.path);
      }
      return target.path;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  /// 检查指定模型是否已在本地（不会触发下载）。
  static Future<bool> isModelAvailable(String fileName) async {
    final dir = await CoreMLModelConfig.modelsDirectory;
    return _modelExists(p.join(dir.path, fileName));
  }

  static bool _modelExists(String path) {
    if (path.endsWith('.mlpackage')) {
      return File(p.join(path, 'Manifest.json')).existsSync() &&
          File(
            p.join(path, 'Data/com.apple.CoreML/model.mlmodel'),
          ).existsSync() &&
          File(
            p.join(path, 'Data/com.apple.CoreML/weights/weight.bin'),
          ).existsSync();
    }
    return File(path).existsSync();
  }
}

Future<void> _extractModelZip((String, String) paths) async {
  final input = InputFileStream(paths.$1);
  try {
    final archive = ZipDecoder().decodeStream(input);
    await extractArchiveToDisk(archive, paths.$2);
  } finally {
    await input.close();
  }
}
