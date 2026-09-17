#ifndef RUNNER_GPU_PRESENT_BRIDGE_H_
#define RUNNER_GPU_PRESENT_BRIDGE_H_

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

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Rossi GPU 呈现桥（Windows）。
//
// # 职责边界
//
// 这一层**不做任何像素工作**。它只做三件事：
//   1. 把 Rust 侧（`rossi_gpu_present.dll`）导出的共享句柄交给 Flutter 的 texture registrar；
//   2. 把引擎请求的尺寸转告给 Rust（尺寸变了就让 Rust 重建目标并换句柄）；
//   3. 把 Dart 的方法调用转给 Rust，并在 Rust 放好像素之后通知引擎来取这一帧。
//
// 像素从解码到上屏全程既不过这一层，也不经过 Dart。
//
// # 为什么用 LoadLibrary 而不是 import lib
//
// 与 Gate A 的 PoC 同一条路子：免得把 CMake 的链接顺序和 cargo 的构建顺序耦在一起。
// 而且本 DLL 是 Windows 专属产物，其他平台根本不生成，用 import lib 会逼着
// CMake 在每个平台都做一次存在性判断。
//
// # 失败不阻断启动
//
// 构造函数里任何一步失败（没 cargo 构建产物、显卡不支持、注册纹理失败）都只把原因
// 记进 `error()`，窗口照常显示。Dart 侧读 `stats` 就能看到为什么不可用 ——
// 这比"启动即崩"或"黑屏但没提示"都好。
//
// # 呈现器是异步建的：所以状态有三个，不是两个
//
// Rust 侧的 `create` 只起线程、立刻返回，真正的 wgpu device 与渲染管线在后台
// ~1 s 建好（它要是在这里同步做，就会压在第一帧之前、直接吃冷启动预算）。
//
// 于是本桥的状态是 **loading / ready / failed** 三态：
// - `loading`：还在建。调用方此刻该走 CPU 兜底路径，并且**不该**挂 `Texture`；
// - `ready`：可以拿句柄上屏；
// - `failed`：这条路走不通了，兜底是终点。
//
// 把 loading 和 failed 合成一个"还没好"是不行的：一个该等、一个该放弃，
// 而调用方没法从"还没好"里分辨是哪一个。
//
// 状态每次现问（`QueryStateLocked`），不在 C++ 侧缓存 —— 见那里的说明。
class GpuPresentBridge {
 public:
  GpuPresentBridge(flutter::FlutterEngine* engine,
                   FlutterDesktopTextureRegistrarRef texture_registrar);
  ~GpuPresentBridge();

  // 注册外部纹理。曾在构造中做会有一个问题：注册时引擎马上就可能回调
  // SurfaceCallback，而那时 `this` 还没交出去给调用方保存。所以拆成显式一步。
  bool Register();

  bool ok() const { return ok_; }
  const std::string& error() const { return error_; }
  int64_t texture_id() const { return texture_id_; }

 private:
  // ── rossi_gpu_present.dll 的 C ABI ──
  //
  // 类型必须与 `rust/gpu_present/src/lib.rs` 逐字对应。这里手写而不生成头文件，
  // 是因为接口只有 10 个函数且不常变；代价是改名时两边都要动 ——
  // 符号名统一以 `rossi_gpu_present_` 开头就是为了让这种错配一眼可见。
  using CreateFn = void* (*)(uint64_t adapter_luid, uint32_t width, uint32_t height,
                             uint8_t* err_buf, size_t err_len);
  using DestroyFn = void (*)(void* presenter);
  using HandleFn = void* (*)(void* presenter);
  using GenerationFn = uint64_t (*)(void* presenter);
  using NotifyReleasedFn = void (*)(void* presenter, uint64_t generation);
  using ResizeFn = void* (*)(void* presenter, uint32_t width, uint32_t height,
                             uint8_t* err_buf, size_t err_len);
  using OpenFn = int32_t (*)(void* presenter, const uint8_t* path, size_t path_len,
                             uint8_t* err_buf, size_t err_len);
  using PageCountFn = int32_t (*)(void* presenter);
  using ShowFn = int32_t (*)(void* presenter, uint32_t index, uint8_t* err_buf,
                             size_t err_len);
  using StatsFn = int32_t (*)(void* presenter, uint8_t* buf, size_t len);
  // 查后台创建进度。它是唯一一个"不要求呈现器已就绪"的入口 —— 正相反，
  // 它存在的全部意义就是回答"就绪了没有"，所以在未就绪时它必须能调。
  using StatusFn = int32_t (*)(void* presenter, uint8_t* err_buf, size_t err_len);

