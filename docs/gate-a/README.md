# Gate A — GPU Texture PoC 验证记录

> 对应 `docs/ROADMAP.md` 的决策门 **Gate A**（已按 ADR-0004 拆成两只门）：
>
> - **Gate A-W（Windows）：已通过。** 可行性两条路径都已证完。
> - **Gate A-M（macOS）：尚未进行**，与 A-W 等价，**不阻塞 Phase 1–2**，是显式技术债。
>
> 旧表述「Gate A 在 Windows 与 macOS 上均达标后才允许进入 Phase 2」**已废弃**。
>
> 本文记录 Gate A 的**分步验证过程与结论**。仍未量化的两项：Release 下的行为与性能、
> 以及对照基线（现有 Reader 的帧率 / 内存 / 翻页延迟，Phase 0 未勾选项）。
>
> 本文覆盖前两条路径（外部纹理共享）。针对「能否绕开共享」评估的第三条路径见
> [`flutter-gpu-path.md`](./flutter-gpu-path.md)：Flutter GPU 在 Windows 上实测可用，
> 但**无法与 wgpu 共存，且没有 compute**。

## 0. 为什么要把 Gate A 拆成两个独立风险

Gate A 的验证链是：

```text
Rust wgpu 渲染 → 导出 GPU 资源句柄 → Flutter 合成上屏
```

这条链上串着两个**互不相关**的风险，失败模式与排查成本差一个量级：

| | 风险 | 内容 | 排查成本 |
|---|---|---|---|
| **风险 1** | Flutter 侧通道是否可用 | Flutter Windows/macOS embedder 能不能收下一张外部创建的 GPU texture 并正确合成 | 低（不涉及 wgpu） |
| **风险 2** | wgpu 能否导出可用句柄 | wgpu 上游不提供开箱的跨设备共享导出，需 `as_hal` 摸到 `d3d12::Device` 自行 `CreateSharedHandle` | 高（unsafe + 格式/时序约束） |

两件事一起做，一旦画面不对就无法判断是 embedder 不接受句柄、还是 wgpu 根本导不出来。
因此按风险 1 → 风险 2 的顺序分开验。

## 1. 结论速览

| 项 | 结论 | 依据 |
|---|---|---|
| 风险 1（native 路径） | **Windows 通过** | 引擎每帧消费我们的帧；像素零误差 |
| 风险 2（wgpu 路径） | **Windows 通过（需一次 GPU 拷贝）** | 同 adapter、像素零误差、帧持续 |
| **wgpu texture 直接共享** | **不可行**（实测被拒） | `CreateSharedHandle` 返回 `E_INVALIDARG` |
| 零拷贝反包 wgpu | **公开 API 不支持** | `Dx12Texture` 字段私有，只有单向 `raw_resource()` |
| resize 稳定性 | 通过 | 120 次尺寸变化，重建/释放完全配对 |
| 持续运行稳定性 | 通过 | 70 s 帧率 163→164 fps，内存平坦 |
| **那次 GPU 拷贝的成本** | **已量化** | 视口 0.07%–0.56%，4K 单页 2.1%，8K 双页 8.3%（§3.5） |
| Release 下性能量化 | **未做** | 当前结论全部来自 Debug 构建 |
| macOS 侧 | **未做** | 当前无可用 Mac（按约定标记待定） |
| 对照基线 | **未采集** | ROADMAP Phase 0 未勾选项 |

验证工程：`poc/texture-bridge/`（独立最小 Flutter 工程，不依赖 Breeze 主工程）。
同一套像素约定跑两条路径，Dart 侧可在 `native` / `wgpu` 之间切换比对。

两条路径都画：顶部红/绿/蓝三条纯色竖带（通道顺序）、中部左右往返的白色方块
（证明持续出帧）、底部随相位渐变的横条。像素约定一致，所以截屏校验脚本两条路径复用。

