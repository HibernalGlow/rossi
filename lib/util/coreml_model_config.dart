import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/i18n/strings.g.dart';

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

  /// 返回解压后模型根目录。
  static Future<Directory> get modelsDirectory async {
    final tempDir = await getTemporaryDirectory();
    return Directory(p.join(tempDir.path, 'coreml_models', archiveSubDir));
  }
}
