#include "gpu_present_bridge.h"

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <utility>
#include <vector>

namespace {

std::string HrToHex(HRESULT hr) {
  char buffer[16] = {};
  std::snprintf(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(hr));
  return std::string(buffer);
}

std::string WideToUtf8(const wchar_t* wide) {
  if (wide == nullptr) {
    return std::string();
  }
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return std::string();
  }
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr, nullptr);
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// release_callback 的落点
//
// `FlutterDesktopGpuSurfaceDescriptor::release_context` 里放的是**代际号**
// （一个整数强转成指针），不是 `GpuPresentBridge*`。理由：
// 引擎的注销是异步的（`FlutterDesktopTextureRegistrarUnregisterExternalTexture`
// 的注释写着 "Asynchronously unregisters"），所以回调理论上可能在本对象析构**之后**
// 才来。把一个可能悬垂的 `this` 交出去是不可接受的；而一个整数即使迟到，
// 也只会落到"找不到这个代际"的 no-op 上。
//
// 代价是回调里要找回桥对象，于是有了这个进程级的落点。
// 本应用只有一个 GPU 呈现桥；`Register` 时占用、析构时清空，
// 清空之后迟到的回调一律安全地变成 no-op（我们只是晚一点回收那一代目标，
// 而 `MAX_RETIRED` 会给它兜底）。
// ─────────────────────────────────────────────────────────────────────────────
std::mutex g_release_target_mutex;
GpuPresentBridge* g_release_target = nullptr;

// 呈现器状态码。**必须与 `rust/gpu_present/src/lib.rs` 的 `STATE_*` 逐一对应** ——
// 这是一处跨语言的枚举，改一边不改另一边不会有任何编译错误，
// 只会把 `loading` 判成 `failed` 之类的静默错判。
constexpr int32_t kGpuStateLoading = 0;
constexpr int32_t kGpuStateReady = 1;
constexpr int32_t kGpuStateFailed = 2;

const char* GpuStateName(int32_t state) {
  switch (state) {
    case kGpuStateReady:
      return "ready";
    case kGpuStateLoading:
      return "loading";
    default:
      return "failed";
  }
}

// 取一个整数参数；Dart 的 int 可能以 int32_t / int64_t / double 三种形态过桥。
bool TryGetInt(const flutter::EncodableMap& map, const char* key, int64_t* out) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return false;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    *out = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    *out = *value;
    return true;
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    *out = static_cast<int64_t>(*value);
    return true;
  }
  return false;
}

bool TryGetString(const flutter::EncodableMap& map, const char* key,
                  std::string* out) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return false;
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    *out = *value;
    return true;
  }
  return false;
}

// 排查用的落盘跟踪（可选）。设了 `ROSSI_GPU_SHOW_TRACE=<ASCII 路径>` 才写。
//
// 为什么要这个东西：Windows runner 是 GUI 子系统，**没有控制台** —— 线程卡在哪一步
// 从外面完全看不出来（表现只是"产物只写了个表头，然后什么都没有"）。跨线程的活一旦
// 卡住，只有一个文件能说话。
//
// # 为什么不是"每次调 fopen_s/写/fclose"
//
// 第一版就是这么干的，结果是**会丢行**：平台线程、`show` 工作线程、raster 线程同时
// 开同一个文件、"a" 模式各自 seek 到末尾再写，几条日志互相盖掉。丢的恰好是排查最需要
// 的那一行时，"没有这一行"会被读成"这一步没发生" —— 比没有日志更坏。**这个坑真踩了。**
//
// 所以改成：**一个进程级的 sink，一把互斥，一行一次写**。写成**不依赖桥对象**的自由
// 函数，因为"工作线程投到平台线程上的那一段"也要打点，而那个 lambda 可能在桥析构之后
// 才轮到执行 —— 捕获 `this` 再调成员就是悬垂。所以它只认一个路径副本。
struct TraceSink {
  std::mutex mutex;
  FILE* file = nullptr;
  std::string path;
};

// **故意泄漏**：这个 sink 会被"桥已经析构之后才轮到的任务"用到，
// 让它有一个会在退出时被析构的对象，等于给自己造一个 use-after-free。
TraceSink& Sink() {
  static TraceSink* sink = new TraceSink();
  return *sink;
}

void TraceToV(const std::string& path, const char* fmt, va_list args) {
  if (path.empty()) {
    return;
  }
  TraceSink& sink = Sink();
  std::lock_guard<std::mutex> guard(sink.mutex);
  if (sink.file == nullptr || sink.path != path) {
    if (sink.file != nullptr) {
      std::fclose(sink.file);
      sink.file = nullptr;
    }
    if (::fopen_s(&sink.file, path.c_str(), "a") != 0 || sink.file == nullptr) {
      return;
    }
    sink.path = path;
  }
  std::fprintf(sink.file, "%llu ", static_cast<unsigned long long>(::GetTickCount64()));
  std::vfprintf(sink.file, fmt, args);
  std::fputc(10, sink.file);  // 10 = 换行。**不用字符字面量**：转义层在 Windows 上很容易把这一行写坏。
  std::fflush(sink.file);
}

void TraceTo(const std::string& path, const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  TraceToV(path, fmt, args);
  va_end(args);
}

}  // namespace