实拍证据：`wgpu-path-capture.png`（wgpu 路径出画，三色带 + 移动白块 + 实时面板）。

## 2. 风险 1：Flutter 收下外部 D3D12 texture（native 路径）

原生侧手写 D3D12 渲染 → DXGI shared texture → 注册给 Flutter 合成。

### 客观证据

原生侧落盘数据（`poc-native-stats.json`，每秒由 `getStats` 通道导出）：

| 指标 | 实测值 | 说明 |
|---|---|---|
| `handleOpened` | 与 `frames` 相等 | 引擎确实打开了我们提供的 DXGI shared handle |
| `usingFlutterAdapter` | **true** | 成功复用 Flutter 自己的 DXGI adapter |
| `adapter` | `NVIDIA GeForce RTX 4060 Laptop GPU` | 走独显，非 WARP 软渲染 |
| `width × height` | 1264 × 531 | 非 16 对齐尺寸可用 |
| `recreates` | 1 | 仅初始创建，尺寸稳定 |

像素级校验（`tools/capture_probe.py` 截屏采样）：

| 采样位置 | 实测 RGB | 期望 | 结果 |
|---|---|---|---|
| 左带 | `(255, 0, 0)` | 红 | 通过 |
| 中带 | `(0, 255, 0)` | 绿 | 通过 |
| 右带 | `(0, 0, 255)` | 蓝 | 通过 |

取到的是**纯色精确值**，说明既没有 R/B 互换，也没有位偏移或格式降级。
这一条很关键：`handleOpened > 0` 只能证明引擎收下了句柄，证明不了通道顺序正确
（BGRA 被当 RGBA 解释时句柄照样会被打开）。必须读真实像素才能区分。

## 3. 风险 2：wgpu 渲染 → 共享句柄 → Flutter 合成（wgpu 路径）

`poc/texture-bridge/rust/wgpu-probe/` 是一个 `cdylib` 探针：wgpu 渲染，经 `as_hal`
摸到裸 D3D12 资源，再导出共享句柄。

### 3.1 实测数据

| 指标 | 实测值 | 说明 |
|---|---|---|
| 后端 | `wgpu/dx12` | 未回退到 Vulkan 或 WARP |
| adapter | `NVIDIA GeForce RTX 4060 Laptop GPU` | — |
| `adapterMatched` | **true** | LUID `0x157e0` 与 Flutter 侧一致 |
| `handleOpened` / `frames` | 1557 / 1557 | 每渲染一帧，引擎就消费一帧 |
| 尺寸 | 1264 × 487 | 非对齐尺寸可用 |
| Dart 侧往返吞吐 | 161 次/秒 | 每帧一次平台通道调用 |
| `initMs` | 807.8 ms（热）/ 2311.6 ms（首次冷） | 含 WGSL→HLSL→DXIL 一次性编译 |
| 像素校验 | 红 / 绿 / 蓝 | 零误差，与 native 路径一致 |

> 两条路径的 texture 高度不同（531 / 487）只因底部面板高度不同，不是渲染差异。

### 3.2 关键结论：直接共享 wgpu texture 不可行

探针第一次动作就是**故意**拿 wgpu 自己的渲染目标去调 `CreateSharedHandle`，结果是：

```text
directShareOfWgpuTexture = 失败 -2147024809
```

`-2147024809` = `0x80070057` = **`E_INVALIDARG`**。

**这不是代码写错，是 D3D12 的硬性约束**：`CreateSharedHandle` 要求目标资源在建堆时
带 `D3D12_HEAP_FLAG_SHARED`，而 wgpu 的 texture 建在默认堆上，且 wgpu 27 的公开
API 既不提供该标志，也不提供「用外部资源反包一个 wgpu texture」的入口。

