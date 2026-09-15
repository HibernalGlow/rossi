#include "gpu_texture_poc.h"

#include <algorithm>
#include <cstdio>
#include <utility>

namespace {

std::string HrToHex(HRESULT hr) {
  char buffer[16] = {};
  std::snprintf(buffer, sizeof(buffer), "0x%08lX",
                static_cast<unsigned long>(hr));
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

// 用带 rect 的 ClearRenderTargetView 画一个色块。
// 这样整个 PoC 不需要 shader / PSO / 顶点缓冲，把变量压到最少。
void ClearRect(ID3D12GraphicsCommandList* list,
               const D3D12_CPU_DESCRIPTOR_HANDLE& rtv, const FLOAT color[4],
               LONG left, LONG top, LONG right, LONG bottom) {
  if (right <= left || bottom <= top) {
    return;
  }
  D3D12_RECT rect{};
  rect.left = left;
  rect.top = top;
  rect.right = right;
  rect.bottom = bottom;
  list->ClearRenderTargetView(rtv, color, 1, &rect);
}

}  // namespace

GpuTexturePoc::GpuTexturePoc(flutter::FlutterEngine* engine,
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
  if (!InitDevice()) {
    return;
  }

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine_->messenger(), "rossi/poc/texture_bridge",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  ok_ = true;
}

GpuTexturePoc::~GpuTexturePoc() {
  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        texture_registrar_, texture_id_, nullptr, nullptr);
    texture_id_ = -1;
  }

  for (auto& retired : retired_) {
    if (retired.handle != nullptr) {
      CloseHandle(retired.handle);
      retired.handle = nullptr;
    }
  }
  retired_.clear();

  if (shared_handle_ != nullptr) {
    CloseHandle(shared_handle_);
    shared_handle_ = nullptr;
  }
  texture_.Reset();
  rtv_heap_.Reset();

  if (fence_event_ != nullptr) {
    CloseHandle(fence_event_);
    fence_event_ = nullptr;
  }
  fence_.Reset();
  command_list_.Reset();
  allocator_.Reset();
  queue_.Reset();
  device_.Reset();
}

void GpuTexturePoc::SetError(const std::string& message) {
  if (error_.empty()) {
    error_ = message;
  }
}

bool GpuTexturePoc::InitDevice() {
  // 不启用 debug layer：部分机器没装 Graphics Tools，开了会直接创建失败。
  HRESULT hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&factory_));
  if (FAILED(hr)) {
    SetError("CreateDXGIFactory2 失败 " + HrToHex(hr));
    return false;
  }

  // 优先复用 Flutter 自己所在的 adapter。
  // 跨 adapter 共享 texture 在多数机器上会失败或掉进极慢的拷贝路径，
  // 所以这一条对后面的 wgpu 集成是硬约束。
  if (engine_ != nullptr) {
    IDXGIAdapter* raw_adapter = nullptr;
    if (engine_->GetGraphicsAdapter(&raw_adapter) && raw_adapter != nullptr) {
      adapter_.Attach(raw_adapter);
      using_flutter_adapter_ = true;
    } else if (raw_adapter != nullptr) {
      raw_adapter->Release();
    }
  }

  if (!adapter_) {
    hr = factory_->EnumAdapterByGpuPreference(
        0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter_));
    if (FAILED(hr)) {
      SetError("枚举 DXGI adapter 失败 " + HrToHex(hr));
      return false;
    }
    using_flutter_adapter_ = false;
  }

  DXGI_ADAPTER_DESC adapter_desc{};
  if (SUCCEEDED(adapter_->GetDesc(&adapter_desc))) {
    adapter_name_ = WideToUtf8(adapter_desc.Description);
  }

  hr = D3D12CreateDevice(adapter_.Get(), D3D_FEATURE_LEVEL_11_0,
                         IID_PPV_ARGS(&device_));
  if (FAILED(hr)) {
    SetError("D3D12CreateDevice 失败 " + HrToHex(hr));
    return false;
  }

  D3D12_COMMAND_QUEUE_DESC queue_desc{};
  queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
  queue_desc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
  queue_desc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
  queue_desc.NodeMask = 0;
  hr = device_->CreateCommandQueue(&queue_desc, IID_PPV_ARGS(&queue_));
  if (FAILED(hr)) {
    SetError("CreateCommandQueue 失败 " + HrToHex(hr));
    return false;
  }

  hr = device_->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                       IID_PPV_ARGS(&allocator_));
  if (FAILED(hr)) {
    SetError("CreateCommandAllocator 失败 " + HrToHex(hr));
    return false;
  }

  hr = device_->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                  allocator_.Get(), nullptr,
                                  IID_PPV_ARGS(&command_list_));
  if (FAILED(hr)) {
    SetError("CreateCommandList 失败 " + HrToHex(hr));
    return false;
  }
  command_list_->Close();

  hr = device_->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence_));
  if (FAILED(hr)) {
    SetError("CreateFence 失败 " + HrToHex(hr));
    return false;
  }
  fence_event_ = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (fence_event_ == nullptr) {
    SetError("CreateEvent 失败");
    return false;
  }

  return true;
}

