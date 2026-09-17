#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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

  // === GPU 上屏路径（Windows / D3D12 共享纹理）===
  //
  // 契约：本桥只负责"把句柄交给引擎"与"通知引擎来取帧"，
  // 像素由 Rust 侧的 rossi_gpu_present.dll 从解码到上屏全程不经 CPU。
  //
  // 用 `GetRegistrarForPlugin` 而不是 `PluginRegistrarManager`：
  // 后者要引入 cpp_client_wrapper 的额外头文件，而 registrar 只需一个名字，
  // 名字本身不参与任何查找逻辑（Flutter 对应用自有 registrar 一律返回有效值）。
  {
    flutter::FlutterEngine* engine = flutter_controller_->engine();
    FlutterDesktopPluginRegistrarRef registrar =
        engine->GetRegistrarForPlugin("rossi_gpu_present");
    FlutterDesktopTextureRegistrarRef texture_registrar =
        registrar != nullptr ? FlutterDesktopRegistrarGetTextureRegistrar(registrar) : nullptr;

    if (texture_registrar != nullptr) {
      // 这一步**不再等呈现器建好**：Rust 侧的 `create` 只起线程就返回，
      // wgpu device 与渲染管线在后台 ~1 s 建好。所以下面之后的第一帧不受它影响。
      // 就绪之前 Dart 侧走 CPU 兜底路径 —— 见 `gpu_present_bridge.h` 的说明。
      auto bridge = std::make_unique<GpuPresentBridge>(engine, texture_registrar);
      // ok() 为假时**不要**调 Register()：那种情况下它只会立刻返回 false，
      // 真正的原因（DLL 没构建、显卡不支持、registrar 拿不到……）已经在 error() 里了。
      //
      // 注意 `ok()` 不再等于"呈现器可用"，只等于"这条路径有实现" ——
      // 注册纹理本身很廉价，也不依赖呈现器已就绪。
      const bool registered = bridge->ok() && bridge->Register();
      if (!registered) {
        // 不中断启动：窗口照常显示，原因由 Dart 侧读 `stats` 显示在页面上。
        // 这里只再留一条调试输出 —— "为什么黑屏"不该只有挂调试器才看得到。
        OutputDebugStringA("GpuPresentBridge 初始化失败: ");
        OutputDebugStringA(bridge->error().c_str());
        OutputDebugStringA("\n");
      }
      // 失败也保留这个对象：构造函数会把 MethodChannel 先建好，所以即便
      // 呈现器不可用，Dart 侧仍能读到失败原因，而不是收到一个无解释的异常。
      gpu_present_bridge_ = std::move(bridge);
    } else {
      OutputDebugStringA("无法获取 Flutter texture registrar\n");
    }
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {

  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 必须先拆 GPU 呈现桥再拆 Flutter controller：
  // 桥的析构会调用 `FlutterDesktopTextureRegistrarUnregisterExternalTexture` 注销纹理，
  // 那需要 engine 仍然活着；反过来 engine 先没了，注销就落在空 engine 上。
  // 桥自己还持有 wgpu / D3D12 资源，它们的析构函数在 rossi_gpu_present.dll 里，
  // 所以顺序只能是：注销纹理 → 析构桥 → 卸载 DLL。
  gpu_present_bridge_.reset();

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
