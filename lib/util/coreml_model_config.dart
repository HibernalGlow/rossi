import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/util/get_path.dart';

/// iOS / macOS CoreML 超分模型配置。
///
/// 模型文件来自 GitHub `deretame/breeze-binary` 的 `MacOS-iOS.7z`，
/// Breeze 压缩包提供以下两个变体：
/// - waifu2x_photo_noise0_scale2x.mlmodel
/// - RealCUGAN_2x_no-denoise_block156.mlpackage
/// Real-ESRGAN x4plus 使用独立的社区 CoreML ZIP，保留原生 4× 倍率。
class CoreMLModelFamily {
  final String id;
  final String label;
  final List<CoreMLModelVariant> variants;

  CoreMLModelFamily({
    required this.id,
    required this.label,
    required this.variants,
  });

  /// 用户界面显示的本地化模型族名称。
  String get localizedLabel {
    return switch (id) {
      'waifu2x' => t.realSr.coremlSpeed,
      'realcugan' => t.realSr.coremlQuality,
      _ => label,
    };
  }
}

class CoreMLModelVariant {
  final String displayName;
  final String fileName;
  final Map<String, dynamic> config;
  final String? downloadUrl;

  CoreMLModelVariant({
    required this.displayName,
    required this.fileName,
    required this.config,
    this.downloadUrl,
  });

  /// 用户界面显示的本地化变体名称。
  String get localizedDisplayName {
    return switch (fileName) {
      'waifu2x_photo_noise0_scale2x.mlmodel' => t.realSr.coremlNoise0,
      'RealCUGAN_2x_no-denoise_block156.mlpackage' => t.realSr.coremlNoDenoise,
      _ => displayName,
    };
  }
}

abstract class CoreMLModelConfig {
  CoreMLModelConfig._();

  static const String archiveName = 'MacOS-iOS.7z';
  static const String archiveSubDir = 'MacOS-iOS';
  static const String binaryRepoBaseUrl =
      'https://github.com/deretame/breeze-binary/raw/main';

  static final List<CoreMLModelFamily> families = <CoreMLModelFamily>[
    CoreMLModelFamily(
      id: 'waifu2x',
      label: t.realSr.coremlSpeed,
      variants: <CoreMLModelVariant>[
        CoreMLModelVariant(
          displayName: t.realSr.coremlNoise0,
          fileName: 'waifu2x_photo_noise0_scale2x.mlmodel',
          config: <String, dynamic>{
            'inputName': 'input',
            'outputName': 'output',
            'blockSize': 156,
            'shrinkSize': 7,
            'scale': 2,
          },
        ),
      ],
    ),
    CoreMLModelFamily(
      id: 'realcugan',
      label: t.realSr.coremlQuality,
      variants: <CoreMLModelVariant>[
        CoreMLModelVariant(
          displayName: t.realSr.coremlNoDenoise,
          fileName: 'RealCUGAN_2x_no-denoise_block156.mlpackage',
          config: <String, dynamic>{
            'inputName': 'input',
            'outputName': 'output',
            'blockSize': 192,
            'shrinkSize': 18,
            'scale': 2,
          },
        ),
      ],
    ),
    CoreMLModelFamily(
      id: 'realesrgan',
      label: 'Real-ESRGAN x4plus · 照片/CG',
      variants: <CoreMLModelVariant>[
        CoreMLModelVariant(
          displayName: '模型自带降噪',
          fileName: 'RealESRGAN-x4plus.mlpackage',
          downloadUrl:
              'https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML/resolve/main/RealESRGAN-x4plus.mlpackage.zip',
          config: <String, dynamic>{
            'inputName': 'input',
            'outputName': 'output',
            'blockSize': 256,
            'shrinkSize': 16,
            // ESRGAN 返回完整输入的 4×，裁掉上下文后再拼接。
            'outputCrop': 64,
            'inputBias': 0.0,
            'scale': 4,
          },
        ),
      ],
    ),
  ];

  static CoreMLModelFamily get defaultFamily => families.first;

  static CoreMLModelVariant get defaultVariant => defaultFamily.variants.first;

  static CoreMLModelFamily? familyById(String id) {
    for (final family in families) {
      if (family.id == id) return family;
    }
    return null;
  }

  static CoreMLModelVariant? variantByFileName(
    CoreMLModelFamily family,
    String fileName,
  ) {
    for (final variant in family.variants) {
      if (variant.fileName == fileName) return variant;
    }
    return null;
  }

  /// 内容块尺寸 = 模型输入尺寸 - 2×反射边距。
  static int contentBlockSize(CoreMLModelVariant variant) {
    final blockSize = variant.config['blockSize'] as int? ?? 0;
    final shrinkSize = variant.config['shrinkSize'] as int? ?? 0;
    return blockSize - 2 * shrinkSize;
  }

  /// 解压后模型根目录：`getFilePath()/super_resolution/coreml_models/<archiveSubDir>`。
  ///
  /// 曾经这里在 `getTemporaryDirectory()` 下，于是每次启动都要重下一整包：macOS 的
  /// `/usr/libexec/dirhelper` 每天 03:35 清 `$TMPDIR`（`CLEAN_FILES_OLDER_THAN_DAYS=3`），
  /// 而就绪判据只看这个目录里有没有文件（`CoreMLModelLoader.isModelAvailable`）。
  /// 放在 `super_resolution/` 里与 mImage ONNX 同级，`deleteModel` 的整目录清理才覆盖得到它。
  static Future<Directory> get modelsDirectory async => Directory(
    p.join(
      await getFilePath(),
      'super_resolution', // 与 `real_sr_super_resolution.dart` 的 `_modelDirectory` 同源
      rootSegment,
      archiveSubDir,
    ),
  );

  /// [modelsDirectory] 改址前的位置，仅用于一次性搬迁。
  static Future<Directory> get legacyModelsDirectory async => Directory(
    p.join((await getTemporaryDirectory()).path, rootSegment, archiveSubDir),
  );

  /// 新旧两处都用的那一段目录名。
  static const String rootSegment = 'coreml_models';
}