bool GpuTexturePoc::CreateSizeDependentResources(UINT width, UINT height) {
  if (width == 0 || height == 0) {
    SetError("非法尺寸");
    return false;
  }

  // 旧资源不能立即析构：引擎可能还持有由旧 handle 打开出来的合成纹理。
  // 先挪进 retired_，由 ReclaimRetiredResources 延迟回收。
  if (texture_ || shared_handle_ != nullptr) {
    RetiredResource retired;
    retired.resource = std::move(texture_);
    retired.handle = shared_handle_;
    retired_.push_back(std::move(retired));
    shared_handle_ = nullptr;
    rtv_heap_.Reset();
    rtv_ = {};
  }

  D3D12_HEAP_PROPERTIES heap_properties{};
  heap_properties.Type = D3D12_HEAP_TYPE_DEFAULT;
  heap_properties.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
  heap_properties.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
  heap_properties.CreationNodeMask = 1;
  heap_properties.VisibleNodeMask = 1;

  D3D12_RESOURCE_DESC resource_desc{};
  resource_desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  resource_desc.Alignment = 0;
  resource_desc.Width = width;
  resource_desc.Height = height;
  resource_desc.DepthOrArraySize = 1;
  resource_desc.MipLevels = 1;
  // 必须是 BGRA8：Flutter Windows 走 ANGLE / D3D11 合成，
  // 而 D3D11 打不开 RGBA8 的 shared texture。
  resource_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  resource_desc.SampleDesc.Count = 1;
  resource_desc.SampleDesc.Quality = 0;
  resource_desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
  resource_desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

  D3D12_CLEAR_VALUE clear_value{};
  clear_value.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  for (int i = 0; i < 4; ++i) {
    clear_value.Color[i] = 0.0f;
  }

  HRESULT hr = device_->CreateCommittedResource(
      &heap_properties, D3D12_HEAP_FLAG_SHARED, &resource_desc,
      D3D12_RESOURCE_STATE_COMMON, &clear_value, IID_PPV_ARGS(&texture_));
  if (FAILED(hr)) {
    SetError("CreateCommittedResource 失败 " + HrToHex(hr));
    return false;
  }

  D3D12_DESCRIPTOR_HEAP_DESC heap_desc{};
  heap_desc.NumDescriptors = 1;
  heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
  heap_desc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
  heap_desc.NodeMask = 0;
  hr = device_->CreateDescriptorHeap(&heap_desc, IID_PPV_ARGS(&rtv_heap_));
  if (FAILED(hr)) {
    SetError("CreateDescriptorHeap 失败 " + HrToHex(hr));
    return false;
  }
  rtv_ = rtv_heap_->GetCPUDescriptorHandleForHeapStart();
  device_->CreateRenderTargetView(texture_.Get(), nullptr, rtv_);

  hr = device_->CreateSharedHandle(texture_.Get(), nullptr, GENERIC_ALL,
                                   nullptr, &shared_handle_);
  if (FAILED(hr)) {
    SetError("CreateSharedHandle 失败 " + HrToHex(hr));
    return false;
  }

  width_ = width;
  height_ = height;
  recreate_count_++;

  descriptor_ = {};
  descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  descriptor_.handle = shared_handle_;
  descriptor_.width = width;
  descriptor_.height = height;
  descriptor_.visible_width = width;
  descriptor_.visible_height = height;
  descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
  descriptor_.release_callback = &GpuTexturePoc::OnHandleOpened;
  descriptor_.release_context = this;

  return true;
}

