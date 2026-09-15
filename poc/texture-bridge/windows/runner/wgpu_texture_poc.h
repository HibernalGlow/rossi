#ifndef RUNNER_WGPU_TEXTURE_POC_H_
#define RUNNER_WGPU_TEXTURE_POC_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

// Gate A / 风险 2 验证层：wgpu 渲染结果 → DXGI shared handle → Flutter 合成。
//
// 与 GpuTexturePoc（风险 1）的分工很清楚：
//   风险 1 证明「Flutter 侧的 texture 通道可用」—— 渲染是这一侧手写的 D3D12；
//   风险 2 证明「wgpu 能接进这条通道」—— 渲染与导出全在 Rust 侧的 wgpu 探针里，
//   本类只做三件事：加载 wgpu_probe.dll、注册外部 texture、把句柄转交引擎。
//
// 为什么渲染不在这一侧做：wgpu 的 Device 和它创建的 texture 都活在 Rust 侧。
// 要把结果导出成 shareable 资源，必须在**同一个 ID3D12Device** 上操作
// （跨 device 共享要么失败要么掉进极慢路径），所以拷贝也只能在 Rust 侧完成。
class WgpuTexturePoc {
 public:
  WgpuTexturePoc(flutter::FlutterEngine* engine,
                 FlutterDesktopTextureRegistrarRef texture_registrar);
  ~WgpuTexturePoc();

  // 注册外部 texture。构造后、渲染前调用一次。
  bool Register();

  // 渲染一帧（wgpu 渲染 + GPU→GPU 拷贝到共享纹理）并通知引擎来取。
  bool RenderFrame(float phase);

  // 按当前尺寸强制重建，验证销毁 / 重建路径。
  bool ForceRecreate();

  int64_t texture_id() const { return texture_id_; }
  bool ok() const { return ok_; }
  const std::string& error() const { return error_; }

 private:
  // ── DLL 导出的 C ABI ──
  // 用 LoadLibrary 动态加载而不是链接 import lib，避免 build 顺序耦合。
  using CreateFn = void* (*)(uint64_t, uint32_t, uint32_t, uint8_t*, size_t);
  using HandleFn = void* (*)(void*);
  using RenderFn = int32_t (*)(void*, float);
  using ResizeFn = void* (*)(void*, uint32_t, uint32_t);
  using RecreateFn = void* (*)(void*);
  using StatsFn = int32_t (*)(void*, uint8_t*, size_t);
  using DestroyFn = void (*)(void*);

  static const FlutterDesktopGpuSurfaceDescriptor* SurfaceCallback(
      size_t width, size_t height, void* user_data);
  static void OnHandleOpened(void* release_context);

  bool LoadProbeLibrary();
  void SetError(const std::string& message);

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                            result);
  flutter::EncodableMap BuildStats();

  flutter::FlutterEngine* engine_ = nullptr;
  FlutterDesktopTextureRegistrarRef texture_registrar_ = nullptr;
  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  HMODULE library_ = nullptr;
  CreateFn create_ = nullptr;
  HandleFn get_handle_ = nullptr;
  RenderFn render_ = nullptr;
  ResizeFn resize_ = nullptr;
  RecreateFn recreate_ = nullptr;
  StatsFn stats_ = nullptr;
  DestroyFn destroy_ = nullptr;

  void* probe_ = nullptr;
  void* shared_handle_ = nullptr;
  UINT width_ = 0;
  UINT height_ = 0;
  uint64_t adapter_luid_ = 0;
  bool luid_known_ = false;

  // descriptor 必须长期有效：引擎会一直持有这个指针，直到下一次 callback。
  FlutterDesktopGpuSurfaceDescriptor descriptor_ = {};

  mutable std::mutex mutex_;

  bool ok_ = false;
  std::string error_;
  uint32_t recreate_count_ = 0;
  uint32_t handle_opened_count_ = 0;
  uint64_t frame_count_ = 0;
  std::string last_probe_stats_ = "{}";
};

#endif  // RUNNER_WGPU_TEXTURE_POC_H_
