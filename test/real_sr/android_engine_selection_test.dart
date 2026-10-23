import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_sr_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';

/// Android 引擎选择（Vulkan CLI / QNN NPU）与缓存指纹。
///
/// 与 `sr_engine_selection_test.dart` 同源的两个回归点：
/// - Vulkan 分支的缓存指纹必须逐字节不变 —— 变了的话老用户已生成的
///   `sr_*_<key>.png` 会整体作废、被静默重推理，这种回归不报错只是变慢；
/// - 切到 QNN 后指纹必须由 NPU 模型决定，换模型必须换指纹。
///
/// 另外钉住模型清单：`AndroidQnnModel` 的 id 同时是 DLC 文件名与 manifest 键，
/// 与打包脚本 `script/models/package_qnn_models.py` 的 PACKAGED_MODELS
/// 两处同步维护，这里改了那里不改（或反过来）都会让下载-校验链路对不上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Android 引擎默认 Vulkan，存量外来值回落默认', () async {
    expect(
      defaultAndroidSuperResolutionEngine,
      AndroidSuperResolutionEngine.vulkan,
    );
    expect(
      await RealSrSettings.loadAndroidEngine(),
      AndroidSuperResolutionEngine.vulkan,
      reason: '全新安装应落在默认引擎',
    );

    SharedPreferences.setMockInitialValues({
      'realsr_android_engine': 'nonsense',
    });
    expect(
      await RealSrSettings.loadAndroidEngine(),
      AndroidSuperResolutionEngine.vulkan,
      reason: '存量外来值必须回落默认，不能漏到分派层',
    );

    SharedPreferences.setMockInitialValues({
      'realsr_android_engine': 'realsr_android_qnn',
    });
    expect(
      await RealSrSettings.loadAndroidEngine(),
      AndroidSuperResolutionEngine.qnnNpu,
    );
  });

  test('QNN 模型清单、倍率与 padding 与上游基线一致', () {
    // 与 script/models/package_qnn_models.py 的 PACKAGED_MODELS 对齐；
    // padding 取值来自上游 mihon_img_upscale（Real-CUGAN SE/Pro 2x = 18）。
    expect(AndroidQnnModel.values.map((model) => model.id), [
      'realcugan-se-x2-no-denoise',
      'realcugan-pro-x2-denoise3x',
    ]);
    expect(
      AndroidQnnModelConfig.defaultModel,
      AndroidQnnModel.seX2NoDenoise,
    );
    for (final model in AndroidQnnModel.values) {
      expect(model.scale, 2, reason: '${model.id} 倍率漂移');
      expect(model.padding, 18, reason: '${model.id} padding 漂移会改变分块行为');
    }
    // 网点纹理防护方案只对 Pro 家族 + 单色源启用（上游同口径）。
    expect(AndroidQnnModel.seX2NoDenoise.isPro, isFalse);
    expect(AndroidQnnModel.proX2Denoise3x.isPro, isTrue);
    expect(
      AndroidQnnModelConfig.byId('realcugan-pro-x2-denoise3x'),
      AndroidQnnModel.proX2Denoise3x,
    );
    expect(AndroidQnnModelConfig.byId('nonsense'), isNull);
  });

  test('Android 缓存指纹：Vulkan 分支逐字节不变，QNN 分支随模型变', () async {
    await RealSrSettings.saveAndroidEngine(AndroidSuperResolutionEngine.vulkan);
    await RealSrSettings.saveAndroidNcnnMode(AndroidNcnnMode.efficiency);
    await RealSrSettings.saveAndroidNcnnNoise(AndroidNcnnNoise.noise0);
    await RealSrSettings.saveScale(RealSrScale.x2);
    const vulkanKey = 'efficiency_noise0_2x';
    expect(
      await RealSrSettings.loadCacheKeyFor(isAndroid: true),
      vulkanKey,
      reason: 'Vulkan 分支指纹格式与接入 QNN 前逐字节一致',
    );

    await RealSrSettings.saveAndroidEngine(AndroidSuperResolutionEngine.qnnNpu);
    await RealSrSettings.saveAndroidQnnModel(AndroidQnnModel.seX2NoDenoise);
    expect(
      await RealSrSettings.loadCacheKeyFor(isAndroid: true),
      'qnn_realcugan-se-x2-no-denoise',
    );

    await RealSrSettings.saveAndroidQnnModel(
      AndroidQnnModel.proX2Denoise3x,
    );
    expect(
      await RealSrSettings.loadCacheKeyFor(isAndroid: true),
      'qnn_realcugan-pro-x2-denoise3x',
      reason: '换 NPU 模型必须换指纹，否则继续命中旧模型缓存',
    );
  });
}
