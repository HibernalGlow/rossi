import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('book override follows global again when set to global value', () async {
    expect(await ImageDenoiseSettings.enabledFor('book-a'), isFalse);
    await ImageDenoiseSettings.saveFor('book-a', true);
    expect(await ImageDenoiseSettings.enabledFor('book-a'), isTrue);
    expect(await ImageDenoiseSettings.enabledFor('book-b'), isFalse);

    await ImageDenoiseSettings.saveGlobal(true);
    await ImageDenoiseSettings.saveFor('book-a', true);
    await ImageDenoiseSettings.saveGlobal(false);
    expect(await ImageDenoiseSettings.enabledFor('book-a'), isFalse);
  });

  test('cache key includes 1x model version and stage order', () async {
    const upscale = 'mimage_onnx_realcugan_4x_7';
    expect(
      await ImageDenoiseSettings.cacheKey(
        denoise: false,
        upscale: true,
        upscaleKey: upscale,
      ),
      upscale,
    );
    final denoiseOnly = await ImageDenoiseSettings.cacheKey(
      denoise: true,
      upscale: false,
      upscaleKey: upscale,
    );
    final chain = await ImageDenoiseSettings.cacheKey(
      denoise: true,
      upscale: true,
      upscaleKey: upscale,
    );
    expect(denoiseOnly, 'realplksr_1x_0');
    expect(chain, 'realplksr_1x_0_then_$upscale');
    await ImageDenoiseSettings.modelChanged();
    expect(
      await ImageDenoiseSettings.cacheKey(
        denoise: true,
        upscale: false,
        upscaleKey: upscale,
      ),
      isNot(denoiseOnly),
    );
  });

  test('all four modes map to their ordered stages', () {
    for (final mode in ImageEnhancementMode.values) {
      expect(
        ImageEnhancementMode.fromStages(
          denoise: mode.usesDenoise,
          upscale: mode.usesUpscale,
        ),
        mode,
      );
    }
  });
}