因此面板上这一栏显示错误值**属于预期**：它是 Gate A 需要的原因说明，不是故障状态。
区分方法看 `verdict` 与 `ok` 字段：
- `verdict = channel_ok` / `ok = true` → 链路健康，`directShareOfWgpuTexture` 只是测量值；
- `verdict = init_failed` / `ok = false` → 才是真的初始化失败，此时 `error` 字段非空。

### 3.3 替代路径：自建共享纹理 + 每帧 GPU→GPU 拷贝

```text
wgpu 渲染目标（默认堆）
      │  CopyResource（GPU→GPU，同在 wgpu 的 D3D12 device / queue 上）
      ▼
自建纹理（D3D12_HEAP_FLAG_SHARED，BGRA8）  ──CreateSharedHandle──▶  Flutter 合成
```

要点：

- 自建纹理与 wgpu 用**同一个 `ID3D12Device` 和同一条 queue**，所以拷贝可以纯 GPU 完成，
  **不经过 CPU**，满足 Gate A 的「不发生不必要的 GPU→CPU→GPU 往返」。
- 拷贝命令天然排在 wgpu 的 `submit` 之后（同一条 queue），顺序有保障。
- 每次 `CopyResource` 后需要 `flush`，把共享纹理的状态推到「引擎可安全打开」。
- 实测 `copies == frames`，即每帧恰好一次拷贝。

### 3.4 零拷贝方案在 wgpu 27 上已关闭

`wgpu::Device::create_texture_from_hal` 是存在的，但用不上：

- `wgpu_hal::dx12::Texture` 的字段全部私有，且带 `suballocation::Allocation`
  这份 wgpu-hal 内部记账，无法从裸 `ID3D12Resource` 伪造一个出来；
- 唯一对外的是**单向**的 `raw_resource()`（wgpu 内部资源 → 裸指针），没有反向入口。

结论：**在 wgpu 27 上，"每帧一次 GPU→GPU 全表面拷贝"是必需的**，不是实现偷懒。
若将来要真正零拷贝，只有两条路：

1. 给 wgpu-hal 打补丁 / 维护 fork，让纹理分配带 `D3D12_HEAP_FLAG_SHARED`
   （改动小，但要跟上游同步）；
2. 渲染层不用 wgpu，直接手写 D3D12（回到风险 1 的做法，放弃 wgpu 的跨平台收益）。

### 3.5 那次拷贝到底值多少（实测，2026-09-16）

**先纠正一个曾经写在这里的错数**：早先记的是「1264 × 487 约 2.4 MB/帧，160 fps 下
约 380 MB/s 额外显存带宽」。那个 380 MB/s 是**拿帧率反推出来的**，而帧率被 vsync
锁死在 160 Hz —— 量到的是显示器刷新率，不是带宽。它比真实值低两个数量级，
不能用来判断成本。

正确做法是把拷贝从帧循环里摘出来、离屏批量跑，用 GPU timestamp 测独占时长。
基准实现在 `poc/texture-bridge/rust/wgpu-probe/src/bench.rs`
（`cargo run --release --bin bench`），原始数据 `copy-bandwidth.csv`。

RTX 4060 Laptop（128-bit GDDR6，标称 256 GB/s，实测拷贝吞吐约 190 GB/s ≈ 74%）：

| 尺寸 | 单张 | 单次拷贝 | 占 16.7 ms | 占 6.9 ms |
|---|---|---|---|---|
| 1264 × 487（本 PoC 视口） | 2.3 MB | **0.012 ms** | 0.07% | 0.18% |
| 1920 × 1080 | 7.9 MB | **0.033 ms** | 0.20% | 0.48% |
| 2048 × 2048 | 16.0 MB | **0.093 ms** | 0.56% | 1.34% |
| **3840 × 2160（4K 单页）** | 31.6 MB | **0.348 ms** | **2.1%** | **5.0%** |
| 3840 × 4320（4K 双页） | 63.3 MB | **0.701 ms** | 4.2% | 10.1% |
| **7680 × 4320（8K 双页）** | 126.6 MB | **1.384 ms** | **8.3%** | **19.9%** |
| 8000 × 12000（96MP） | 366.2 MB | **4.094 ms** | 24.6% | 59.0% |

