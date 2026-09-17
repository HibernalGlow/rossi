#include "gpu_present_bridge.h"

#include <algorithm>
#include <cstdio>
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

  ok_ = true;
}

GpuPresentBridge::~GpuPresentBridge() {
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

  std::lock_guard<std::mutex> guard(self->mutex_);

  // 未就绪时没有句柄可给，只能回 nullptr（语义是"这一帧没有 surface"，合法）。
  // 把 `shared_handle_` 的初始值 nullptr 当成合法句柄交出去就不是合法用法了。
  //
  // 正常流程里走不到这里：Dart 侧在收到 `ready` 之前不构建 `Texture`，
  // 引擎也就不会来要帧。这一段是防误用，不是主路径。
  if (self->QueryStateLocked(nullptr) != kGpuStateReady) {
    return nullptr;
  }

  const uint32_t target_width =
      static_cast<uint32_t>(width > 0 ? std::min<size_t>(width, 8192) : 1);
  const uint32_t target_height =
      static_cast<uint32_t>(height > 0 ? std::min<size_t>(height, 8192) : 1);

  if (!self->SyncTarget(target_width, target_height)) {
    return nullptr;
  }
  return &self->descriptor_;
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
  if (shared_handle_ != nullptr && width_ == width && height_ == height) {
    return true;
  }

  std::vector<uint8_t> err(1024, 0);
  void* handle = resize_(presenter_, width, height, err.data(), static_cast<size_t>(err.size()));
  if (handle == nullptr) {
    error_ = std::string("resize 失败: ") + reinterpret_cast<const char*>(err.data());
    return false;
  }

  shared_handle_ = handle;
  width_ = width;
  height_ = height;
  generation_ = generation_fn_(presenter_);
  resize_count_++;
  RefreshDescriptor();
  return true;
}

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
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(width_));
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(height_));
  map[flutter::EncodableValue("adapter")] = flutter::EncodableValue(adapter_name_);
  map[flutter::EncodableValue("luidKnown")] = flutter::EncodableValue(luid_known_);
  map[flutter::EncodableValue("adapterLuid")] = flutter::EncodableValue(
      static_cast<int64_t>(adapter_luid_ & 0x7FFFFFFFFFFFFFFFLL));
  map[flutter::EncodableValue("generation")] =
      flutter::EncodableValue(static_cast<int64_t>(generation_));
  map[flutter::EncodableValue("framesMarked")] =
      flutter::EncodableValue(static_cast<int64_t>(frames_marked_));
  // 这一条是"链路真的通了"的硬证据：引擎只有确实把这张纹理合成了才会打开句柄。
  map[flutter::EncodableValue("handleOpened")] =
      flutter::EncodableValue(static_cast<int64_t>(handle_opened_));
  map[flutter::EncodableValue("resizes")] =
      flutter::EncodableValue(static_cast<int32_t>(resize_count_));
  map[flutter::EncodableValue("pageCount")] =
      flutter::EncodableValue(static_cast<int32_t>(last_open_page_count_));
  map[flutter::EncodableValue("probe")] = flutter::EncodableValue(probe_json);
  return map;
}

void GpuPresentBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

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

    {
      std::lock_guard<std::mutex> guard(mutex_);
      if (QueryStateLocked(nullptr) != kGpuStateReady) {
        result->Error("not-ready", "呈现器尚未就绪，此刻应走兜底路径");
        return;
      }
      std::vector<uint8_t> err(1024, 0);
      const int32_t rc = show_(presenter_, static_cast<uint32_t>(index), err.data(),
                               static_cast<size_t>(err.size()));
      if (rc != 0) {
        result->Error("show-failed", reinterpret_cast<const char*>(err.data()));
        return;
      }
    }

    // 必须在**释放锁之后**再通知引擎：引擎可能同步回调 SurfaceCallback，
    // 而 SurfaceCallback 要拿同一把锁，持锁调用会直接死锁。
    if (texture_registrar_ != nullptr && texture_id_ >= 0) {
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(texture_registrar_,
                                                                      texture_id_);
      std::lock_guard<std::mutex> guard(mutex_);
      frames_marked_++;
    }
    result->Success(flutter::EncodableValue(true));
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
