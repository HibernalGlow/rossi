#include "wgpu_texture_poc.h"

#include <dxgi.h>

#include <algorithm>
#include <cstring>
#include <vector>

namespace {

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

// 取 Flutter 正在使用的那块 adapter 的 LUID。
//
// 这是硬约束而不是优化：Rust 侧必须选中同一块卡，否则共享纹理要么创建失败，
// 要么被驱动扔进极慢的跨适配器拷贝路径，Gate A 的性能结论就失去意义。
bool ResolveFlutterAdapterLuid(flutter::FlutterEngine* engine, uint64_t* out_luid) {
  if (engine == nullptr || out_luid == nullptr) {
    return false;
  }
  IDXGIAdapter* raw_adapter = nullptr;
  if (!engine->GetGraphicsAdapter(&raw_adapter) || raw_adapter == nullptr) {
    if (raw_adapter != nullptr) {
      raw_adapter->Release();
    }
    return false;
  }

  DXGI_ADAPTER_DESC desc{};
  const HRESULT hr = raw_adapter->GetDesc(&desc);
  raw_adapter->Release();
  if (FAILED(hr)) {
    return false;
  }

  // HighPart 是 LONG（有符号），先转无符号再拼，避免高位被符号扩展。
  *out_luid =
      (static_cast<uint64_t>(static_cast<uint32_t>(desc.AdapterLuid.HighPart))
       << 32) |
      static_cast<uint64_t>(desc.AdapterLuid.LowPart);
  return true;
}

}  // namespace

WgpuTexturePoc::WgpuTexturePoc(flutter::FlutterEngine* engine,
                               FlutterDesktopTextureRegistrarRef texture_registrar)
    : engine_(engine), texture_registrar_(texture_registrar) {
  if (engine_ == nullptr) {
    SetError("engine 为空");
    return;
  }
  if (texture_registrar_ == nullptr) {
    SetError("texture registrar 为空");
    return;
  }
  if (!LoadProbeLibrary()) {
    return;
  }

  uint64_t luid = 0;
  luid_known_ = ResolveFlutterAdapterLuid(engine_, &luid);
  adapter_luid_ = luid;

  // 探针内部会：选同 LUID 的 adapter → 建 wgpu device → 建共享纹理并导出
  // handle → 实测「直接共享 wgpu texture」的 HRESULT。
  // 首次调用还要编译 WGSL（走 DXC），可能耗时数百毫秒。
  std::vector<uint8_t> err(1024, 0);
  probe_ = create_(adapter_luid_, 256, 256, err.data(),
                   static_cast<size_t>(err.size()));
  if (probe_ == nullptr) {
    SetError(std::string("wgpu 探针创建失败: ") +
             reinterpret_cast<const char*>(err.data()));
    return;
  }

  shared_handle_ = get_handle_(probe_);

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine_->messenger(), "rossi/poc/wgpu_bridge",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  ok_ = true;
}

WgpuTexturePoc::~WgpuTexturePoc() {
  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        texture_registrar_, texture_id_, nullptr, nullptr);
    texture_id_ = -1;
  }

  channel_.reset();

  // 必须先销毁探针再卸载 DLL：探针的析构函数在 DLL 里。
  if (probe_ != nullptr && destroy_ != nullptr) {
    destroy_(probe_);
    probe_ = nullptr;
  }
  shared_handle_ = nullptr;

  if (library_ != nullptr) {
    FreeLibrary(library_);
    library_ = nullptr;
  }
}

void WgpuTexturePoc::SetError(const std::string& message) {
  if (error_.empty()) {
    error_ = message;
  }
}

bool WgpuTexturePoc::LoadProbeLibrary() {
  library_ = ::LoadLibraryW(L"wgpu_probe.dll");
  if (library_ == nullptr) {
    SetError("加载 wgpu_probe.dll 失败（错误码 " +
             std::to_string(::GetLastError()) + "）");
    return false;
  }

  // MSVC 对 FARPROC → 函数指针的转换报 C4191，而本工程开了 /WX。
  // 这里只取自己 DLL 自己导出的符号，转换是安全的。
#pragma warning(push)
#pragma warning(disable : 4191)
  create_ = reinterpret_cast<CreateFn>(::GetProcAddress(library_, "wgpu_probe_create"));
  get_handle_ = reinterpret_cast<HandleFn>(::GetProcAddress(library_, "wgpu_probe_handle"));
  render_ = reinterpret_cast<RenderFn>(::GetProcAddress(library_, "wgpu_probe_render"));
  resize_ = reinterpret_cast<ResizeFn>(::GetProcAddress(library_, "wgpu_probe_resize"));
  recreate_ = reinterpret_cast<RecreateFn>(::GetProcAddress(library_, "wgpu_probe_recreate"));
  stats_ = reinterpret_cast<StatsFn>(::GetProcAddress(library_, "wgpu_probe_stats"));
  destroy_ = reinterpret_cast<DestroyFn>(::GetProcAddress(library_, "wgpu_probe_destroy"));
#pragma warning(pop)

  if (create_ == nullptr || get_handle_ == nullptr || render_ == nullptr ||
      resize_ == nullptr || stats_ == nullptr || destroy_ == nullptr) {
    SetError("wgpu_probe.dll 缺少必要的导出符号");
    return false;
  }
  return true;
}

bool WgpuTexturePoc::Register() {
  if (!ok_) {
    return false;
  }

  FlutterDesktopGpuSurfaceTextureConfig gpu_config{};
  gpu_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
  gpu_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  gpu_config.callback = &WgpuTexturePoc::SurfaceCallback;
  gpu_config.user_data = this;

  FlutterDesktopTextureInfo info{};
  info.type = kFlutterDesktopGpuSurfaceTexture;
  info.gpu_surface_config = gpu_config;

  texture_id_ = FlutterDesktopTextureRegistrarRegisterExternalTexture(
      texture_registrar_, &info);
  if (texture_id_ < 0) {
    SetError("RegisterExternalTexture 失败");
    ok_ = false;
    return false;
  }
  return true;
}