线性度很好：≥32 MB 之后稳定在 181–191 GB/s，说明瓶颈就是显存带宽本身，
没有额外的隐藏开销；≤16 MB 靠 L2，便宜得多。

测量过程中撞到两个会让结果"好得不真实"的坑，症状与处理见 §5.10：

| 对照（都是实测） | 结果 |
|---|---|
| dst barrier 往返的成本（`shared − nobar`） | **−6% ~ +2%**，无系统性成本 |
| SHARED 堆标志的成本（`shared − plain`） | **−20% ~ +0%**，默认堆反而略慢 |

**判定**：视口量级（≤16 MB）拷贝成本 0.07%–0.56%，比动手门槛低一个数量级；
按整页大图算是 4K 单页 2.1%、8K 双页 8.3%，但这类尺寸**不该每帧拷**
（只有翻页/缩放/超分输出更新时才需要）。按 `wgpu-hal-patch-assessment.md` §4
写死的判据，**当前判定是「不改 wgpu-hal」**，优先落地「copy 按需而非每帧」
这个实现约束。

## 4. 稳定性验证

### 4.1 尺寸抖动（`tools/stress_probe.py`）

连续 120 次非对齐尺寸变化（700×450 ~ 1600×950），每 100 ms 一次：

| 指标 | 实测 |
|---|---|
| 帧数 | 259 → 3181（持续增长，渲染未卡死） |
| 重建次数 | 1 → 121（尺寸变化 120 次，每次恰好一次） |
| 累计释放旧资源 | 119 |
| 惰性释放队列深度 | 2（设计上限 2） |
| 工作集 | 419.1 MB → 418.4 MB |
| 进程 | 存活 |

121 次重建对应 119 次累计释放 + 2 个仍在队列中，**完全配对，无资源泄漏**。

> 另有一次人工拖动窗口的观测：约 10 秒内触发 175 次重建，全部被正确释放
> （累计释放 173、队列深度恒 ≤ 2）。这构成一次非脚本化的密集 resize 验证。

### 4.2 持续运行（`tools/soak_probe.py`）

70 秒连续渲染，每 7 秒采样：

| 指标 | 实测 |
|---|---|
| 帧速率 | 前半段 162 fps → 后半段 164 fps（无衰减） |
| 尺寸 | 全程恒为 1264 × 487 |
| 重建次数 | 全程恒为 1 |
| 工作集 | 407 ~ 415 MB 区间波动，无单调爬升 |

### 4.3 一个必须区分的指标：队列深度 ≠ 累计释放

`retired` 是**延迟释放队列的当前深度**（故意限制在 2 以内），不是累计退役数。
第一次跑压测时把 `retired`(=2) 与 `recreates`(=121) 对比，得出了「旧 texture 未释放」
的假泄漏结论。为此在探针里补了 `releasedTotal`（累计真正释放数），判据改用它之后
结论才是可信的。**看资源释放是否配对，必须看累计值。**

## 5. 过程中确认的硬约束与发现

### 5.1 格式必须是 BGRA8

Flutter Windows 走 D3D11/ANGLE 打开 shared texture，而 D3D11 打不开 RGBA8 的共享纹理。
因此 D3D12 侧必须用 `DXGI_FORMAT_B8G8R8A8_UNORM` + `D3D12_HEAP_FLAG_SHARED`
+ `D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET`。

### 5.2 必须复用 Flutter 的 adapter

`flutter::FlutterEngine::GetGraphicsAdapter(IDXGIAdapter**)` 能直接拿到 Flutter 正在
使用的 DXGI adapter。这是硬约束而非优化：跨 adapter 共享纹理在多数机器上会失败，
或掉进极慢的拷贝路径。两条路径都实测命中同一个独显（LUID 一致）。