  static const FlutterDesktopGpuSurfaceDescriptor* SurfaceCallback(size_t width,
                                                                  size_t height,
                                                                  void* user_data);
  // 引擎在**打开句柄之后**回调。`release_context` 里塞的是代际号（不是 this）——
  // 理由见 cpp 里 `kReleaseContextIsGeneration` 附近的说明。
  static void OnHandleOpened(void* release_context);

  bool LoadSymbols();
  // 向 Rust 问当前就绪状态。**调用方必须已持有 `mutex_`。**
  //
  // 不缓存结果：这个状态是在后台线程上改变的，在 C++ 侧存一份就等于多了一份
  // 会过期的真相。它已经足够便宜（拿锁 + 读一个枚举 + 可能拷一段错误文本），
  // 而调用点只有 `init` / `status` / `stats` / `SurfaceCallback` 四处。
  int32_t QueryStateLocked(std::string* error);
  // 让 Rust 侧的呈现目标与引擎请求的尺寸一致。返回是否可用。
  bool SyncTarget(uint32_t width, uint32_t height);
  void RefreshDescriptor();

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::EncodableMap BuildStats();

  flutter::FlutterEngine* engine_ = nullptr;
  FlutterDesktopTextureRegistrarRef texture_registrar_ = nullptr;

  HMODULE library_ = nullptr;
  void* presenter_ = nullptr;
  CreateFn create_ = nullptr;
  DestroyFn destroy_ = nullptr;
  HandleFn handle_ = nullptr;
  // 函数指针一律带 `_fn` 后缀：`generation_` 这个名字下面还占着一个**值**
  // （当前句柄的代际号），两者同名会直接编译失败（C2373 重定义、类型修饰符不同）。
  GenerationFn generation_fn_ = nullptr;
  NotifyReleasedFn notify_released_ = nullptr;
  ResizeFn resize_ = nullptr;
  OpenFn open_ = nullptr;
  PageCountFn page_count_ = nullptr;
  ShowFn show_ = nullptr;
  StatsFn stats_ = nullptr;
  StatusFn status_ = nullptr;

  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Flutter 正在用的那块 adapter 的 LUID。Rust 侧必须选同一块卡（硬约束）。
  uint64_t adapter_luid_ = 0;
  bool luid_known_ = false;
  std::string adapter_name_;

  // 当前句柄对应的目标尺寸与代际号。
  uint32_t width_ = 0;
  uint32_t height_ = 0;
  void* shared_handle_ = nullptr;
  uint64_t generation_ = 0;

  // descriptor 必须长期有效：引擎会一直持有这个指针，直到下一次 callback。
  FlutterDesktopGpuSurfaceDescriptor descriptor_ = {};

  // 统计。`handle_opened_` 是"链路真的通了"的硬证据 ——
  // 引擎只有在确实把这张纹理合成了才会去打开句柄。
  uint64_t frames_marked_ = 0;
  uint64_t handle_opened_ = 0;
  uint32_t resize_count_ = 0;
  uint32_t last_open_page_count_ = 0;

  // `SurfaceCallback` 在 raster 线程，`show` / `open` / `resize` 在平台线程，
  // 两者都会碰 `presenter_` 与上面这些字段。
  mutable std::mutex mutex_;

  bool ok_ = false;
  std::string error_;
};

#endif  // RUNNER_GPU_PRESENT_BRIDGE_H_