GpuPresentBridge::GpuPresentBridge(flutter::FlutterEngine* engine,
                                   FlutterDesktopTextureRegistrarRef texture_registrar)
    : engine_(engine), texture_registrar_(texture_registrar) {
  if (engine_ == nullptr) {
    error_ = "FlutterEngine 为空";
    return;
  }
  if (texture_registrar_ == nullptr) {
    error_ = "texture registrar 为空";
    return;
  }

  // 先把 MethodChannel 挂上，再做后面那些会失败的事。
  //
  // 反过来（先加载 DLL，成功了才建 channel）看着更自然，但那样一旦加载失败，
  // Dart 侧调 `stats` 拿到的是 MissingPluginException —— 一个**说不出原因的**
  // 错误。这层的设计目标之一恰恰是"失败也要能说出为什么"，所以通道必须先于
  // 可能失败的部分建立。
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine_->messenger(), "rossi/gpu_present",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  if (!LoadSymbols()) {
    return;
  }

  // 解析 Flutter 正在用的那块 adapter。取不到不阻止启动，只是退化成
  // "让 Rust 自己挑一块" —— 但那时跨 adapter 共享可能失败或极慢，
  // 所以这个 bool 会原样报给 Dart，不要当成无关紧要的细节。
  IDXGIAdapter* raw_adapter = nullptr;
  if (engine_->GetGraphicsAdapter(&raw_adapter) && raw_adapter != nullptr) {
    DXGI_ADAPTER_DESC desc{};
    if (SUCCEEDED(raw_adapter->GetDesc(&desc))) {
      adapter_luid_ = (static_cast<uint64_t>(static_cast<uint32_t>(desc.AdapterLuid.HighPart))
                       << 32) |
                      static_cast<uint64_t>(desc.AdapterLuid.LowPart);
      adapter_name_ = WideToUtf8(desc.Description);
      luid_known_ = true;
    }
    raw_adapter->Release();
  }

  // 尺寸先给 0：真正的尺寸由 `init` 或 `SurfaceCallback` 带进来。
  // 这里不猜一个默认值 —— 猜错会白建一张纹理，而且掩盖"引擎到底要多大"这个事实。
  std::vector<uint8_t> err(1024, 0);
  presenter_ = create_(adapter_luid_, 0, 0, err.data(), static_cast<size_t>(err.size()));
  if (presenter_ == nullptr) {
    error_ = std::string("wgpu 呈现器创建失败: ") + reinterpret_cast<const char*>(err.data());
    return;
  }

  // `ROSSI_GPU_SHOW_ASYNC=0` 让 `show` 退回"在平台线程上同步跑"。**只为 A/B 存在**：
  // 同一份二进制、只差这一处，才排得掉代码漂移对数字的影响（与预取那个开关同理）。
  wchar_t async_flag[8] = {};
  if (::GetEnvironmentVariableW(L"ROSSI_GPU_SHOW_ASYNC", async_flag, 8) > 0) {
    async_show_ = !(async_flag[0] == L'0' && async_flag[1] == L'\0');
  }

  // 排查用的落盘跟踪（可选）。路径必须是 ASCII —— `fopen_s` 用窄字符 API，
  // 中文路径在这个编码下会打不开，而"打不开"的表现是**静默没有任何跟踪**。
  //
  // 用 `GetEnvironmentVariableA` 而不是 `std::getenv`：后者在 MSVC 上是 C4996
  // （"unsafe"，建议 `_dupenv_s`），而本工程开了 `/W4 /WX` —— 一句
  // 排查用的读环境变量会把整个构建拦下来，不值当。
  char trace_env[512] = {};
  if (::GetEnvironmentVariableA("ROSSI_GPU_SHOW_TRACE", trace_env,
                                static_cast<DWORD>(sizeof(trace_env))) > 0) {
    trace_path_ = trace_env;
    Trace("bridge-init ok=%d async=%d", 1, async_show_ ? 1 : 0);
  }

  // 工作线程即使 `async_show_ == false` 也起：它待着不做事，省掉一条"到底起没起过"
  // 的分支，`StopWorker` 也就不用猜。
  StartWorker();

  // 冒烟：从**平台线程**投一份空任务回去。它和 `WorkerLoop` 里那一份走的是同一条路，
  // 但起点不同 —— 两者放在一起就能把"投递机制坏了"与"从别的线程投不行"分开。
  // （排查用；`TraceTo` 在没设跟踪路径时是 no-op，正式路径零代价。）
  if (engine_ != nullptr) {
    engine_->PostPlatformThreadTask(
        [path = trace_path_]() { TraceTo(path, "smoke-from-platform"); });
  }

  ok_ = true;
}

