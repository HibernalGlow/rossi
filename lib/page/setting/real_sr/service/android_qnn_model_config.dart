import 'package:zephyr/i18n/strings.g.dart';

/// Android QNN（Qualcomm HTP NPU）超分模型。
///
/// 模型名与 FP16 DLC 文件（`<id>.dlc`）及 manifest.json 的键一一对应，
/// 产物来自上游 mihon_img_upscale 的模型管线（QAIRT 2.49.0 FP16 转换），
/// 由 Rossi 首次使用时下载，不随 APK 打包。
///
/// `padding` 是模型 prepadding（推理输入块的边缘裁剪量），与上游
/// `Waifu2x.kt` 的取值一致：Real-CUGAN SE/Pro 2x 均为 18。
enum AndroidQnnModel {
  seX2NoDenoise._(
    id: 'realcugan-se-x2-no-denoise',
    scale: 2,
    padding: 18,
    isPro: false,
  ),
  proX2Denoise3x._(
    id: 'realcugan-pro-x2-denoise3x',
    scale: 2,
    padding: 18,
    isPro: true,
  );

  const AndroidQnnModel._({
    required this.id,
    required this.scale,
    required this.padding,
    required this.isPro,
  });

  /// 模型名，同时是 `<id>.dlc` 文件名与 manifest.json 的键。
  final String id;

  /// 输出倍率（用于产物尺寸校验）。
  final int scale;

  /// 模型 prepadding，透传给原生层。
  final int padding;

  /// Real-CUGAN Pro 家族：仅 Pro + 单色源启用网点纹理防护方案（上游同口径）。
  final bool isPro;

  String get label => switch (this) {
    AndroidQnnModel.seX2NoDenoise => t.realSr.qnnModelSeX2NoDenoise,
    AndroidQnnModel.proX2Denoise3x => t.realSr.qnnModelProX2Denoise3x,
  };
}

abstract class AndroidQnnModelConfig {
  AndroidQnnModelConfig._();

  /// 阶段一默认模型：SE 2x 无降噪，先验证干净漫画的线条与文字细节。
  static const AndroidQnnModel defaultModel = AndroidQnnModel.seX2NoDenoise;

  static AndroidQnnModel? byId(String? id) {
    if (id == null) return null;
    return AndroidQnnModel.values.where((model) => model.id == id).firstOrNull;
  }

  /// 模型下载包名（`<super_resolution>/qnn/` 目录的 7z 压缩包）。
  static const String archiveName = 'realsr-qnn-android.7z';

  /// QNN 模型压缩包的托管仓库。
  ///
  /// 与 NCNN 模型的 `deretame/breeze-binary` 分开：那是上游作者的仓库，
  /// 本仓无推送权；QNN 模型走本仓自己的托管（创建后把
  /// `script/models/package_qnn_models.py` 产出的 7z 传上去）。
  static const String binaryRepoBaseUrl =
      'https://github.com/HibernalGlow/breeze-binary/raw/main';

  static String get archiveUrl => '$binaryRepoBaseUrl/$archiveName';

  /// DLC 子目录名（相对 `getFilePath()/super_resolution/`）。
  static const String dlcDirName = 'qnn';
}
