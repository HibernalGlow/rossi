# GPU 上屏路径（Rust 呈现器 → Flutter 合成）

> 相关：`poc/texture-bridge/`（Gate A 的概念验证）、`docs/phase0-vendor-spike.md`（Gate A 的全部实测）、
> `rust/local_core/`（像素从哪来）、`docs/v0.1-local-core.md`（解码与预取）、`docs/frb_and_cpp_bridge_design.md`。

## 1. 这条路径解决什么

v0.1 的链路里，`解码` 之后是 `上屏`。本地核心已经能把归档直读成像素，但**像素到屏幕的那一段**
曾经只有一条 CPU 兜底路径：Rust 解出 RGBA → 过 FRB 桥成 `Uint8List` → `ui.decodeImageFromPixels`
→ 再上传成 GPU 纹理。这条路在判据 C 上是不可能过的：

- 一页 44.8 MPix 是 **179 MB**；把它搬过语言边界再交回引擎，实测读页一步就多出 ~40 ms 的过桥成本；
- 更要紧的是它**多绕了一圈**：像素本来就在显存里（解码/缩放发生在 Rust 侧），却被搬到内存再送回去。

本路径把它改成：**像素永远在显存里，过桥的只有一句柄和一个整数。**

### 链路

```text
归档文件
  → [Rust] local_core::LocalSource 读条目字节
  → [Rust] 解码（按「显示宽度」解，不是全尺寸）
  → [Rust] wgpu 上传成纹理
  → [Rust] wgpu 渲染：全屏三角形 + letterbox 采样（等比、居中、留底色）
  → [Rust] GPU→GPU CopyResource：wgpu 纹理 → 自建 SHARED 纹理（BGRA8）
  → [Rust] CreateSharedHandle 导出 NT 句柄 ─────────┐
                                                    │ 只有句柄与统计过桥
  ← [C++] TextureRegistrar 注册外部纹理 ←────────────┘
  → [C++] SurfaceCallback 把句柄包成 Descriptor 交给引擎
  → [Dart] Texture(textureId)  ← 只有一个 int
  → Flutter(D3D11/ANGLE) 打开共享纹理合成 → 屏幕
```

与 PoC 的关系：`poc/texture-bridge/` 回答的是**"这条路通不通"**（风险 1：Flutter Windows embedder 收不收
外部 D3D12 共享纹理；风险 2：wgpu 能不能导出共享句柄）。答案是通，但**不能零拷贝**——
这张文档记的是把它接成一条真实的、可诊断的路径时，那些"通"之外还必须成立的事。

## 2. 三层分工

| 层 | 位置 | 只做什么 | 绝不做什么 |
| --- | --- | --- | --- |
| Rust 呈现器 | `rust/gpu_present/`（cdylib） | 解码、上传、letterbox 渲染、GPU 拷贝、导出句柄 | 不知道 Flutter 存在 |
| C++ 桥 | `windows/runner/gpu_present_bridge.{h,cpp}` | 注册纹理、转达引擎请求的尺寸、转达方法调用、通知取帧 | **不碰一个像素** |
| Dart | `lib/gpu/gpu_present_{bridge,page}.dart` | 拿 textureId、放进 `Texture` 组件、显示诊断 | 不碰字节 |

### 2.1 Rust 呈现器

- 入口 `rossi_gpu_present.dll`，10 个 C ABI 函数（`create/destroy/handle/generation/notify_released/`
  `resize/open/page_count/show/stats`）。全部 `catch_unwind`，错误以 UTF-8 回填到调用方给的缓冲。
- **按 Flutter 的 adapter LUID 选卡**。这是硬约束，不是优化：跨 adapter 共享要么失败、要么极慢。
- 解码按**显示宽度**解（`page_pixels_scaled(index, Some(target_width))`）。全尺寸解再缩在
  `docs/v0.1-local-core.md §12.1` 已经量过：像素降 45× 只换 4.6×，不值。
- letterbox 在着色器里做：全屏三角形 + 采样页纹理，**alpha 钉 1.0**（不采样页的 alpha），
  否则每像素都要预乘。