GpuPresentBridge::~GpuPresentBridge() {
  // **第一件事**：把 `show` 的工作线程停下来、并等它做完手上那一份。
  //
  // 次序不能改 —— 下面马上要在 `mutex_` 保护下调用 Rust、注销纹理、最后卸载 DLL，
  // 而工作线程会调进 `presenter_`；不等它就是"在已卸下的代码页上跳转"。
  // 代价：关窗时如果正好在解一页，这里会等最多一页解码（~0.5 s）。
  // 与 Rust 侧 `Drop` 里 stop + join 预取线程是同一种取舍 —— 宁可慢一点收尾。
  StopWorker();

  // 顺序很重要：先注销纹理，再销毁呈现器，最后卸载 DLL。
  // Rust 对象里持有 wgpu 与 D3D12 资源，它们的析构函数在 DLL 里，
  // 卸载后再析构就是"在已卸下的代码页上跳转"。
  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(texture_registrar_,
                                                            texture_id_, nullptr,
                                                            nullptr);
    texture_id_ = -1;
  }

  {
    std::lock_guard<std::mutex> guard(g_release_target_mutex);
    if (g_release_target == this) {
      // 清空之后，迟到的 release_callback 会安全地变成 no-op。
      g_release_target = nullptr;
    }
  }

  channel_.reset();

  if (presenter_ != nullptr && destroy_ != nullptr) {
    destroy_(presenter_);
    presenter_ = nullptr;
  }
  shared_handle_ = nullptr;

  if (library_ != nullptr) {
    FreeLibrary(library_);
    library_ = nullptr;
  }
}

bool GpuPresentBridge::LoadSymbols() {
  library_ = ::LoadLibraryW(L"rossi_gpu_present.dll");
  if (library_ == nullptr) {
    error_ = "加载 rossi_gpu_present.dll 失败（错误码 " +
             std::to_string(::GetLastError()) +
             "）—— 多半是 cargo 没构建出这个产物，见 windows/runner/CMakeLists.txt";
    return false;
  }

  // MSVC 对 FARPROC → 函数指针的转换报 C4191，而本工程开了 /W4 /WX。
  // 这里取的是本仓库自己 DLL 自己导出的符号，转换是安全的。
#pragma warning(push)
#pragma warning(disable : 4191)
  create_ = reinterpret_cast<CreateFn>(::GetProcAddress(library_, "rossi_gpu_present_create"));
  destroy_ = reinterpret_cast<DestroyFn>(::GetProcAddress(library_, "rossi_gpu_present_destroy"));
  handle_ = reinterpret_cast<HandleFn>(::GetProcAddress(library_, "rossi_gpu_present_handle"));
  generation_fn_ =
      reinterpret_cast<GenerationFn>(::GetProcAddress(library_, "rossi_gpu_present_generation"));
  notify_released_ = reinterpret_cast<NotifyReleasedFn>(
      ::GetProcAddress(library_, "rossi_gpu_present_notify_released"));
  resize_ = reinterpret_cast<ResizeFn>(::GetProcAddress(library_, "rossi_gpu_present_resize"));
  open_ = reinterpret_cast<OpenFn>(::GetProcAddress(library_, "rossi_gpu_present_open"));
  page_count_ =
      reinterpret_cast<PageCountFn>(::GetProcAddress(library_, "rossi_gpu_present_page_count"));
  show_ = reinterpret_cast<ShowFn>(::GetProcAddress(library_, "rossi_gpu_present_show"));
  stats_ = reinterpret_cast<StatsFn>(::GetProcAddress(library_, "rossi_gpu_present_stats"));
  status_ = reinterpret_cast<StatusFn>(::GetProcAddress(library_, "rossi_gpu_present_status"));
  // 故意**不在**下面的必需符号检查里：缺它只意味着没有运行时开关，
  // 预取照样按默认开关跑。为一个可选控制把整条 GPU 路判死是不划算的。
  set_prefetch_ =
      reinterpret_cast<SetPrefetchFn>(::GetProcAddress(library_, "rossi_gpu_present_set_prefetch"));
#pragma warning(pop)

  if (create_ == nullptr || destroy_ == nullptr || handle_ == nullptr ||
      generation_fn_ == nullptr || notify_released_ == nullptr || resize_ == nullptr ||
      open_ == nullptr || page_count_ == nullptr || show_ == nullptr || stats_ == nullptr ||
      status_ == nullptr) {
    error_ =
        "rossi_gpu_present.dll 缺少必要的导出符号（版本不匹配？）。"
        "若是刚升过版，注意 `rossi_gpu_present_status` 是异步创建引入的新符号，"
        "旧的 DLL 要重新 cargo build";
    return false;
  }
  return true;
}

bool GpuPresentBridge::Register() {
  if (!ok_) {
    return false;
  }
  if (texture_id_ >= 0) {
    return true;
  }

  FlutterDesktopGpuSurfaceTextureConfig gpu_config{};
  gpu_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
  gpu_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  gpu_config.callback = &GpuPresentBridge::SurfaceCallback;
  gpu_config.user_data = this;

  FlutterDesktopTextureInfo info{};
  info.type = kFlutterDesktopGpuSurfaceTexture;
  info.gpu_surface_config = gpu_config;

  texture_id_ =
      FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &info);
  if (texture_id_ < 0) {
    error_ = "RegisterExternalTexture 失败";
    ok_ = false;
    return false;
  }

  {
    std::lock_guard<std::mutex> guard(g_release_target_mutex);
    if (g_release_target != nullptr && g_release_target != this) {
      // 只应是单实例。真出现了，后注册的会抢走回调落点 —— 报出来而不是静默。
      OutputDebugStringA("GpuPresentBridge: 已存在另一个实例，release 回调可能错配\n");
    }
    g_release_target = this;
  }
  return true;
}

