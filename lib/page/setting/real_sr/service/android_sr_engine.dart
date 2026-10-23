import 'package:zephyr/i18n/strings.g.dart';

/// Android 超分引擎选择。
///
/// Rossi 在 Android 上有两条互不相干的后端：
/// - **vulkan**：外部 waifu2x CLI 进程（`libwaifu2x_cli.so`，ncnn + Vulkan），
///   一直以来的默认路线；
/// - **qnnNpu**：进程内 JNI 的 Qualcomm QNN / HTP NPU 推理（`librealsr_qnn.so`，
///   移植自 mihon_img_upscale）。
///
/// 显式选择 NPU 时失败**不回退**到 Vulkan：如实报错并保留原图，与上游
/// mihon_img_upscale 的语义一致（静默回退会让用户误以为 NPU 已生效）。
enum AndroidSuperResolutionEngine {
  vulkan('realsr_android_vulkan'),
  qnnNpu('realsr_android_qnn');

  const AndroidSuperResolutionEngine(this.id);

  /// SharedPreferences 存储值。
  final String id;

  String get label => switch (this) {
    AndroidSuperResolutionEngine.vulkan => t.realSr.androidEngineVulkan,
    AndroidSuperResolutionEngine.qnnNpu => t.realSr.androidEngineQnnNpu,
  };

  String get subtitle => switch (this) {
    AndroidSuperResolutionEngine.vulkan => t.realSr.androidEngineVulkanSubtitle,
    AndroidSuperResolutionEngine.qnnNpu => t.realSr.androidEngineQnnNpuSubtitle,
  };
}

/// 默认引擎保持 Vulkan：NPU 后端处于实验阶段（体积代价、设备面与画质
/// 都待实测验证），不替所有现有用户改默认行为。
const AndroidSuperResolutionEngine defaultAndroidSuperResolutionEngine =
    AndroidSuperResolutionEngine.vulkan;

AndroidSuperResolutionEngine? androidEngineById(String? id) {
  if (id == null) return null;
  return AndroidSuperResolutionEngine.values
      .where((engine) => engine.id == id)
      .firstOrNull;
}