void GpuTexturePoc::ReleaseSizeDependentResources() {
  texture_.Reset();
  rtv_heap_.Reset();
  rtv_ = {};
  width_ = 0;
  height_ = 0;
}

void GpuTexturePoc::ReclaimRetiredResources() {
  // 保留最近两个：刚刚被替换掉的纹理可能仍在引擎的合成链上。
  constexpr size_t kKeepAlive = 2;
  while (retired_.size() > kKeepAlive) {
    RetiredResource oldest = std::move(retired_.front());
    retired_.erase(retired_.begin());
    if (oldest.handle != nullptr) {
      CloseHandle(oldest.handle);
      oldest.handle = nullptr;
    }
    // oldest.resource 随作用域结束释放。
  }
}

// 引擎以它想要的像素尺寸来问我们要 surface。
// 尺寸变化就在这里发生 —— 这正是 Gate A 要验证的「销毁与重建」路径。
const FlutterDesktopGpuSurfaceDescriptor* GpuTexturePoc::SurfaceCallback(
    size_t width, size_t height, void* user_data) {
  auto* self = static_cast<GpuTexturePoc*>(user_data);
  if (self == nullptr) {
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(self->mutex_);
  self->ReclaimRetiredResources();

  UINT target_width = static_cast<UINT>(width > 0 ? width : 256);
  UINT target_height = static_cast<UINT>(height > 0 ? height : 256);
  target_width = std::min<UINT>(target_width, 8192);
  target_height = std::min<UINT>(target_height, 8192);

  if (!self->texture_ || self->width_ != target_width ||
      self->height_ != target_height) {
    if (!self->CreateSizeDependentResources(target_width, target_height)) {
      return nullptr;
    }
  }
  return &self->descriptor_;
}

void GpuTexturePoc::OnHandleOpened(void* release_context) {
  auto* self = static_cast<GpuTexturePoc*>(release_context);
  if (self != nullptr) {
    self->handle_opened_count_++;
  }
}

bool GpuTexturePoc::Register() {
  if (!ok_) {
    return false;
  }

  FlutterDesktopGpuSurfaceTextureConfig gpu_config{};
  gpu_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
  gpu_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  gpu_config.callback = &GpuTexturePoc::SurfaceCallback;
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

bool GpuTexturePoc::RenderFrame(float phase) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!ok_ || !texture_ || !command_list_) {
      return false;
    }
    last_phase_ = phase;

    HRESULT hr = allocator_->Reset();
    if (FAILED(hr)) {
      SetError("CommandAllocator::Reset 失败 " + HrToHex(hr));
      return false;
    }
    hr = command_list_->Reset(allocator_.Get(), nullptr);
    if (FAILED(hr)) {
      SetError("CommandList::Reset 失败 " + HrToHex(hr));
      return false;
    }

    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
    barrier.Transition.pResource = texture_.Get();
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
    command_list_->ResourceBarrier(1, &barrier);

    const LONG w = static_cast<LONG>(width_);
    const LONG h = static_cast<LONG>(height_);

    const FLOAT background[4] = {0.05f, 0.06f, 0.09f, 1.0f};
    command_list_->ClearRenderTargetView(rtv_, background, 0, nullptr);

    // 顶部三条纯色带：红 / 绿 / 蓝。
    // 屏幕上从左到右是红绿蓝 => BGRA 通道顺序正确。
    // 若红蓝互换 => Flutter 把格式当 RGBA 解释了，这正是要抓的 bug。
    const FLOAT red[4] = {1.0f, 0.0f, 0.0f, 1.0f};
    const FLOAT green[4] = {0.0f, 1.0f, 0.0f, 1.0f};
    const FLOAT blue[4] = {0.0f, 0.0f, 1.0f, 1.0f};
    const LONG band_bottom = h / 3;
    ClearRect(command_list_.Get(), rtv_, red, 0, 0, w / 3, band_bottom);
    ClearRect(command_list_.Get(), rtv_, green, w / 3, 0, (w * 2) / 3,
              band_bottom);
    ClearRect(command_list_.Get(), rtv_, blue, (w * 2) / 3, 0, w, band_bottom);

    // 归一化到 [0,1)，避免 Dart 侧传进来负数或超大值。
    float normalized = phase - static_cast<float>(static_cast<int>(phase));
    if (normalized < 0.0f) {
      normalized += 1.0f;
    }

    // 中部一个随 phase 左右移动的白色方块：证明帧在持续更新，不是只画一次。
    const LONG box_w = std::max<LONG>(8, w / 12);
    const LONG box_h = std::max<LONG>(8, h / 12);
    const LONG travel = std::max<LONG>(1, w - box_w);
    const LONG box_x = static_cast<LONG>(normalized * static_cast<float>(travel));
    const LONG box_y = h / 2 - box_h / 2;
    const FLOAT white[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    ClearRect(command_list_.Get(), rtv_, white, box_x, box_y, box_x + box_w,
              box_y + box_h);

    // 底部三分之一随 phase 变色的带子。
    const FLOAT sweep[4] = {normalized, 1.0f - normalized, 0.5f, 1.0f};
    ClearRect(command_list_.Get(), rtv_, sweep, 0, (h * 2) / 3, w, h);

    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COMMON;
    command_list_->ResourceBarrier(1, &barrier);

    hr = command_list_->Close();
    if (FAILED(hr)) {
      SetError("CommandList::Close 失败 " + HrToHex(hr));
      return false;
    }

    ID3D12CommandList* lists[] = {command_list_.Get()};
    queue_->ExecuteCommandLists(1, lists);

    const UINT64 value = ++fence_value_;
    hr = queue_->Signal(fence_.Get(), value);
    if (FAILED(hr)) {
      SetError("CommandQueue::Signal 失败 " + HrToHex(hr));
      return false;
    }
    if (fence_->GetCompletedValue() < value) {
      fence_->SetEventOnCompletion(value, fence_event_);
      WaitForSingleObject(fence_event_, 2000);
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

bool GpuTexturePoc::ForceRecreate() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!ok_) {
    return false;
  }
  const UINT target_width = width_ > 0 ? width_ : 256;
  const UINT target_height = height_ > 0 ? height_ : 256;
  return CreateSizeDependentResources(target_width, target_height);
}

flutter::EncodableMap GpuTexturePoc::BuildStats() const {
  std::lock_guard<std::mutex> lock(mutex_);
  flutter::EncodableMap map;
  map[flutter::EncodableValue("ok")] = flutter::EncodableValue(ok_);
  map[flutter::EncodableValue("error")] = flutter::EncodableValue(error_);
  map[flutter::EncodableValue("adapter")] = flutter::EncodableValue(adapter_name_);
  map[flutter::EncodableValue("usingFlutterAdapter")] =
      flutter::EncodableValue(using_flutter_adapter_);
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
  map[flutter::EncodableValue("retired")] =
      flutter::EncodableValue(static_cast<int32_t>(retired_.size()));
  return map;
}

void GpuTexturePoc::HandleMethodCall(
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
