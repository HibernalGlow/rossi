#ifndef RUNNER_GPU_PRESENT_BRIDGE_H_
#define RUNNER_GPU_PRESENT_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>

#include <d3d12.h>
// EnumAdapterByGpuPreference / DXGI_GPU_PREFERENCE_* 属于 IDXGIFactory6，
// 需要 dxgi1_6.h（dxgi1_4.h 里没有这两个符号）。
#include <dxgi1_6.h>

#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
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
// # `show` 不在平台线程上跑
//
// 冷页的 `show` 要 400–500 ms（60 MPix 的 AVIF 在 dav1d 上是**固定成本**，档位再小
// 也不减），而它原先是在**平台线程上同步跑**的 —— 平台线程同时还是 Win32 的消息泵，
// 所以那 400 ms 里窗口连拖动和输入都不响应。观感比"慢"更糟，这一条被用户直接报了。
//
// 于是重活挪到本类自己的一个工作线程上：平台线程只做参数校验、把这一份交出去、
// 立刻返回；Dart 侧的 `await` 照旧等，只是不再占着平台线程。线程契约：
//
// - **至多一份 `show` 在飞。** Dart 侧 `await` 每一份，所以这是表述而不是限制；
//   真的并发来了就报错（`busy`），**不排队** —— 排队等于让"用户早翻过去了"的那些页
//   继续解下去，正是预取那边刻意避开的那种积压。
// - 完成时用 `FlutterEngine::PostPlatformThreadTask` 把应答**送回平台线程**再调
//   `MethodResult` —— 它不保证线程安全，在别的线程上应答属于未定义用法。
// - `mutex_` 的持有者因此可能是工作线程。它是"presenter 访问锁"，
//   不再是"平台线程的锁"。退出次序见 `~GpuPresentBridge`。
// - `ROSSI_GPU_SHOW_ASYNC=0` 让 `show` 退回平台线程同步跑。**只为 A/B 存在**：
//   同一份二进制、只差这一处，才排得掉代码漂移对数字的影响。
//
// # 两把锁，不是一个
//
// 把 `show` 挪走之后还剩一个洞：`mutex_` 在工作线程上要持 400–500 ms，
// 而 `SurfaceCallback`（raster 线程）原先也要拿同一把 —— 于是 raster 被挡在
// 冷页解码后面，观感就是"翻页时画面顿住"。实测对照组帧跨度
// （`vsyncStart → rasterFinish`）最大 **487.7 ms**，就是这个。
//
// 所以拆成两把，**加锁顺序恒为 `mutex_` → `snapshot_mutex_`**：
//
// - `mutex_`：presenter 访问 + 计数。只在调用 `rossi_gpu_present_*` 时持有，
//   冷页时确实会持几百毫秒。
// - `snapshot_mutex_`：只护一份极小的"当前句柄/尺寸/代际"快照。
//   `SurfaceCallback` 的稳态路径（尺寸没变）**只拿这一把**，所以它绝不会
//   排在解码后面；真需要 resize 时才升级去拿 `mutex_`。
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
  // 开关后台预取。**可选符号**：它在 `LoadSymbols` 的存在性检查之外 ——
  // 少了它只是没有运行时开关（预取仍按默认开跑），不该因此把整条 GPU 路判死。
  using SetPrefetchFn = int32_t (*)(void* presenter, int32_t enabled);
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

  // ── `show`：重活与应答分开 ──
  //
  // 两者必须分开：重活可以（也应该）在工作线程上做，而应答**只能**在平台线程上做。
  // 把它们合成一个函数，就等于把"在哪个线程应答"这个决定藏进了调用点。
  struct ShowOutcome {
    bool ok = false;
    std::string code;
    std::string message;
  };

  // 一次 `show` 请求：页下标 + 还没应答的那一份 `result`。
  struct ShowJob {
    ShowJob(uint32_t page, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> r)
        : index(page), result(std::move(r)) {}
    uint32_t index = 0;
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  };

  void StartWorker();
  void StopWorker();
  void WorkerLoop();
  // 做 `show` 的重活：持 `mutex_` 调 Rust，成功后通知引擎来取帧。不碰 `MethodResult`。
  ShowOutcome PerformShow(uint32_t index);
  // 把结果交给 Dart。
  //
  // Flutter 官方 C++ wrapper 的 `EngineMethodResult` 底层 `BinaryReply` 回调自带
  // `FlutterDesktopMessengerLock` 保护，头文件与源码注释明确写明
  // "This lambda can be called on any thread"。因此工作线程完成渲染后可直接在此
  // 回复 Dart，无需经过 `PostPlatformThreadTask`，避免任务排队被 cancel 吞失。
  static void ResolveShow(const ShowOutcome& outcome,
                          flutter::MethodResult<flutter::EncodableValue>* result);
  // 告诉引擎"这一帧有新像素了"。**必须在释放 `mutex_` 之后调**（引擎可能同步回调
  // `SurfaceCallback`，而那要拿 `mutex_`，持锁调用会直接死锁）。
  //
  // 顺带记一句：`FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`
  // 的头文件明说"可以任何线程调"，所以异步 `show` 之后这一句是在**工作线程**上执行的 ——
  // 也就是说 `SurfaceCallback` 有可能就发生在工作线程上。那正是快路径必须只拿
  // `snapshot_mutex_` 的原因之一。
  void MarkFrameAvailable();

  // 排查用的落盘跟踪。设了 `ROSSI_GPU_SHOW_TRACE=<ASCII 路径>` 才写。
  //
  // 为什么要这个东西：Windows runner 是 GUI 子系统，**没有控制台** —— 线程卡在哪
  // 一步，从外面完全看不出来（表现只是"产物只写了个表头，然后什么都没有"）。
  // 跨线程的活一旦卡住，只有一个文件能说话。
  void Trace(const char* fmt, ...);
  std::string trace_path_;
  // `SurfaceCallback` 被调过几次。只用来给跟踪限量（每帧都会来一次）。
  // 它不是统计量，`stats` 里报的那个是 `resize_count_`。
  mutable uint64_t surface_calls_ = 0;

  // ── `show` 的工作线程 ──
  //
  // 单槽而不是队列：见类注释里的线程契约。
  std::thread worker_;
  mutable std::mutex work_mutex_;
  std::condition_variable work_cv_;
  std::unique_ptr<ShowJob> pending_show_;
  bool show_in_flight_ = false;
  bool worker_stopping_ = false;
  // 是否把 `show` 挪到工作线程。`ROSSI_GPU_SHOW_ASYNC=0` 可以关掉（A/B 用）。
  bool async_show_ = true;
  // 因为"上一页还没做完"而被拒掉的 `show` 次数。**正常恒为 0** ——
  // 它不为 0 就说明 Dart 侧出现了没被 `await` 串起来的并发，那是 bug 不是常态。
  uint64_t show_busy_rejected_ = 0;

  // 构造之后**只读**：所以 `show` 的工作线程可以不拿锁读它，用来把应答投回平台线程。
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
  SetPrefetchFn set_prefetch_ = nullptr;

  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Flutter 正在用的那块 adapter 的 LUID。Rust 侧必须选同一块卡（硬约束）。
  uint64_t adapter_luid_ = 0;
  bool luid_known_ = false;
  std::string adapter_name_;

  // ── 下面这一组由 `snapshot_mutex_` 护着 ──
  //
  // 它们就是"当前该把哪个句柄、多大尺寸交给引擎"的全部状态。单独一把锁的理由：
  // `SurfaceCallback` 在 raster 线程上每次合成都要读它，而 `mutex_` 在冷页 `show`
  // 期间会被持有几百毫秒 —— 共用一把就等于让 raster 排队等解码。
  //
  // 当前句柄对应的目标尺寸与代际号。
  uint32_t width_ = 0;
  uint32_t height_ = 0;
  void* shared_handle_ = nullptr;
  uint64_t generation_ = 0;

  // descriptor 必须长期有效：引擎会一直持有这个指针，直到下一次 callback。
  // （指针的存活期到下一次 callback 为止 —— 与本次改动之前**完全一样**，
  // 没有变得更宽松，也没有变得更紧。）
  FlutterDesktopGpuSurfaceDescriptor descriptor_ = {};
  mutable std::mutex snapshot_mutex_;

  // ── 下面这一组由 `mutex_` 护着 ──
  //
  // 统计。`handle_opened_` 是"链路真的通了"的硬证据 ——
  // 引擎只有在确实把这张纹理合成了才会去打开句柄。
  uint64_t frames_marked_ = 0;
  uint64_t handle_opened_ = 0;
  uint32_t resize_count_ = 0;
  uint32_t last_open_page_count_ = 0;

  // presenter 访问锁：凡是调 `rossi_gpu_present_*` 的地方都拿它。
  // 持有者可能是平台线程（`open` / `init` / `stats`）、raster 线程（`SurfaceCallback`
  // 里那次 resize）、或 `show` 的工作线程 —— 所以它**不是**"平台线程的锁"，
  // 也不要指望它短。
  //
  // **加锁顺序恒为 `mutex_` → `snapshot_mutex_`。** 反过来就有互锁空间。
  mutable std::mutex mutex_;

  bool ok_ = false;
  std::string error_;
};

#endif  // RUNNER_GPU_PRESENT_BRIDGE_H_