- 呈现目标用 `ensure_target(w, h)` 维护；尺寸变了就重建并**立刻重画当前页**——
  否则拖窗口时会看到一片底色。

### 2.2 C++ 桥

- 用 `LoadLibraryW` 加载 DLL（**不走 import lib**）。理由：不想把 CMake 的链接顺序和 cargo 的构建顺序
  耦在一起，也不想让非 Windows 平台去处理一个根本不存在的产物。
- **失败不阻断启动**：构造里任何一步失败（产物没构建、显卡不支持、注册失败）都只把原因记进 `error()`，
  窗口照常起来，Dart 读 `stats` 就能看到为什么不可用。这比"启动即崩"或"黑屏无提示"都好。
- `SurfaceCallback` 在 **raster 线程**，`show`/`open`/`resize` 在**平台线程**，共用一把 `mutex_`。
  `show` 必须在**释放锁之后**才 `MarkExternalTextureFrameAvailable`——引擎可能同步回调
  `SurfaceCallback`，持锁调用会直接死锁。

### 2.3 Dart 侧

- `lib/gpu/gpu_present_bridge.dart`：MethodChannel `rossi/gpu_present` 的封装，非 Windows 优雅降级。
- `lib/gpu/gpu_present_page.dart`：调试页。入口 **更多 → 全局设置 → 调试 → GPU 上屏（D3D12 共享纹理）**，
  以及导航栏侧栏的第二个诊断按钮。与判据 A 的窗口同理，**刻意不放进 `if (kDebugMode)`**。
- 只给 `init` 传**物理像素**（`constraints * devicePixelRatio`）：Flutter 的纹理按物理像素合成，
  传逻辑尺寸会在 1.5x/2x 屏上得到一张被拉伸的模糊图，而且引擎随后会用另一个尺寸来问
  `SurfaceCallback`，两边永远对不上，形成反复重建——症状是拖窗口时画面闪烁。
- `Texture` 铺满整个盒子是**故意的**：等比缩放与留边已经在 Rust 侧完成，这里再套 `AspectRatio`
  或 `BoxFit` 只会引入第二次缩放。

## 3. 关键设计决定（每条都有代价）

### 3.1 为什么每帧要一次 GPU→GPU 拷贝

**直接共享 wgpu 的纹理不可行**：`CreateSharedHandle` 返回 `E_INVALIDARG`（0x80070057），
因为 wgpu 把纹理建在默认堆、没带 `D3D12_HEAP_FLAG_SHARED`，而 wgpu 27 的公开 API
没有"用外部资源反包 texture"的入口。

于是路径变成：自建 SHARED 纹理 + 同 device/queue 上原生 `CopyResource` + flush。**零拷贝在这个
wgpu 版本上已关闭**，代价是一次显存内拷贝。它值不值有刻度：
`docs/phase0-vendor-spike.md` 实测 RTX 4060 Laptop 上 ~190 GB/s，单次拷贝占 60fps 预算
0.07%（1264×487）／2.1%（4K 单页）／8.3%（8K 双页）——判据写死在那份文档里。

`stats` 里的 `directShareOfWgpuTexture` 会在**启动时实测一次**并把结论原样报出来，
所以"零拷贝到底行不行"这个问题永远有一个当场的答案，而不是靠记忆。

### 3.2 为什么 `release_callback` 传代际号而不是 `this`

引擎注销外部纹理是**异步**的（`UnregisterExternalTexture` 的注释就写着 "Asynchronously unregisters"），
所以 release 回调理论上可能在本对象析构**之后**才到。交出一个可能悬垂的 `this` 不可接受；
交一个整数，即使迟到也只会落到"这一代已经没人认领"的 no-op 上。代价是回调里要找回桥对象，
于是有了一个进程级落点 `g_release_target`，Rust 侧再用 `MAX_RETIRED = 4` 兜底回收。

### 3.3 为什么格式必须是 `B8G8R8A8_UNORM`

Flutter Windows 走 ANGLE/D3D11 打开这张共享纹理来合成，而 **D3D11 打不开 RGBA8 的共享纹理**。
所以 Rust 侧建的、C++ 报给引擎的，两边都钉在 BGRA8。

### 3.4 为什么 `windows` crate 必须与 `wgpu-hal` 同版本