### 5.3 引擎每帧重新打开 handle

实测 `handleOpened == frames`，即**每一帧都执行了一次打开共享资源**。
这与头文件语义一致（`flutter_texture_registrar.h`：

> An optional callback that gets invoked when the |handle| has been opened.

Debug 下如此，Release 是否一致**尚未验证**。若一致，这是一个真实的性能项：
每帧一次跨设备打开并非零成本。后续可评估改用
`kFlutterDesktopGpuSurfaceTypeD3d11Texture2D`（直接交出 `ID3D11Texture2D*`，
由我们自行持有让引擎缓存）能否规避。

### 5.4 Flutter 3.47 Windows 默认渲染后端是 Impeller / OpenGLES

启动日志：

```text
[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impeller.cc(126)]
Using the Impeller rendering backend (OpenGLESSDF).
```

上屏路径不是纯 D3D11/ANGLE，而是 D3D12 →（D3D11 打开）→ GL/Impeller。
**可能有额外的跨 API 转换开销**，而 Gate A 的验收项里有「不发生不必要的
GPU→CPU→GPU 往返」，必须专门量化。当前只证明了「能通」，没证明「够快」。
macOS 侧 Flutter 直接走 Metal，这条链会短得多 —— 意味着 Windows 是这条链的弱侧。

### 5.5 wgpu / windows crate 版本必须与 wgpu-hal 对齐

`wgpu-hal 27.0.4` 依赖 `windows 0.58`。探针 crate 必须锁同一版本，否则
`ID3D12Device` / `ID3D12Resource` 会被当成两个不同的类型，报出一堆看不懂的类型不匹配。
另外 wgpu 27 的 `as_hal` 已不是闭包式，而是返回 Deref guard；`raw_queue()` 挂在
**Device** 上而不是 Queue 上。

### 5.6 DXC 必须随 exe 分发

wgpu 的 DX12 后端把 WGSL 经 naga 编成 HLSL，再调 **DXC** 编成 DXIL，需要
`dxcompiler.dll` 与 `dxil.dll`。二者在 Windows SDK 里存在
（`...\Windows Kits\10\bin\10.0.26100.0\x64`）但**不在 PATH**，
必须由 CMake 拷到 exe 同目录，否则初始化直接失败。

### 5.7 MSVC 需要显式 `/utf-8`，否则中文注释会引发语法雪崩

Flutter 的 Windows 模板在 `apply_standard_settings` 里开了 `/W4 /WX`，而 MSVC 在中文
Windows 上**默认按 GBK(936) 解析源文件**。UTF-8 无 BOM 的中文注释会被读错位，典型症状是
注释收尾处吞掉换行，随后整片语法雪崩，并且 C4819 被 `/WX` 升级成 `error C2220`：

```text
warning C4819: 该文件包含不能在当前代码页(936)中表示的字符
error C2220: 以下警告被视为错误
gpu_texture_poc.h(30,2): error C2059: 语法错误:"public"      <- 全是假象
```

满屏 `C2059` / `C2143` 看起来像「代码写错了」，实际只是编码。修复一行：

```cmake
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")
```

Rust 侧不受影响（`rustc` 默认按 UTF-8 处理源码）。

### 5.8 `CARGO_TARGET_DIR` 会让探针继承主工程的 target 目录

`docs/windows-build/win-baseline-env.sh` 为 Breeze 主工程设了
`CARGO_TARGET_DIR=<repo>/rust/target`。PoC 若继承它，产物会与主工程混用，
表现为莫名其妙的 `only metadata stub found for rlib dependency core`。
PoC 的 CMake 必须显式清掉这个变量，让产物落在自己的 `rust/wgpu-probe/target`。

### 5.9 采数脚本自身的两个坑

