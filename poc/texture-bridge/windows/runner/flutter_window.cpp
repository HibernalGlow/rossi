#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "gpu_texture_poc.h"
#include "wgpu_texture_poc.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // === Gate A / 风险 1 ===
  // 用原生 D3D12 造一张 shared texture，注册成 Flutter 的外部 texture。
  // 这里刻意不接 wgpu —— 先把「Flutter 侧通道能不能工作」这个独立风险单独
  // 验证掉，再谈「wgpu 能否导出 handle」那一半。
  flutter::FlutterEngine* engine = flutter_controller_->engine();
  FlutterDesktopPluginRegistrarRef registrar =
      engine->GetRegistrarForPlugin("rossi_texture_bridge_poc");
  FlutterDesktopTextureRegistrarRef texture_registrar =
      registrar != nullptr ? FlutterDesktopRegistrarGetTextureRegistrar(registrar)
                           : nullptr;
  if (texture_registrar != nullptr) {
    auto poc = std::make_unique<GpuTexturePoc>(engine, texture_registrar);
    if (poc->ok() && poc->Register()) {
      gpu_texture_poc_ = std::move(poc);
    } else {
      // 不中断启动：窗口照常显示，错误原因由 Dart 侧 getStats 读出来。
      OutputDebugStringA("GpuTexturePoc 初始化失败: ");
      OutputDebugStringA(poc->error().c_str());
      OutputDebugStringA("\n");
    }

    // === Gate A / 风险 2 ===
    // Rust/wgpu 探针：wgpu 渲染 → 同 device 上 GPU 拷贝到 SHARED 纹理 →
    // 导出 DXGI handle 交给引擎。构造里会加载 wgpu_probe.dll 并跑完整初始化，
    // 首次还要经 DXC 编译 WGSL，可能要几百毫秒。
    auto wgpu_poc = std::make_unique<WgpuTexturePoc>(engine, texture_registrar);
    if (wgpu_poc->ok() && wgpu_poc->Register()) {
      wgpu_texture_poc_ = std::move(wgpu_poc);
    } else {
      OutputDebugStringA("WgpuTexturePoc 初始化失败: ");
      OutputDebugStringA(wgpu_poc->error().c_str());
      OutputDebugStringA("\n");
    }
  } else {
    OutputDebugStringA("无法获取 Flutter texture registrar\n");
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 先销毁两个 PoC：它们会注销外部 texture，必须在 Flutter engine 仍然活着时完成。
  // wgpu 那个还要在卸载 DLL 前把自己的 D3D12/wgpu 资源释放干净。
  wgpu_texture_poc_.reset();
  gpu_texture_poc_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