桥要从 Rust 侧拿到裸的 `ID3D12Device` / `ID3D12CommandQueue` 指针并在 C++ 侧当接口用。
`windows` crate 的 COM 接口布局一旦与 `wgpu-hal` 编译时用的那套不一致，
拿到手的就是一个"布局对不上的结构体指针"——不会编译错，只会在调用时炸。当前两边都是 0.58。

## 4. 黑屏的七种原因，与各自的指纹

这一节是这张文档最实用的部分。"黑屏"本身没有信息量，所以调试页第一行永远先报**可区分的原因**：

| 现象 | 指纹 | 去处 |
| --- | --- | --- |
| DLL 没构建/没拷到 exe 旁 | `native ok=false`，`error` 里有"加载 rossi_gpu_present.dll 失败" | `windows/runner/CMakeLists.txt` 的 cargo 命令 |
| DLL 版本不匹配 | `error` 里有"缺少必要的导出符号" | 两边符号表对不上，重编 |
| 创建 wgpu 设备失败 | `error` 里有"wgpu 呈现器创建失败" | 显卡/驱动/DXC |
| 没拿到 Flutter 的 LUID | `luidKnown=false` | 跨卡共享有风险，画面可能不出来或极慢 |
| 纹理没注册 | `tex-1 未注册` | `Register()` 失败 |
| 通知了但没人来取 | `framesMarked>0` 而 `handleOpened=0` | 纹理没被真正合成（不在树上/尺寸为 0） |
| **链路真通** | `handleOpened>0` | —— |

最后一条是这个页面存在的理由：**引擎只有确实把这张纹理拿去合成了，才会来打开我们给的共享句柄**。
`framesMarked` 只证明我们喊过。所以 `handleOpened > 0` 是唯一的硬证据。

## 5. 怎么验证

### 5.1 脱离 Flutter：端到端回读（`present_probe`）

```bash
# 散图文件夹 / CBZ / CBR 都行
cargo run -p rossi_gpu_present --features probe --bin present_probe -- \
  --path <归档或文件夹> --index 0 --width 900 --height 1350
```

它把整条 Rust 侧链路跑一遍（解码→上传→letterbox→拷贝→共享纹理），然后把共享纹理
`COPY_SOURCE` → READBACK 缓冲**回读**，用四条判据自动断言：

1. 底色占比 ≈ letterbox 理论值；
2. 内容包围盒 ≈ 绘制矩形；
3. 页内 25 点采样与"同档位直接解码"的基准逐点一致（最大通道差 0）；
4. 画面非全黑。

`--out` 可落盘 JSON 报告。**这一步不需要 GPU 上屏成功**，所以它能把"Rust 侧像素对不对"
与"Flutter 收不收"分开定位。

### 5.2 真机引擎：集成测试

```bash
flutter test integration_test/gpu_present_probe_test.dart -d windows
```

样本路径可用 `ROSSI_GPU_PRESENT_SAMPLE` 覆盖；样本缺失时静默跳过。
它断言 `framesMarked>0` 与 **`handleOpened>0`**——即"引擎真的来取了这一帧"。
**必须在真机引擎上跑**：`flutter test`（单元测试）跑的是 `flutter_tester`，
软件渲染、没有 Windows embedder、连 `TextureRegistrar` 都没有，在那里"通过"什么也证明不了。

### 5.3 手动观察

调试页可换来源、翻页、看统计。`ROSSI_GPU_PRESENT_SAMPLE` 环境变量可指定默认打开的样本。

## 6. 实测（本轮，2026-09-16）

环境：RTX 4060 Laptop（引擎选的是**独显**；本机还有一块 AMD 780M，但没被用上）。
顺序是先证 Rust 侧像素对，再证引擎真的来取帧。

### 6.1 Rust 侧端到端回读（`present_probe`，不需要 Flutter）

| 来源 | 页 | 解码档位（原图） | decode | upload | submit | 合计 | 底色占比 实测／理论 | 页内 25 点采样 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 散图文件夹 | 1 | 900×1350（1200×1800） | 34.1 ms | 0.4 ms | 2.7 ms | 37.2 ms | 0.037／0.037 | 最大通道差 0 |
| CBZ | 1 | — | — | — | — | — | 全过 | 最大通道差 0 |
| 竖长页 | 3 | — | — | — | — | — | 0.639／0.639 | 最大通道差 0 |