1. **`taskkill //F` 在 Git-Bash 下会被参数转换破坏**，报
   `无效参数/选项 - '//F'` 且**不杀进程**。残留实例会同时往同名
   `poc-*-stats.json` 写数据，于是出现「native 与 wgpu 两条路径都有大量帧数」的假象，
   看起来像两条链路同时在跑。工具脚本一律改用 subprocess 列表参数绕开 shell 转换。
2. **`tasklist` / `taskkill` 输出是 GBK**，Python 默认按 UTF-8 解码会抛
   `UnicodeDecodeError`，让读取脚本自己崩掉而不是报告真实状态。统一按 GBK 容错解码。

### 5.10 带宽基准自身的两个坑（症状都是"结果好得不真实"）

1. **显存压缩。** 源纹理留成未写入（内容全零）时，实测读+写吞吐 363–432 GB/s，
   **超出这块卡 256 GB/s 的标称带宽 40% 以上**。全零数据被 NVIDIA 的
   delta color compression 吃掉了，真实显存流量远小于名义值。
   修法：源纹理改由 wgpu 渲染生成，用**整数 bit-mix hash**（不是常见的
   `fract(sin(dot(p,k))*n)` —— 像素坐标到 12000 时 float32 尾数精度会让相邻像素
   算出相近值，一有相关性压缩又会生效）。漫画页是扫描件/照片，本来就高熵，
   用噪声才和真实场景对得上。

2. **L2 缓存。** 2.3 MB（PoC 视口尺寸）量到 444 GB/s，同样是虚高：它整个放得进
   32 MB 的 L2，读根本没落到显存。所以判断 Gate A 只看 ≥32 MB 那几档，
   小尺寸的数字只能说明「这个量级的拷贝很便宜」。

另外一条是口径问题：**帧循环里的拷贝被 vsync 锁死**，一帧只拷一次；
拿帧率换算带宽得到的是刷新率上限，不是吞吐。基准必须离屏批量跑。

### 5.11 几处 windows-rs 0.58 的签名与直觉相反

同一个 crate 里两种调用风格混用，写错时的报错位置和根因经常对不上：

| 方法 | 风格 |
|---|---|
| `CreateCommittedResource` / `CreateQueryHeap` | **out 参数**（末尾 `*mut Option<T>`，返回 `Result<()>`） |
| `CreateCommandAllocator` / `CreateCommandList` / `CreateFence` | **返回值**（`Result<T>`，需 turbofish 指定接口） |
| `ID3D12Resource::Map` | 第三参是 `*mut *mut c_void`，不能直接传 `*mut u64` |

还有一条 D3D12 语义坑：**fence 值必须严格单调递增**。重置计数器（例如在预热之后
把 `fence_value` 重新读一遍）会让 `Signal` 变成空操作、`SetEventOnCompletion` 立刻
返回 —— 等待没生效，资源提前释放，GPU 读已释放内存，报出来的却是
`DXGI_ERROR_DEVICE_REMOVED (0x887A0005)`。这个 HRESULT 的含义是「整个设备已不可用，
后续操作都会失败」，不是「这次分配失败」；不认出来会把排查方向带偏。

## 6. 已知薄弱点（PoC 有意保留）

1. **未做跨设备同步。** 我们在 D3D12 侧写、Flutter 在 D3D11 侧读，两者之间没有显式
   fence 或 keyed mutex，只靠 `flush`。实测数分钟无异常，但这**不能证明时序安全**，
   正式实现需补 D3D11 `IDXGIKeyedMutex` 或等价机制。
2. **旧的 GPU 资源延迟释放是保守近似。** 重建时旧资源挪进队列保留最近 2 个再释放，
   正式实现应改为基于 `release_callback` 的引用计数。
3. **渲染负载极轻。** 只有一次 `draw(0..3)` 全屏三角形 + 一次拷贝，刻意不引入
   真实解码/缩放负载。性能结论不能外推到真实 Reader。
