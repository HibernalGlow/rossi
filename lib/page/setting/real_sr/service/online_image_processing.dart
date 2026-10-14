import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/image_enhancement_file_cache.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_policy_service.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';

abstract final class OnlineImageProcessing {
  static final _cache = ImageEnhancementFileCache();
  // 原图预览只影响显示，不能改变后台处理设置或覆盖保存的书级偏好。
  static final originalPreview = ValueNotifier<(String?, bool)>((null, false));
  static bool previewsOriginal(String? bookKey) =>
      originalPreview.value == (bookKey, true);
  static void setOriginalPreview(String? bookKey, bool value) {
    originalPreview.value = (bookKey, value);
  }

  static Future<String?> process(String sourcePath, {String? bookKey}) async {
    final denoise =
        supportsMImageOnnx && await ImageDenoiseSettings.enabledFor(bookKey);
    var upscale = await RealSrBookScope.enabledFor(bookKey);
    if (!denoise && !upscale) return null;
    final profile = hasSuperResolutionEngineChoice
        ? await RealSrSettings.loadProfile()
        : null;
    var tileSize = await RealSrSettings.loadTileSize();
    if (upscale && !denoise) {
      final conditional = await RealSrSettings.loadConditionalEnabled();
      if (conditional) {
        final decision = await RealSrSuperResolution.decidePolicy(
          inputPath: sourcePath,
          bookPath: bookKey ?? '',
          trigger: SuperResolutionPolicyTrigger.auto,
          autoUpscaleEnabled: true,
        );
        upscale = decision.shouldRun;
        tileSize = decision.tileSize ?? 0;
      } else {
        upscale = await RealSrSuperResolution.shouldUpscale(sourcePath);
      }
    }
    if (!denoise && !upscale) return null;
    final denoiseOptions = await ImageDenoiseSettings.loadOptions();
    final pipelineKey = await ImageDenoiseSettings.cacheKey(
      denoise: denoise,
      options: denoiseOptions,
      upscale: upscale,
      upscaleKey: await RealSrSettings.loadCacheKey(),
    );
    final stages = <FileEnhancementStage>[
      if (denoise)
        (input, output) => RealSrSuperResolution.denoise(
          inputPath: input,
          outputPath: output,
          options: denoiseOptions,
        ),
      if (upscale)
        (input, output) async {
          if (Platform.isWindows || Platform.isLinux) {
            final variant = DesktopNcnnModelConfig.variantFor(
              mode: await RealSrSettings.loadDesktopNcnnMode(),
              noise: await RealSrSettings.loadDesktopNcnnNoise(),
            );
            return RealSrSuperResolution.upscale(
              inputPath: input,
              outputPath: output,
              engineProfile: profile,
              executable: variant.displayName,
              modelDir: variant.modelDir,
              scale: variant.scale,
              noiseLevel: RealSrNoiseLevel.values.firstWhere(
                (v) => v.value == variant.noise,
                orElse: () => RealSrNoiseLevel.conservative,
              ),
              tileSize: tileSize,
            );
          }
          return RealSrSuperResolution.upscale(
            inputPath: input,
            outputPath: output,
            engineProfile: profile,
            noiseLevel: await RealSrSettings.loadNoiseLevel(),
            tileSize: tileSize,
          );
        },
    ];
    return _cache.process(
      sourcePath: sourcePath,
      cacheDirectory: Directory(
        p.join(await getCachePath(), 'reader_image_processing'),
      ),
      pipelineKey: '${pipelineKey}_policyTile$tileSize',
      stages: stages,
    );
  }
}
