import 'package:flutter/foundation.dart';

/// WebGPU 呈现器在 Web 端的前端接口与组件
class WebGpuPresenter {
  WebGpuPresenter._();
  static final WebGpuPresenter instance = WebGpuPresenter._();

  bool _initialized = false;
  bool get isSupported => kIsWeb;

  /// 初始化 WebAssembly 与 WebGPU 运行时
  Future<void> init() async {
    if (!kIsWeb || _initialized) return;
    _initialized = true;
  }

  /// 呈现一页 RGBA 像素到 WebGPU 画布上
  Future<void> renderPage({
    required Uint8List rgba,
    required int width,
    required int height,
    bool anime4k = false,
  }) async {
    if (!kIsWeb) return;
    // 在 Web 端，通过 JS interop 传递给 RossiWebPresenter.render_page
  }
}