// 引擎以它想要的像素尺寸来要 surface。尺寸变化就在这里发生。
const FlutterDesktopGpuSurfaceDescriptor* GpuPresentBridge::SurfaceCallback(
    size_t width, size_t height, void* user_data) {
  auto* self = static_cast<GpuPresentBridge*>(user_data);
  if (self == nullptr || !self->ok_) {
    return nullptr;
  }

  const uint32_t target_width =
      static_cast<uint32_t>(width > 0 ? std::min<size_t>(width, 8192) : 1);
  const uint32_t target_height =
      static_cast<uint32_t>(height > 0 ? std::min<size_t>(height, 8192) : 1);
  // 跟踪只记前若干次：`SurfaceCallback` 每合成一帧就会来一次，全记会把文件写爆。
  const bool traced = self->surface_calls_ < 400;
  self->surface_calls_++;
  if (traced) {
    self->Trace("surface-enter %ux%u", target_width, target_height);
  }

  // ── 稳态快路径：尺寸没变，只拿 `snapshot_mutex_` ──
  //
  // 这一条是**为冷页加的**。`show` 的工作线程此刻可能正持着 `mutex_` 解一页
  // 400–500 ms，而本函数跑在 raster 线程上；两者原先共用一把锁，于是 raster
  // 排到解码后面去，观感就是"翻页时画面顿住"（实测帧跨度最大 487.7 ms）。
  // 尺寸没变时这里根本不需要 presenter，也就不该去排那把长锁。
  {
    std::lock_guard<std::mutex> snapshot(self->snapshot_mutex_);
    if (self->shared_handle_ != nullptr && self->width_ == target_width &&
        self->height_ == target_height) {
      if (traced) {
        self->Trace("surface-fast-ok");
      }
      return &self->descriptor_;
    }
  }

  // ── 慢路径：首次（尺寸还是 0）或尺寸真的变了，才去碰 presenter ──
  {
    if (traced) {
      self->Trace("surface-slow-wait-lock");
    }
    std::lock_guard<std::mutex> guard(self->mutex_);
    if (traced) {
      self->Trace("surface-slow-locked");
    }

    // 未就绪时没有句柄可给，只能回 nullptr（语义是"这一帧没有 surface"，合法）。
    // 把 `shared_handle_` 的初始值 nullptr 当成合法句柄交出去就不是合法用法了。
    //
    // 正常流程里走不到这里：Dart 侧在收到 `ready` 之前不构建 `Texture`，
    // 引擎也就不会来要帧。这一段是防误用，不是主路径。
    if (self->QueryStateLocked(nullptr) != kGpuStateReady) {
      return nullptr;
    }
    if (!self->SyncTarget(target_width, target_height)) {
      return nullptr;
    }
    if (traced) {
      self->Trace("surface-slow-done");
    }
    // 加锁顺序 `mutex_` → `snapshot_mutex_`，与别处一致。
    std::lock_guard<std::mutex> snapshot(self->snapshot_mutex_);
    return &self->descriptor_;
  }
}

// 向 Rust 问当前就绪状态。调用方必须已持有 `mutex_`。
int32_t GpuPresentBridge::QueryStateLocked(std::string* error) {
  if (presenter_ == nullptr || status_ == nullptr) {
    if (error != nullptr) {
      *error = error_.empty() ? std::string("呈现器不可用") : error_;
    }
    return kGpuStateFailed;
  }

  std::vector<uint8_t> err(1024, 0);
  const int32_t state = status_(presenter_, err.data(), static_cast<size_t>(err.size()));
  if (state == kGpuStateFailed && error != nullptr) {
    *error = reinterpret_cast<const char*>(err.data());
  }
  return state;
}

// 让 Rust 侧的呈现目标与请求尺寸一致，并刷新本地缓存的句柄/尺寸。
//
// 调用方必须已经持有 `mutex_`，**并且必须先确认呈现器已就绪** ——
// 未就绪时 Rust 侧的 `resize` 会失败，而那不是"这个尺寸不行"，是"还没轮到"，
// 把两者混起来报错会把排查方向带偏。
bool GpuPresentBridge::SyncTarget(uint32_t width, uint32_t height) {
  if (presenter_ == nullptr || resize_ == nullptr) {
    return false;
  }
  {
    std::lock_guard<std::mutex> snapshot(snapshot_mutex_);
    if (shared_handle_ != nullptr && width_ == width && height_ == height) {
      return true;
    }
  }

  std::vector<uint8_t> err(1024, 0);
  void* handle = resize_(presenter_, width, height, err.data(), static_cast<size_t>(err.size()));
  if (handle == nullptr) {
    error_ = std::string("resize 失败: ") + reinterpret_cast<const char*>(err.data());
    return false;
  }

  // `presenter_` 在我们持有 `mutex_` 期间是稳定的，所以代际号可以放在取快照之前问，
  // 临界区里就只剩几次赋值。
  const uint64_t generation = generation_fn_ != nullptr ? generation_fn_(presenter_) : 0;
  {
    std::lock_guard<std::mutex> snapshot(snapshot_mutex_);
    shared_handle_ = handle;
    width_ = width;
    height_ = height;
    generation_ = generation;
    resize_count_++;
    RefreshDescriptor();
  }
  return true;
}

