import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// 有「超分引擎」这颗选择器的平台（Android 用内置 CLI，不参与选择）。
bool get hasSuperResolutionEngineChoice =>
    !kIsWeb &&
    (Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isIOS);

/// 能跑 Breeze 原生 CoreML 引擎的平台。
bool get supportsCoreML => !kIsWeb && (Platform.isMacOS || Platform.isIOS);

/// 能跑 mImage ONNX 引擎的平台。Rust 侧 `init_ort` 对 Apple 注册 CoreML EP、
/// 对 Windows 注册 DirectML EP（**注册失败即报错，不退回 CPU**），
/// 其余平台留默认 EP。
bool get supportsMImageOnnx =>
    !kIsWeb &&
    (Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isIOS);

/// 桌面 NCNN（waifu2x / Real-CUGAN 可执行文件）这条路的平台。
bool get supportsDesktopNcnn => !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// mImage ONNX 引擎在本平台的**实际**运行时，供设置页如实显示。
///
/// 必须与 `rust/src/api/mimage_onnx.rs` 里 `init_ort` 按目标注册的 EP 一致：
/// Apple 是 CoreML EP，Windows 是 DirectML EP（且注册失败即报错、不退回 CPU），
/// 其余平台没有注册任何 EP，就是 ONNX Runtime 自带的 CPU EP。
String get mImageRuntimeLabel {
  if (supportsCoreML) return 'CoreML · Apple Neural Engine / GPU';
  if (Platform.isWindows) return 'DirectML · DirectX 12 GPU';
  return 'ONNX Runtime · CPU';
}

enum SuperResolutionEngine {
  breezeCoreML('breeze_coreml', 'Rossi 原生 CoreML'),
  mimageOnnx('mimage_onnx', 'mImage ONNX'),
  desktopNcnn('desktop_ncnn', '桌面 NCNN（waifu2x / Real-CUGAN）');

  const SuperResolutionEngine(this.id, this.label);
  final String id;
  final String label;
}

/// 本平台可选的引擎，顺序即下拉顺序。
List<SuperResolutionEngine> get availableEngines => [
  if (supportsCoreML) SuperResolutionEngine.breezeCoreML,
  if (supportsMImageOnnx) SuperResolutionEngine.mimageOnnx,
  if (supportsDesktopNcnn) SuperResolutionEngine.desktopNcnn,
];

/// 未设置时的默认引擎。
///
/// Windows / Linux 保持 **桌面 NCNN**：那是这次改动之前唯一的路线，默认值改了
/// 就等于替所有桌面用户换引擎（ONNX 在非 Apple 上此前从未跑过）。
SuperResolutionEngine get defaultEngine =>
    supportsDesktopNcnn
        ? SuperResolutionEngine.desktopNcnn
        : SuperResolutionEngine.mimageOnnx;

/// 一次任务的不可变配置；排队期间切换设置不会改变正在处理的模型。
class SuperResolutionProfile {
  const SuperResolutionProfile({
    required this.engine,
    required this.mimageModel,
    required this.coremlVariant,
    required this.cacheKey,
    this.desktopScale = 2,
  });

  final SuperResolutionEngine engine;
  final MImageOnnxModel mimageModel;
  final CoreMLModelVariant coremlVariant;
  final String cacheKey;

  /// 桌面 NCNN 的倍率；只有 engine 是 desktopNcnn 时有意义。
  final int desktopScale;

  int get scale => switch (engine) {
    SuperResolutionEngine.breezeCoreML =>
      coremlVariant.config['scale'] as int,
    SuperResolutionEngine.mimageOnnx => mimageModel.scale,
    SuperResolutionEngine.desktopNcnn => desktopScale,
  };
}

class _RealSrSettingsNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// RealSR / Real-CUGAN 超分设置
///
/// 这些配置不进入 ObjectBox 的 [GlobalSettingState]，而是直接存在
/// SharedPreferences 中，避免把“功能开关”和“全局配置”混在一起。
class RealSrSettings {
  RealSrSettings._();

  static final _RealSrSettingsNotifier _modelChanges =
      _RealSrSettingsNotifier();
  static ChangeNotifier get modelChanges => _modelChanges;
  static void notifyChanges() => _modelChanges.notify();