// 引擎以它想要的像素尺寸来要 surface，尺寸变化就在这里发生。
const FlutterDesktopGpuSurfaceDescriptor* WgpuTexturePoc::SurfaceCallback(
    size_t width, size_t height, void* user_data) {
  auto* self = static_cast<WgpuTexturePoc*>(user_data);
  if (self == nullptr || !self->ok_ || self->probe_ == nullptr) {
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(self->mutex_);

  UINT target_width = static_cast<UINT>(width > 0 ? width : 256);
  UINT target_height = static_cast<UINT>(height > 0 ? height : 256);
  target_width = std::min<UINT>(target_width, 8192);
  target_height = std::min<UINT>(target_height, 8192);

  if (self->shared_handle_ == nullptr || self->width_ != target_width ||
      self->height_ != target_height) {
    void* handle = self->resize_(self->probe_, target_width, target_height);
    if (handle == nullptr) {
      return nullptr;
    }
    self->shared_handle_ = handle;
    self->width_ = target_width;
    self->height_ = target_height;
    self->recreate_count_++;

    self->descriptor_ = {};
    self->descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    self->descriptor_.handle = handle;
    self->descriptor_.width = target_width;
    self->descriptor_.height = target_height;
    self->descriptor_.visible_width = target_width;
    self->descriptor_.visible_height = target_height;
    self->descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
    self->descriptor_.release_callback = &WgpuTexturePoc::OnHandleOpened;
    self->descriptor_.release_context = self;
  }

  return &self->descriptor_;
}

void WgpuTexturePoc::OnHandleOpened(void* release_context) {
  auto* self = static_cast<WgpuTexturePoc*>(release_context);
  if (self != nullptr) {
    self->handle_opened_count_++;
  }
}

bool WgpuTexturePoc::RenderFrame(float phase) {
  if (!ok_ || probe_ == nullptr) {
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    const int32_t rc = render_(probe_, phase);
    if (rc != 0) {
      SetError("wgpu 探针渲染失败，返回码 " + std::to_string(rc));
      return false;
    }
    frame_count_++;
  }

  // 必须在释放 mutex 之后再通知引擎：引擎可能同步回调 SurfaceCallback，
  // 而 SurfaceCallback 要拿同一把锁，持锁调用会直接死锁。
  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
        texture_registrar_, texture_id_);
  }
  return true;
}

bool WgpuTexturePoc::ForceRecreate() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!ok_ || probe_ == nullptr || recreate_ == nullptr) {
    return false;
  }
  void* handle = recreate_(probe_);
  if (handle == nullptr) {
    return false;
  }
  shared_handle_ = handle;
  descriptor_.handle = handle;
  recreate_count_++;
  return true;
}

flutter::EncodableMap WgpuTexturePoc::BuildStats() {
  std::lock_guard<std::mutex> lock(mutex_);

  // 探针内部状态（含那条关键证据 directShareOfWgpuTexture）以 JSON 形式取回，
  // 直接透传给 Dart，避免两侧结构体定义要手动保持同步。
  if (stats_ != nullptr && probe_ != nullptr) {
    std::vector<uint8_t> buf(2048, 0);
    const int32_t n =
        stats_(probe_, buf.data(), static_cast<size_t>(buf.size()));
    if (n > 0) {
      last_probe_stats_ = reinterpret_cast<const char*>(buf.data());
    }
  }

  flutter::EncodableMap map;
  map[flutter::EncodableValue("ok")] =
      flutter::EncodableValue(ok_ && shared_handle_ != nullptr);
  map[flutter::EncodableValue("error")] = flutter::EncodableValue(error_);
  map[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(static_cast<int64_t>(texture_id_));
  map[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int32_t>(width_));
  map[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int32_t>(height_));
  map[flutter::EncodableValue("frames")] =
      flutter::EncodableValue(static_cast<int64_t>(frame_count_));
  map[flutter::EncodableValue("recreates")] =
      flutter::EncodableValue(static_cast<int32_t>(recreate_count_));
  map[flutter::EncodableValue("handleOpened")] =
      flutter::EncodableValue(static_cast<int32_t>(handle_opened_count_));
  map[flutter::EncodableValue("luidKnown")] =
      flutter::EncodableValue(luid_known_);
  map[flutter::EncodableValue("adapterLuid")] = flutter::EncodableValue(
      static_cast<int64_t>(adapter_luid_ & 0x7FFFFFFFFFFFFFFFLL));
  map[flutter::EncodableValue("probe")] =
      flutter::EncodableValue(last_probe_stats_);
  return map;
}

void WgpuTexturePoc::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "getStats") {
    result->Success(flutter::EncodableValue(BuildStats()));
    return;
  }

  if (method == "renderFrame") {
    float phase = 0.0f;
    const auto* arguments = call.arguments();
    if (arguments != nullptr) {
      const auto* map = std::get_if<flutter::EncodableMap>(arguments);
      if (map != nullptr) {
        const auto it = map->find(flutter::EncodableValue("phase"));
        if (it != map->end()) {
          if (const auto* value = std::get_if<double>(&it->second)) {
            phase = static_cast<float>(*value);
          }
        }
      }
    }
    result->Success(flutter::EncodableValue(RenderFrame(phase)));
    return;
  }

  if (method == "forceRecreate") {
    result->Success(flutter::EncodableValue(ForceRecreate()));
    return;
  }

  result->NotImplemented();
}