// 调用方必须已持有 `snapshot_mutex_`（它写的是那一组字段）。
void GpuPresentBridge::RefreshDescriptor() {
  descriptor_ = {};
  descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  descriptor_.handle = shared_handle_;
  descriptor_.width = width_;
  descriptor_.height = height_;
  descriptor_.visible_width = width_;
  descriptor_.visible_height = height_;
  // 必须是 BGRA8888：Flutter Windows 走 ANGLE / D3D11 打开这张共享纹理合成，
  // 而 D3D11 打不开 RGBA8 的共享纹理。Rust 侧建的就是 BGRA8，两边一致。
  descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
  descriptor_.release_callback = &GpuPresentBridge::OnHandleOpened;
  // 传代际号而不是 this —— 见文件顶部 g_release_target 的说明。
  descriptor_.release_context = reinterpret_cast<void*>(static_cast<uintptr_t>(generation_));
}

void GpuPresentBridge::OnHandleOpened(void* release_context) {
  const auto generation = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(release_context));

  GpuPresentBridge* self = nullptr;
  {
    std::lock_guard<std::mutex> guard(g_release_target_mutex);
    self = g_release_target;
  }
  if (self == nullptr) {
    // 桥已经拆了；这一代目标会被 `MAX_RETIRED` 兜底回收。
    return;
  }

  {
    std::lock_guard<std::mutex> guard(self->mutex_);
    self->handle_opened_++;
  }
  if (self->notify_released_ != nullptr && self->presenter_ != nullptr) {
    self->notify_released_(self->presenter_, generation);
  }
}

void GpuPresentBridge::Trace(const char* fmt, ...) {
  if (trace_path_.empty()) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  TraceToV(trace_path_, fmt, args);
  va_end(args);
}

// ─────────────────────────────────────────────────────────────────────────────
// `show`：重活、应答、工作线程
//
// 三件事刻意分成三个函数：
// `PerformShow` 跑重活（自己拿 `mutex_`）、`ResolveShow` 应答（跨线程安全）、
// `WorkerLoop` 调度二者并维护 `show_in_flight_` 单槽。
// ─────────────────────────────────────────────────────────────────────────────

GpuPresentBridge::ShowOutcome GpuPresentBridge::PerformShow(uint32_t index) {
  {
    Trace("perform-wait-lock idx=%u", index);
    std::lock_guard<std::mutex> guard(mutex_);
    Trace("perform-locked idx=%u", index);
    if (QueryStateLocked(nullptr) != kGpuStateReady) {
      Trace("perform-not-ready idx=%u", index);
      return {false, "not-ready", "呈现器尚未就绪，此刻应走兜底路径"};
    }
    std::vector<uint8_t> err(1024, 0);
    const int32_t rc = show_(presenter_, index, err.data(), static_cast<size_t>(err.size()));
    Trace("perform-ffi-done idx=%u rc=%d", index, rc);
    if (rc != 0) {
      return {false, "show-failed", reinterpret_cast<const char*>(err.data())};
    }
  }
  // 锁放掉了才通知引擎 —— 见 `MarkFrameAvailable` 的说明。
  MarkFrameAvailable();
  return {true, std::string(), std::string()};
}

void GpuPresentBridge::MarkFrameAvailable() {
  int64_t texture_id = -1;
  {
    // `texture_id_` 只在 `Register()`（平台线程）与析构里改，而析构那次发生在
    // `StopWorker()` 之后 —— 所以这里读不到半截。拿一下锁只是为了不给"它在不在"
    // 留悬念，代价是几次原子操作。
    std::lock_guard<std::mutex> guard(mutex_);
    texture_id = texture_id_;
  }
  // **必须**在释放 `mutex_` 之后再通知引擎：引擎可能同步回调 `SurfaceCallback`，
  // 而它（慢路径）要拿 `mutex_`，持锁调用会直接死锁。
  if (texture_registrar_ != nullptr && texture_id >= 0) {
    Trace("mark-enter id=%lld", static_cast<long long>(texture_id));
    FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(texture_registrar_,
                                                                    texture_id);
    Trace("mark-done id=%lld", static_cast<long long>(texture_id));
    std::lock_guard<std::mutex> guard(mutex_);
    frames_marked_++;
  }
}

// 静态成员：没有 `this`，所以投到平台任务队列里的 lambda 可以放心调它 ——
// 即使它轮到执行时桥已经析构。
void GpuPresentBridge::ResolveShow(
    const ShowOutcome& outcome,
    flutter::MethodResult<flutter::EncodableValue>* result) {
  if (outcome.ok) {
    result->Success(flutter::EncodableValue(true));
  } else {
    result->Error(outcome.code, outcome.message);
  }
}

void GpuPresentBridge::StartWorker() {
  {
    std::lock_guard<std::mutex> guard(work_mutex_);
    if (worker_.joinable()) {
      return;
    }
    worker_stopping_ = false;
  }
  worker_ = std::thread([this] { WorkerLoop(); });
}