  static MImageOnnxModel _currentMImageModel =
      MImageOnnxModelConfig.defaultModel;
  static MImageOnnxModel get currentMImageModel => _currentMImageModel;

  /// 引擎的同步快照。`manualDownloadUrl` 这类**同步** getter 要按引擎决定给哪个
  /// 下载链接，而读 SharedPreferences 是异步的，所以留一份和
  /// [currentMImageModel] 同类的缓存；首次 [loadEngine]/[saveEngine] 之前是平台默认值。
  static SuperResolutionEngine _currentEngine = defaultEngine;
  static SuperResolutionEngine get currentEngine => _currentEngine;

  static final prefetchChanges = _RealSrSettingsNotifier();

  static Future<(int, int)> loadPrefetch() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      (prefs.getInt('realsr_prefetch_forward') ?? 2).clamp(0, 5),
      (prefs.getInt('realsr_prefetch_back') ?? 1).clamp(0, 5),
    );
  }

  static Future<void> savePrefetch({
    required int forward,
    required int back,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('realsr_prefetch_forward', forward.clamp(0, 5));
    await prefs.setInt('realsr_prefetch_back', back.clamp(0, 5));
    prefetchChanges.notify();
  }

  // 存储键沿用 `realsr_apple_engine`：改名会让老用户的引擎选择回到默认值。
  static const _keyEngine = 'realsr_apple_engine';

  /// 读引擎，并把存量值夹到本平台可用的那一档。
  ///
  /// 例如在 Windows 上读到 `breeze_coreml`（从 Mac 同步来的设置）会落到默认引擎，
  /// 而不是让上层拿着一个本平台跑不了的引擎去分派。
  static Future<SuperResolutionEngine> loadEngine() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = SuperResolutionEngine.values.firstWhere(
      (engine) => engine.id == prefs.getString(_keyEngine),
      orElse: () => defaultEngine,
    );
    final available = availableEngines;
    final engine = available.contains(stored) ? stored : defaultEngine;
    _currentEngine = engine;
    return engine;
  }

  static Future<void> saveEngine(SuperResolutionEngine engine) async {
    _currentEngine = engine;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyEngine) == engine.id) return;
    await prefs.setString(_keyEngine, engine.id);
    notifyChanges();
  }

  static Future<SuperResolutionProfile> loadProfile() async {
    final engine = await loadEngine();
    final model = await loadMImageModel();
    final family = await loadCoreMLFamily();
    final variant = await loadCoreMLVariant(family);
    final prefs = await SharedPreferences.getInstance();
    final revision = prefs.getInt('realsr_mimage_revision_${model.id}') ?? 0;
    final desktopScale = await loadScale();
    return SuperResolutionProfile(
      engine: engine,
      mimageModel: model,
      coremlVariant: variant,
      desktopScale: desktopScale.value,
      cacheKey: await _cacheKeyFor(engine, variant, model, revision),
    );
  }

  /// 引擎 → 缓存指纹。**指纹格式必须与改动前逐字节一致**，否则老用户已生成的
  /// `sr_*_<key>.png` 超分缓存会整体作废、被重新推理一遍。
  static Future<String> _cacheKeyFor(
    SuperResolutionEngine engine,
    CoreMLModelVariant variant,
    MImageOnnxModel model,
    int revision,
  ) async {
    switch (engine) {
      case SuperResolutionEngine.breezeCoreML:
        return 'breeze_coreml_${variant.fileName}_${variant.config['scale']}x';
      case SuperResolutionEngine.mimageOnnx:
        return 'mimage_onnx_${model.id}_$revision';
      case SuperResolutionEngine.desktopNcnn:
        final mode = await loadDesktopNcnnMode();
        final noise = await loadDesktopNcnnNoise();
        final scale = await loadScale();
        return '${mode.name}_noise${noise.noise}_${scale.value}x';
    }
  }

  static Future<void> modelFileChanged(MImageOnnxModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'realsr_mimage_revision_${model.id}',
      DateTime.now().microsecondsSinceEpoch,
    );
    notifyChanges();
  }

  static const _keyAutoUpscale = 'realsr_auto_upscale';
  static const _keyResolutionThreshold = 'realsr_resolution_threshold';
  static const _keyConcurrency = 'realsr_concurrency';
  static const _keyNoiseLevel = 'realsr_noise_level';
  static const _keyTileSize = 'realsr_tile_size';
  static const _keyCoreMLFamily = 'realsr_coreml_family';
  static const _keyCoreMLVariant = 'realsr_coreml_variant';
  static const _keyAndroidNcnnMode = 'realsr_android_ncnn_mode';
  static const _keyAndroidNcnnNoise = 'realsr_android_ncnn_noise';
  static const _keyDesktopNcnnMode = 'realsr_desktop_ncnn_mode';
  static const _keyDesktopNcnnNoise = 'realsr_desktop_ncnn_noise';
  static const _keyScale = 'realsr_scale';
  static const _keyMImageModel = 'realsr_mimage_onnx_model';

  /// 根据当前运行平台返回推荐的默认并发数。
  ///
  /// - 桌面端（Windows / Linux / macOS）：2
  /// - 移动设备（Android / iOS）：1
  static int get defaultConcurrency {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return 2;
    if (Platform.isAndroid || Platform.isIOS) return 1;
    return 1;
  }

  /// 给定平台形态时可选的阈值档位。纯函数，[isDesktop] 显式传入是为了能在
  /// 任意平台上验证**移动分支**（桌面机器只能跑到桌面那一支）。
  static List<RealSrResolutionThreshold> availableThresholdsFor({
    required bool isDesktop,
  }) => isDesktop
      ? RealSrResolutionThreshold.values
      : const [
          RealSrResolutionThreshold.p540,
          RealSrResolutionThreshold.p720,
          RealSrResolutionThreshold.p1080,
        ];

  /// 当前平台可选的阈值档位。
  static List<RealSrResolutionThreshold> get availableThresholds =>
      availableThresholdsFor(isDesktop: _isDesktop);

  /// 把存储值夹进本平台上限，与 [loadResolutionThreshold] 的夹取规则同源。
  ///
  /// 设置页与阅读器面板**必须**用同一个结果：两处各算一遍的话，
  /// 迟早会出现「下拉显示 1080、写回的却是 2160」这种看起来没生效的怪象。
  static RealSrResolutionThreshold effectiveThreshold(
    RealSrResolutionThreshold stored, {
    bool? isDesktop,
  }) {
    final available = availableThresholdsFor(
      isDesktop: isDesktop ?? _isDesktop,
    );
    return available.contains(stored) ? stored : available.last;
  }

  static Future<bool> loadAutoUpscale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoUpscale) ?? false;
  }

  static Future<void> saveAutoUpscale(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoUpscale, value);
  }

  static Future<RealSrResolutionThreshold> loadResolutionThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyResolutionThreshold);
    final value = RealSrResolutionThreshold.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RealSrResolutionThreshold.p720,
    );

    // 桌面端最高 2160p，移动设备最高 1080p
    const desktopMax = RealSrResolutionThreshold.p2160;
    const mobileMax = RealSrResolutionThreshold.p1080;
    final max = _isDesktop ? desktopMax : mobileMax;
    if (value.maxWidth > max.maxWidth) {
      return max;
    }

    return value;
  }

  static Future<void> saveResolutionThreshold(
    RealSrResolutionThreshold value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyResolutionThreshold, value.name);
  }

  static Future<int> loadConcurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyConcurrency) ?? defaultConcurrency;
  }

  static Future<void> saveConcurrency(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyConcurrency, value);
  }

  static Future<int> loadTileSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTileSize) ?? 256;
  }

  static Future<void> saveTileSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTileSize, value);
  }

  static Future<RealSrNoiseLevel> loadNoiseLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyNoiseLevel);
    return RealSrNoiseLevel.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RealSrNoiseLevel.conservative,
    );
  }

  static Future<void> saveNoiseLevel(RealSrNoiseLevel value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNoiseLevel, value.name);
  }

  /// iOS / macOS 使用的 CoreML 模型族，默认 waifu2x（速度优先）。
  static Future<CoreMLModelFamily> loadCoreMLFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyCoreMLFamily);
    return CoreMLModelConfig.familyById(id ?? '') ??
        CoreMLModelConfig.defaultFamily;
  }

  static Future<void> saveCoreMLFamily(CoreMLModelFamily value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCoreMLFamily, value.id);
    notifyChanges();
  }

  /// iOS / macOS 使用的 CoreML 模型变体。
  ///
  /// 如果保存的变体不在当前族中，自动回退到该族第一个变体。
  static Future<CoreMLModelVariant> loadCoreMLVariant(
    CoreMLModelFamily family,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final fileName = prefs.getString(_keyCoreMLVariant);
    return CoreMLModelConfig.variantByFileName(family, fileName ?? '') ??
        family.variants.first;
  }

  static Future<void> saveCoreMLVariant(CoreMLModelVariant value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCoreMLVariant, value.fileName);
    notifyChanges();
  }

  /// Android 使用的 NCNN 超分模式，默认效率优先（waifu2x）。
  static Future<AndroidNcnnMode> loadAndroidNcnnMode() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyAndroidNcnnMode);
    return AndroidNcnnMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AndroidNcnnModelConfig.defaultMode,
    );
  }

  static Future<void> saveAndroidNcnnMode(AndroidNcnnMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAndroidNcnnMode, value.name);
  }

  /// Android 使用的 NCNN 降噪档位，默认无降噪（适合漫画）。
  static Future<AndroidNcnnNoise> loadAndroidNcnnNoise() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyAndroidNcnnNoise);
    return AndroidNcnnNoise.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AndroidNcnnModelConfig.defaultNoise,
    );
  }

  static Future<void> saveAndroidNcnnNoise(AndroidNcnnNoise value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAndroidNcnnNoise, value.name);
  }

  /// 桌面端（Windows / Linux）使用的 NCNN 超分模式。
  static Future<AndroidNcnnMode> loadDesktopNcnnMode() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyDesktopNcnnMode);
    return AndroidNcnnMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AndroidNcnnModelConfig.defaultMode,
    );
  }

  static Future<void> saveDesktopNcnnMode(AndroidNcnnMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDesktopNcnnMode, value.name);
  }

  /// 桌面端（Windows / Linux）使用的 NCNN 降噪档位。
  static Future<AndroidNcnnNoise> loadDesktopNcnnNoise() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyDesktopNcnnNoise);
    return AndroidNcnnNoise.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AndroidNcnnModelConfig.defaultNoise,
    );
  }

  static Future<void> saveDesktopNcnnNoise(AndroidNcnnNoise value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDesktopNcnnNoise, value.name);
  }

  static Future<RealSrScale> loadScale() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyScale);
    return RealSrScale.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RealSrScale.x2,
    );
  }

  static Future<void> saveScale(RealSrScale value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyScale, value.value);
  }

  static Future<MImageOnnxModel> loadMImageModel() async {
    final prefs = await SharedPreferences.getInstance();
    final model =
        MImageOnnxModelConfig.byId(prefs.getString(_keyMImageModel)) ??
        MImageOnnxModelConfig.defaultModel;
    _currentMImageModel = model;
    return model;
  }

  static Future<void> saveMImageModel(MImageOnnxModel value) async {
    _currentMImageModel = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMImageModel, value.id);
    _modelChanges.notify();
  }

  /// 用于超分结果缓存的配置指纹。模型或倍率改变时必须得到不同的文件名，
  /// 否则会继续显示旧模型产物，看起来就像“换模型没有生效”。
  ///
  /// 指纹一律由**引擎**决定而不是平台决定：Windows/Linux 现在两种引擎都有，
  /// 按平台分叉会让 `loadProfile().cacheKey` 与这里算出两个值。
  static Future<String> loadCacheKey() async {
    if (hasSuperResolutionEngineChoice) {
      return (await loadProfile()).cacheKey;
    }
    // Android：内置 waifu2x CLI，没有引擎选择，指纹仍由 NCNN 模式/降噪/倍率决定。
    final mode = await loadAndroidNcnnMode();
    final noise = await loadAndroidNcnnNoise();
    final scale = await loadScale();
    return '${mode.name}_noise${noise.noise}_${scale.value}x';
  }
}
