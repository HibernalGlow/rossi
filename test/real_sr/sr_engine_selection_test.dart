import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';

/// 超分引擎的可选集与缓存指纹落点。
///
/// 这次把「哪台机器能选哪个引擎」从平台名字换成了能力判定，所以需要一份跑在
/// **真实平台**上的判据。最要防的是缓存指纹漂移：桌面 NCNN 的指纹格式一旦变了，
/// 老用户已生成的 `sr_*_<key>.png` 会整体作废、被静默重新推理一遍 —— 这种回归
/// 不报错，只是变慢，没人会当成 bug 报上来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final isApple = Platform.isMacOS || Platform.isIOS;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('可用引擎与默认值按能力给，不按平台名字写死', () {
    expect(availableEngines, contains(SuperResolutionEngine.mimageOnnx));
    if (isApple) {
      expect(availableEngines, contains(SuperResolutionEngine.breezeCoreML));
      expect(
        availableEngines,
        isNot(contains(SuperResolutionEngine.desktopNcnn)),
      );
      expect(defaultEngine, SuperResolutionEngine.mimageOnnx);
    } else {
      // Windows / Linux：ONNX 与桌面 NCNN 并列，默认仍是改动前唯一的路线 NCNN。
      expect(availableEngines, contains(SuperResolutionEngine.desktopNcnn));
      expect(
        availableEngines,
        isNot(contains(SuperResolutionEngine.breezeCoreML)),
      );
      expect(defaultEngine, SuperResolutionEngine.desktopNcnn);
    }
  });

  test('存量的外来引擎值被夹回可用集，不会漏到分派层', () async {
    for (final stored in ['breeze_coreml', 'nonsense', '']) {
      SharedPreferences.setMockInitialValues({'realsr_apple_engine': stored});
      expect(
        availableEngines,
        contains(await RealSrSettings.loadEngine()),
        reason: '存量值 $stored 不在本平台可用集内时必须回落',
      );
    }
  });

  test('桌面 NCNN 的缓存指纹与改动前逐字节一致，且换引擎必须变', () async {
    await RealSrSettings.saveEngine(SuperResolutionEngine.desktopNcnn);
    await RealSrSettings.saveDesktopNcnnMode(AndroidNcnnMode.efficiency);
    await RealSrSettings.saveDesktopNcnnNoise(
      AndroidNcnnNoise.noiseConservative,
    );
    await RealSrSettings.saveScale(RealSrScale.x2);
    const ncnnKey = 'efficiency_noise-1_2x';
    expect(await RealSrSettings.loadCacheKey(), ncnnKey);
    // profile.cacheKey 被呈现链路直接取用（gpu_present_controller），两处必须同源。
    expect((await RealSrSettings.loadProfile()).cacheKey, ncnnKey);

    await RealSrSettings.saveEngine(SuperResolutionEngine.mimageOnnx);
    expect(await RealSrSettings.loadCacheKey(), isNot(ncnnKey));
    expect((await RealSrSettings.loadProfile()).cacheKey, isNot(ncnnKey));
  }, skip: supportsDesktopNcnn ? false : '本平台没有桌面 NCNN 这条引擎');
}