void GpuPresentBridge::StopWorker() {
  std::unique_ptr<ShowJob> dropped;
  {
    std::lock_guard<std::mutex> guard(work_mutex_);
    if (!worker_.joinable()) {
      return;
    }
    worker_stopping_ = true;
    dropped = std::move(pending_show_);
    pending_show_.reset();
  }
  work_cv_.notify_all();

  // 等这一份做完。**不能不等** —— 工作线程会调进 `presenter_`，而析构流程马上
  // 就要销毁呈现器并卸载 DLL。代价是"关窗时正好在解一页"会等最多一页解码
  // （~0.5 s）；与 Rust 侧 `Drop` 里 stop + join 预取线程是同一种取舍：
  // 宁可慢一点收尾，也不要"在已卸下的代码页上跳转"。
  worker_.join();

  if (dropped != nullptr) {
    // 还没轮到的那一份以错误收尾，别让 Dart 的 future 悬着。
    // 此刻引擎还活着（关停次序见 `flutter_window.cpp` 的 `OnDestroy`），
    // 而本函数在平台线程上跑，所以这一次应答是合法的。
    ResolveShow(ShowOutcome{false, "shutting-down", "呈现器正在关闭，这一页没有呈现"},
                dropped->result.get());
  }
}

void GpuPresentBridge::WorkerLoop() {
  for (;;) {
    uint32_t index = 0;
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
    {
      std::unique_lock<std::mutex> lock(work_mutex_);
      work_cv_.wait(lock, [this] { return worker_stopping_ || pending_show_ != nullptr; });
      if (pending_show_ == nullptr) {
        return;  // 停止，而且手上没有活
      }
      index = pending_show_->index;
      result = std::move(pending_show_->result);
      pending_show_.reset();
    }

    Trace("worker-pickup idx=%u", index);
    const ShowOutcome outcome = PerformShow(index);
    Trace("worker-perform-done idx=%u ok=%d", index, outcome.ok ? 1 : 0);

    // 引擎底层 BinaryReply 回调自带 FlutterDesktopMessengerLock 保护，源码与注释明确注明：
    // "Note: This lambda can be called on any thread."
    // 直接在工作线程上应答：不经过 Windows 消息泵/平台任务队列，彻底杜绝丢任务导致的 Future 挂死。
    // 先应答、再清理 show_in_flight_，严格保证先后顺序。
    Trace("worker-resolve-enter idx=%u", index);
    ResolveShow(outcome, result.get());
    Trace("worker-resolve-done idx=%u", index);

    {
      std::lock_guard<std::mutex> guard(work_mutex_);
      show_in_flight_ = false;
    }
    Trace("worker-inflight-clear idx=%u", index);
  }
}

flutter::EncodableMap GpuPresentBridge::BuildStats() {
  std::lock_guard<std::mutex> guard(mutex_);

  std::string state_error;
  const int32_t state = QueryStateLocked(&state_error);

  // Rust 侧的状态以 JSON 字符串透传，C++ 侧不解析 —— 免得两侧结构体
  // 定义要手动保持同步。Dart 侧按 key 取。
  std::string probe_json;
  if (stats_ != nullptr && presenter_ != nullptr) {
    std::vector<uint8_t> buffer(4096, 0);
    const int32_t written = stats_(presenter_, buffer.data(), static_cast<size_t>(buffer.size()));
    if (written > 0) {
      probe_json = reinterpret_cast<const char*>(buffer.data());
    }
  }

  // 快照字段是另一把锁护的，先把它们取出来（加锁顺序 `mutex_` → `snapshot_mutex_`）。
  //
  // 顺带说明一个**已知的洞**：本函数整体要等 `mutex_`，所以冷页解码期间调 `stats`
  // 会等最多一页的时间。`stats` 是诊断调用，产品路径上没有周期性调用者
  // （调试页那 1 s 心跳除外，而它量的正是翻完之后的读数）。
  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t generation = 0;
  uint32_t resizes = 0;
  {
    std::lock_guard<std::mutex> snapshot(snapshot_mutex_);
    width = width_;
    height = height_;
    generation = generation_;
    resizes = resize_count_;
  }
  uint64_t busy_rejected = 0;
  {
    // `work_mutex_` 是叶子锁：没有人在持另外两把的时候拿它，反过来也一样。
    std::lock_guard<std::mutex> work(work_mutex_);
    busy_rejected = show_busy_rejected_;
  }

  flutter::EncodableMap map;
  // `ok` 的语义是"这条路径**有实现**"（DLL 在、符号齐、呈现器对象建出来了），
  // **不是**"现在能用"。能不能用看 `state` —— 把这两件事压进一个 bool，
  // 正是 loading 与 failed 分不开的根源。
  map[flutter::EncodableValue("ok")] =
      flutter::EncodableValue(ok_ && presenter_ != nullptr);
  map[flutter::EncodableValue("state")] = flutter::EncodableValue(GpuStateName(state));
  map[flutter::EncodableValue("error")] =
      flutter::EncodableValue(state_error.empty() ? error_ : state_error);
  map[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(static_cast<int64_t>(texture_id_));
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(width));
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(height));
  map[flutter::EncodableValue("adapter")] = flutter::EncodableValue(adapter_name_);
  map[flutter::EncodableValue("luidKnown")] = flutter::EncodableValue(luid_known_);
  map[flutter::EncodableValue("adapterLuid")] = flutter::EncodableValue(
      static_cast<int64_t>(adapter_luid_ & 0x7FFFFFFFFFFFFFFFLL));
  map[flutter::EncodableValue("generation")] =
      flutter::EncodableValue(static_cast<int64_t>(generation));
  map[flutter::EncodableValue("framesMarked")] =
      flutter::EncodableValue(static_cast<int64_t>(frames_marked_));
  // 这一条是"链路真的通了"的硬证据：引擎只有确实把这张纹理合成了才会打开句柄。
  map[flutter::EncodableValue("handleOpened")] =
      flutter::EncodableValue(static_cast<int64_t>(handle_opened_));
  map[flutter::EncodableValue("resizes")] =
      flutter::EncodableValue(static_cast<int32_t>(resizes));
  map[flutter::EncodableValue("pageCount")] =
      flutter::EncodableValue(static_cast<int32_t>(last_open_page_count_));
  // `show` 是不是真的挪到工作线程了 —— A/B 时先看这一条，别只看数字差。
  map[flutter::EncodableValue("showAsync")] = flutter::EncodableValue(async_show_);
  map[flutter::EncodableValue("showBusyRejected")] =
      flutter::EncodableValue(static_cast<int64_t>(busy_rejected));
  map[flutter::EncodableValue("probe")] = flutter::EncodableValue(probe_json);
  return map;
}

void GpuPresentBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  // 每一个进来的调用都记一笔。排查「Dart 到底有没有再调 show」这类问题时，
  // 「有没有到达桥」与「到了之后卡在哪」是两件事，必须分得开。
  Trace("call %s", method.c_str());

  if (method == "stats") {
    result->Success(flutter::EncodableValue(BuildStats()));
    return;
  }

  // 只问状态，不做别的事。Dart 侧在等呈现器就绪时轮询它。
  //
  // 单独开一个方法而不复用 `stats`：`stats` 会去问 Rust 要一份完整快照
  // （解码档位、分段耗时、代际号……），那些字段在"还在建"的等待期全是零，
  // 一起拖过来既慢（多一次跨语言往返）又让人误以为"已经有数据可看"。
  if (method == "status") {
    // 桥本身不可用也必须给出**可判定**的结论，不能让 Dart 一直在 loading 里等 ——
    // 那是把"永远等不到"伪装成"再等等"。
    if (!ok_) {
      flutter::EncodableMap payload;
      payload[flutter::EncodableValue("state")] = flutter::EncodableValue("failed");
      payload[flutter::EncodableValue("error")] = flutter::EncodableValue(error_);
      result->Success(flutter::EncodableValue(payload));
      return;
    }

    std::string state_error;
    int32_t state = kGpuStateLoading;
    int64_t texture_id = -1;
    {
      std::lock_guard<std::mutex> guard(mutex_);
      state = QueryStateLocked(&state_error);
      texture_id = static_cast<int64_t>(texture_id_);
    }

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("state")] = flutter::EncodableValue(GpuStateName(state));
    payload[flutter::EncodableValue("textureId")] = flutter::EncodableValue(texture_id);
    payload[flutter::EncodableValue("adapter")] = flutter::EncodableValue(adapter_name_);
    payload[flutter::EncodableValue("luidKnown")] = flutter::EncodableValue(luid_known_);
    if (!state_error.empty()) {
      payload[flutter::EncodableValue("error")] = flutter::EncodableValue(state_error);
    }
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  // Dart 侧带尺寸来，是为了在"还没建 Texture widget"之前就能把目标建好 ——
  // 否则第一次 `show` 会因为没有呈现目标而失败。
  if (method == "init") {
    if (!ok_) {
      result->Error("unavailable", error_);
      return;
    }
    int64_t width = 0;
    int64_t height = 0;
    const auto* arguments = call.arguments();
    if (const auto* map = arguments != nullptr ? std::get_if<flutter::EncodableMap>(arguments)
                                              : nullptr) {
      TryGetInt(*map, "width", &width);
      TryGetInt(*map, "height", &height);
    }
    // 参数错误与"还没就绪"是两回事，先校验参数 —— 它在任何状态下都是错的。
    if (width <= 0 || height <= 0) {
      result->Error("bad-arguments", "init 需要正的 width / height");
      return;
    }

    std::string state_error;
    int32_t state = kGpuStateLoading;
    {
      std::lock_guard<std::mutex> guard(mutex_);
      state = QueryStateLocked(&state_error);
      // 只有就绪时才碰呈现目标。未就绪时调 `resize` 也会失败，但那个失败
      // 什么都不说明 —— 现在本来就不该建目标。
      if (state == kGpuStateReady) {
        if (!SyncTarget(static_cast<uint32_t>(width), static_cast<uint32_t>(height))) {
          result->Error("resize-failed", error_);
          return;
        }
        // 幂等：`OnCreate` 时已注册过一次，这里再调是兜底（比如那次失败了）。
        if (!Register()) {
          result->Error("register-failed", error_);
          return;
        }
      }
    }

    // **未就绪走 Success 而不是 Error**：`{state:"loading"}` 的语义是
    // "这条路还没铺好，你先走兜底"，它是一个正常中间态。报成错误会逼 Dart 侧
    // 把"再等等就好"和"永远不行"当成同一件事处理。
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("state")] = flutter::EncodableValue(GpuStateName(state));
    payload[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(width));
    payload[flutter::EncodableValue("height")] =
        flutter::EncodableValue(static_cast<int32_t>(height));
    payload[flutter::EncodableValue("adapter")] = flutter::EncodableValue(adapter_name_);
    if (state == kGpuStateReady) {
      payload[flutter::EncodableValue("textureId")] =
          flutter::EncodableValue(static_cast<int64_t>(texture_id_));
    }
    if (state == kGpuStateFailed) {
      payload[flutter::EncodableValue("error")] =
          flutter::EncodableValue(state_error.empty() ? error_ : state_error);
    }
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  if (method == "open") {
    if (!ok_) {
      result->Error("unavailable", error_);
      return;
    }
    std::string path;
    const auto* arguments = call.arguments();
    if (const auto* map = arguments != nullptr ? std::get_if<flutter::EncodableMap>(arguments)
                                              : nullptr) {
      TryGetString(*map, "path", &path);
    }
    if (path.empty()) {
      result->Error("bad-arguments", "open 需要 path");
      return;
    }

    std::lock_guard<std::mutex> guard(mutex_);
    if (QueryStateLocked(nullptr) != kGpuStateReady) {
      // 单独一个 error code：调用方（和人）要能一眼分辨"这条路还没铺好"
      // 与"这个文件打不开"—— 两者的下一步动作完全不同。
      result->Error("not-ready", "呈现器尚未就绪，此刻应走兜底路径");
      return;
    }
    std::vector<uint8_t> err(1024, 0);
    const int32_t count = open_(presenter_, reinterpret_cast<const uint8_t*>(path.data()),
                               path.size(), err.data(), static_cast<size_t>(err.size()));
    if (count < 0) {
      result->Error("open-failed", reinterpret_cast<const char*>(err.data()));
      return;
    }
    last_open_page_count_ = static_cast<uint32_t>(count);

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("pageCount")] = flutter::EncodableValue(count);
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  if (method == "show") {
    if (!ok_) {
      result->Error("unavailable", error_);
      return;
    }
    int64_t index = 0;
    const auto* arguments = call.arguments();
    if (const auto* map = arguments != nullptr ? std::get_if<flutter::EncodableMap>(arguments)
                                              : nullptr) {
      TryGetInt(*map, "index", &index);
    }
    if (index < 0) {
      result->Error("bad-arguments", "show 需要非负的 index");
      return;
    }

    // 这里**故意不先问一遍就绪**。问它要拿 `mutex_`，而冷页时 `mutex_` 正被上一份
    // `show` 占着 —— 在平台线程上等它，就把"平台线程不阻塞"这件事又还回去了。
    // 就绪与否交给 `PerformShow` 在工作线程上判，错误照样回得到 Dart（晚一个投递）。
    if (!async_show_) {
      // 对照路径：仍在平台线程上同步跑（`ROSSI_GPU_SHOW_ASYNC=0`）。
      ResolveShow(PerformShow(static_cast<uint32_t>(index)), result.get());
      return;
    }

    auto job = std::make_unique<ShowJob>(static_cast<uint32_t>(index), std::move(result));
    {
      std::lock_guard<std::mutex> guard(work_mutex_);
      if (worker_stopping_ || !worker_.joinable()) {
        // 正在关窗。老实报出来，不要把这一份挂在那里等一个永远不会有的应答。
        job->result->Error("shutting-down", "呈现器正在关闭");
        return;
      }
      if (show_in_flight_) {
        // Dart 侧 `await` 每一份 `show`，所以这不该发生 —— 真发生了就报出来，
        // 而不是排队：排队等于让"用户早翻过去了"的那一页继续解下去，
        // 那正是预取那边刻意避开的积压。
        show_busy_rejected_++;
        Trace("handler-reject-busy idx=%lld", static_cast<long long>(index));
        job->result->Error("busy", "上一页还在呈现：本桥一次只接一份 show");
        return;
      }
      show_in_flight_ = true;
      pending_show_ = std::move(job);
    }
    Trace("handler-accept idx=%lld", static_cast<long long>(index));
    work_cv_.notify_all();
    return;
  }

  // 开关预取。存在的主要理由是 A/B 与将来的"离开阅读器就关掉"，
  // 所以**不因未就绪而报错**：还没建好时这个开关本来就无事可做。
  if (method == "setPrefetch") {
    bool enabled = true;
    const auto* arguments = call.arguments();
    if (const auto* map = arguments != nullptr ? std::get_if<flutter::EncodableMap>(arguments)
                                              : nullptr) {
      const auto it = map->find(flutter::EncodableValue("enabled"));
      if (it != map->end()) {
        if (const auto* value = std::get_if<bool>(&it->second)) {
          enabled = *value;
        }
      }
    }
    if (set_prefetch_ == nullptr) {
      // 老 DLL（没有这个导出）。老实说"做不到"，而不是假装成功 —— 假装成功会
      // 让人以为 A/B 的"关"那一路真的关了。
      result->Error("unsupported", "这个 rossi_gpu_present.dll 没有 set_prefetch 导出");
      return;
    }
    std::lock_guard<std::mutex> guard(mutex_);
    result->Success(flutter::EncodableValue(set_prefetch_(presenter_, enabled ? 1 : 0) == 0));
    return;
  }

  result->NotImplemented();
}
