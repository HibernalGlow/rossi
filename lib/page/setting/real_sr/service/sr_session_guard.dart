import 'dart:io';

import 'package:coreml_upscale/coreml_upscale.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/src/rust/api/mimage_onnx.dart' as onnx;

/// 超分两条**原生引擎**的模型会话「持有记账」与统一交还口。
///
/// 为什么要记账：`LocalReadSession.dispose`（离开阅读器）要把常驻的模型
/// 交还给系统，但「没建过会话的进程」不该为此白过桥 / 白发一次
/// MethodChannel（与 `OcrService._sessionsHeld` 同一个理由，同同一口径）。
///
/// 两条各自记账：
/// - **ONNX**（Rust 侧 `mimage_onnx.rs` 的 `SESSIONS`）：CoreML / DirectML
///   的会话每个几十到几百 MB，之前加载后终身常驻 —— 现在除了 Rust 侧自己的
///   10 分钟空闲清扫，退出阅读器时在这里主动交还；
/// - **CoreML 插件**（Swift `ModelManager.imageModelCache`）：同理，
///   之前 `clearCache()` 是死代码，现在经 `releaseModels` 透传到这里。
///
/// 交还的是**内存里的模型**；磁盘上的编译产物（`.coreml_cache` /
/// `CompiledModelCache`）不受影响，重载不需要重新编译。
abstract final class SrSessionGuard {
  static bool _onnxHeld = false;
  static bool _coremlHeld = false;

  /// ONNX 侧即将建会话（或已建）时打标记。
  static void markOnnxHeld() => _onnxHeld = true;

  /// CoreML 插件即将加载模型时打标记。
  static void markCoremlHeld() => _coremlHeld = true;

  /// 交还所有还持有的会话。没有就什么也不做 —— 所以任何调用点都不必判断
  /// 「这一程到底用没用超分」。
  static Future<void> release() async {
    if (_onnxHeld) {
      _onnxHeld = false;
      try {
        final freed = await onnx.mimageOnnxReleaseSessions();
        if (freed > BigInt.zero) {
          logger.i('mImage ONNX 会话已交还（$freed 字节模型）');
        }
      } catch (e) {
        // 交还是「锦上添花」的回收：失败不影响阅读会话本身的关闭。
        logger.w('mImage ONNX 会话交还失败', error: e);
      }
    }
    if (_coremlHeld && (Platform.isIOS || Platform.isMacOS)) {
      _coremlHeld = false;
      try {
        await CoreMLUpscale.releaseModels();
      } catch (e) {
        logger.w('CoreML 模型交还失败', error: e);
      }
    }
  }
}