四条判据（底色占比、内容包围盒、页内采样、非全黑）全部通过；竖长页一项同时验证了**左右留边**
（内容包围盒 287–612 对理论 288–612，差 1 px 是采样取整）。
`directShareOfWgpuTexture` 稳定报 **`失败 -2147024809`**（= `E_INVALIDARG`），与 §3.1 一致 ——
这不是"哪里坏了"，而是**零拷贝本来就不通、必须多走一次拷贝**的当场证据。

### 6.2 真机引擎（`gpu_present_probe_test.dart`）

```bash
flutter test integration_test/gpu_present_probe_test.dart -d windows
```

```
native ok=true  adapter=NVIDIA GeForce RTX 4060 Laptop GPU  luidKnown=true
textureId = 1580768096
pageCount = 3
framesMarked=1  handleOpened=1  resizes=1  size=800x600
```

**`handleOpened = 1` —— 引擎真的打开了我们给的共享句柄，屏幕上的画面来自 Rust 侧那张纹理。**
这是本轮唯一的硬判据，它过了。

同一轮 Rust 侧上报的 `probe`：

```
adapterMatched: true        adapterLuid == targetLuid == 0x144ba
copyPath: "GPU->GPU CopyResource"
directShareOfWgpuTexture: "失败 -2147024809"
decoded 800x1200   ←   source 1200x1800      （按显示宽度解，不是全尺寸）
decodeMs 29.0 / uploadMs 0.4 / submitMs 6.5 / totalMs 36.0
```

两点值得单独记下来：

- **`adapterMatched: true` 不是理所当然的。** 单独跑 `present_probe` 时挑中的是本机的
  **AMD 780M**，而在 App 里必须是 Flutter 正在用的那块卡（这里是 RTX 4060）。两边 LUID 对上，
  共享才谈得上成立 —— 这也是 §3.4 那条硬约束的存在理由。
- **`initMs ≈ 982 ms` 是启动期成本。** 创建 wgpu device + 管线目前发生在
  `flutter_window.cpp::OnCreate` 里，**因此压在第一帧之前**。判据 B（冷启动 ≤2 s）要把它算进去 ——
  见 §7 第一条。

## 7. 还没做的

- **启动期那 ~1 s 要挪走。** `initMs ≈ 982 ms`（wgpu device + 管线）现在压在第一帧之前，
  直接吃判据 B 的预算。做法是让呈现器**首次使用时才创建**（第一次 `init` 或第一次
  `SurfaceCallback`），或至少挪到首帧之后。但要注意：一旦 GPU 上屏成为阅读器的**主路径**，
  这笔成本还是会在启动期出现 —— 那时要的是"后台创建 + 就绪前走兜底路径"，而不是简单挪位置。
- **判据 C 还没量。** 本轮只证明"链路真通"，帧时间分布（p95/p99、无 >100 ms 单帧）要在
  **Release** 下用真实漫画量，见 `docs/v0.1_acceptance.md`。
- **Release 配置下的打包未复验。** 本轮验证走的是 Debug 配置（集成测试的默认）。CMake 的
  自定义命令与 POST_BUILD 是**配置无关**的，但 Release 产物里 `rossi_gpu_present.dll` 与两个
  DXC DLL 的落位，应该在量判据 C 时一并确认。
- **tile / LRU / 双页**：当前一次只呈现一页，且是整页一张纹理。
- **"copy 按需而非每帧"**：现在每次 `show` 一次拷贝；连续动画场景要按需，判据见 §3.1。
- **预取与呈现的联动**：本地核心的预取判决已经能给目标，但呈现器还没消费它
  （`should_prefetch_final_effect` 未桥接）。
- **超分**：Phase 3 的事。当前着色器只做 letterbox 采样，留了插入点但没实现。
- **macOS / Linux 上屏**：本路径是 Windows 专属（D3D12 共享纹理）。别的平台仍只有 CPU 兜底。
- **外壳路径（jpg 归档）的预取。**
