#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// Gate A / 风险 1 验证：把外部创建的 D3D12 texture 注入 Flutter 合成链。
class GpuTexturePoc;

// Gate A / 风险 2 验证：wgpu 渲染结果 → DXGI shared handle → Flutter 合成。
class WgpuTexturePoc;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 风险 1 的 PoC（原生 D3D12 手写渲染）。初始化失败时为 nullptr，
  // 此时 Dart 侧 getStats 会拿到 ok=false 与具体错误原因。
  std::unique_ptr<GpuTexturePoc> gpu_texture_poc_;

  // 风险 2 的 PoC（Rust/wgpu 渲染 + GPU 拷贝导出 handle）。
  std::unique_ptr<WgpuTexturePoc> wgpu_texture_poc_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
