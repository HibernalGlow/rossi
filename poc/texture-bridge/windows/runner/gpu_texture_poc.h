#ifndef RUNNER_GPU_TEXTURE_POC_H_
#define RUNNER_GPU_TEXTURE_POC_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>

#include <d3d12.h>
// EnumAdapterByGpuPreference / DXGI_GPU_PREFERENCE_* 属于 IDXGIFactory6，
// 需要 dxgi1_6.h（dxgi1_4.h 里没有这两个符号）。
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Gate A / 风险 1 验证工程。
//
// 目的：证明 Flutter Windows embedder 能否收下一张「外部创建的 D3D12 texture」，
// 并把它正确合成为屏幕上的像素。
//
// 关键设计：这里**刻意不使用 wgpu**。只用原生 D3D12 造一张 shared texture，
// 以便把两个互相独立的风险分开：
//   风险 1 = Flutter 侧 texture 通道是否可用          （本文件验证）
//   风险 2 = wgpu 能否把渲染结果导出成 DXGI shared handle（后续验证）
//
// 渲染内容只用 ClearRenderTargetView（带 rect），不引入 shader / PSO，
// 把变量压到最少：
//   - 顶部三条纯色带（红/绿/蓝）用来一眼验证 BGRA 通道有没有搞反；
//   - 中部一个随 phase 左右移动的方块，用来验证帧在持续更新而不是只画一次；
//   - 背景纯色，用来验证不是黑屏/花屏。
class GpuTexturePoc {
 public:
  GpuTexturePoc(flutter::FlutterEngine* engine,
                FlutterDesktopTextureRegistrarRef texture_registrar);
  ~GpuTexturePoc();

  // 注册外部 texture。必须在构造后、渲染前调用一次。
  bool Register();

  // 渲染一帧并通知引擎来取。
  bool RenderFrame(float phase);

  // 按当前尺寸重建 texture，用于验证销毁/重建路径。
  bool ForceRecreate();

  int64_t texture_id() const { return texture_id_; }
  bool ok() const { return ok_; }
  const std::string& error() const { return error_; }

 private:
  // 延迟释放的旧资源。
  //
  // 重建 texture 时不能立即 Release 旧的：引擎可能仍持有由旧 handle 打开的
  // 合成纹理。这里退一步，把旧资源挪进 retired_，等下一次 callback 再回收。
  // 这是 PoC 的已知薄弱点，正式实现应改为基于 release_callback 的引用计数。
  struct RetiredResource {
    Microsoft::WRL::ComPtr<ID3D12Resource> resource;
    HANDLE handle = nullptr;
  };

  static const FlutterDesktopGpuSurfaceDescriptor* SurfaceCallback(
      size_t width, size_t height, void* user_data);
  static void OnHandleOpened(void* release_context);

  bool InitDevice();
  bool CreateSizeDependentResources(UINT width, UINT height);
  void ReleaseSizeDependentResources();
  void ReclaimRetiredResources();
  void SetError(const std::string& message);

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                            result);
  flutter::EncodableMap BuildStats() const;

  flutter::FlutterEngine* engine_ = nullptr;
  FlutterDesktopTextureRegistrarRef texture_registrar_ = nullptr;
  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // D3D12 固定开销部分。
  Microsoft::WRL::ComPtr<IDXGIFactory6> factory_;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter_;
  Microsoft::WRL::ComPtr<ID3D12Device> device_;
  Microsoft::WRL::ComPtr<ID3D12CommandQueue> queue_;
  Microsoft::WRL::ComPtr<ID3D12CommandAllocator> allocator_;
  Microsoft::WRL::ComPtr<ID3D12GraphicsCommandList> command_list_;
  Microsoft::WRL::ComPtr<ID3D12Fence> fence_;
  HANDLE fence_event_ = nullptr;
  UINT64 fence_value_ = 0;

  // 随尺寸变化的资源。
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> rtv_heap_;
  Microsoft::WRL::ComPtr<ID3D12Resource> texture_;
  D3D12_CPU_DESCRIPTOR_HANDLE rtv_ = {};
  HANDLE shared_handle_ = nullptr;
  UINT width_ = 0;
  UINT height_ = 0;

  // descriptor 必须长期有效：引擎会一直持有这个指针，直到下一次 callback。
  FlutterDesktopGpuSurfaceDescriptor descriptor_ = {};

  std::vector<RetiredResource> retired_;
  mutable std::mutex mutex_;

  bool ok_ = false;
  std::string error_;
  std::string adapter_name_ = "(unknown)";
  bool using_flutter_adapter_ = false;
  uint32_t recreate_count_ = 0;
  uint32_t handle_opened_count_ = 0;
  uint64_t frame_count_ = 0;
  float last_phase_ = 0.0f;
};

#endif  // RUNNER_GPU_TEXTURE_POC_H_