4. **只有 Debug 数据。** 全部帧率/时序结论来自 Debug 构建。

## 7. 尚未验证 / 下一步

| 项 | 状态 |
|---|---|
| Release 构建下的行为与性能差异 | **未验证**（含 §5.3 的每帧打开 handle 是否同样存在） |
| 性能量化（帧时间 / GPU 占用 / 跨 API 转换开销） | **未做**，而这正是 Gate A 的实质 |
| macOS 侧同等验证（风险 1 + 风险 2） | **未做**（当前无可用 Mac） |
| 与现有 Reader 的对照基线 | **未采集**（ROADMAP Phase 0 未勾选项） |
| 跨设备同步（keyed mutex / fence） | **未做**（PoC 有意省略） |
| 真实渲染负载下的表现（解码 + 缩放 + 超分） | **未做** |

**Gate A 判定所需但当前缺失的关键前提**：Gate A 说的是「性能与稳定性达标」，
而「达标」需要一个对照物 —— 现有 Reader 的帧率/内存/翻页延迟基线尚未采集。
没有它，PoC 跑得再快也无法判定是否达标。

### 7.1 「要不要给 wgpu-hal 打补丁去掉那次拷贝」已单独评估

结论：**现在不改**。收益是一次 GPU 拷贝，其成本已经实测量化（§3.5）：
视口量级 0.07%–0.56%、4K 单页 2.1%、8K 双页 8.3%（占 60 fps 预算）。
代价是仓库多背 **2.0 MB / 45,262 行**第三方源码（cargo 的 patch 粒度是整个 crate，
改 10 行也躲不掉）＋ 每次升级 wgpu 重新对账。

另外记一条只会在动手时才暴露的坑：RTX 4060 上 `suballocation_supported == true`，
纹理走 **placed 子分配**而不是 committed 资源，只给 `create_committed_texture` 加
`D3D12_HEAP_FLAG_SHARED` 这条代码路径**根本不会被执行**，症状是「补丁打了但没变化」。

还有一条尚未验证的反向风险：fork 之后 wgpu 会**直接在 SHARED 堆纹理上渲染**，
而 shared 堆上的渲染性能没测过 —— 万一它比普通堆慢，省下的拷贝会被抵消。

完整评估、精确改动位置、四种落地方式取舍与动手判据见
[`wgpu-hal-patch-assessment.md`](./wgpu-hal-patch-assessment.md)。

## 8. 工程用法

```bash
# 构建（务必先修 PATH，见 docs/windows-build/win-baseline-env.sh 第 0 节）
export PATH="/c/Users/$USERNAME/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:$PATH"
export PATH="/d/scoop/persist/rustup/.cargo/bin:$PATH"   # CMake 需要找到 cargo
cd poc/texture-bridge
source ../../docs/windows-build/win-baseline-env.sh
flutter build windows --debug
```

四个验证工具（都在 `poc/texture-bridge/tools/`）：

| 工具 | 作用 | 用法 |
|---|---|---|
| `capture_probe.py` | 截屏 + 采样三色带，判定 BGRA 通道顺序 | `python capture_probe.py texture_bridge out.png` |
| `run_probe.py` | 清理 → 启动 → 截屏校验 → 读落盘数据 → 收尾 | `python run_probe.py 12 out.png` |
| `stress_probe.py` | 尺寸抖动压测，检查重建/释放是否配对 | `python stress_probe.py 3 40 5` |
| `soak_probe.py` | 长时间浸泡，检查泄漏与帧率衰减 | `python soak_probe.py 90 10` |

窗口内可手动操作：

- 拖动边框改变尺寸 → 观察「texture 尺寸」与「重建次数」是否跟随；
- 「强制重建 texture」→ 验证销毁/重建路径；
- 「暂停渲染」→ 冻结画面，便于截图对比；
- 顶部 `native` / `wgpu` 切换 → 两条路径肉眼与数据比对。
