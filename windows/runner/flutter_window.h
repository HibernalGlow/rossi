#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "gpu_present_bridge.h"
#include "win32_window.h"

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

  // GPU 呈现桥（Windows / D3D12 共享纹理）。
  //
  // 为什么它住在 runner 而不是 plugins/：Flutter 的纹理注册需要
  // `FlutterDesktopTextureRegistrarRef`，而应用项目拿它的最直接方式就是
  // `engine->GetRegistrarForPlugin(...)`。放进插件包会为了"形式上的整洁"
  // 多一层 pub 包与 CMake 注入，收益为零。
  //
  // 构造失败（例如构建产物里没有 rossi_gpu_present.dll）**不阻断启动**，
  // 只是这条上屏路径不可用；原因会通过 method channel 报给 Dart 侧显示。
  std::unique_ptr<GpuPresentBridge> gpu_present_bridge_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
