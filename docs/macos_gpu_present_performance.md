# macOS GPU 呈现性能记录（2026-10-11）

## 当前判断

视口预渲染缓存命中后的原生缓冲区写入已在毫秒以内；未缓存的大图仍有明显等待，
解码与上传、渲染、同步回读两部分都值得继续优化。当前 macOS 路径不是端到端零拷贝。
以下数据来自本机 Release 原生库，不能当作 Flutter 完整翻页时间或物理屏幕刷新延迟。

本轮已完成：

- 未缓存页只渲染一次，缓存取自这次显示结果，避免同一视口重复 GPU 渲染及回读。
- 页面缓存统一执行 16 页、3 张原图、1 GiB 字节预算，并保护当前页。
  当前页本身超过预算时会保留并上报溢出；这些数字只覆盖 PageCache 持有的像素。
- 后台预取改用事件唤醒，优先服务前台，拒绝旧来源与旧超分轨结果。
  已运行的解码或 GPU 工作仍不能被即时抢占。
- Swift 串行调度让显示任务优先于尚未执行的准备任务，保持来源切换等操作的顺序。
  增加 `showQueueWaitMs` 和 `showBridgeMs`，便于区分排队与桥内处理时间。
- 移除 Swift 上屏前的整帧清零。Rust 首次渲染与缓存复制均写满目标像素及行尾补边；
  原生调用失败时不会发布该缓冲区。

## 路径与测量边界

macOS 未缓存页：

```text
本地来源 → CPU 解码 RGBA → 上传 wgpu 源纹理 → GPU 生成 mip / 缩放
         → 拷入 staging buffer → 等待 GPU 完成及映射 → CPU 写 CVPixelBuffer
         → 保存视口缓存 → Swift 发布 → Flutter 外部纹理合成 → 屏幕刷新
```

缓存页跳过重新解码、上传和渲染，将已保存的 BGRA 视口帧复制到 CVPixelBuffer。
Windows 使用另一套 D3D12 共享纹理及 GPU→GPU CopyResource 路径，不能套用这里的回读结论。
本次没有测 Windows、移动端或 Web。

探针复用一个真实 IOSurface / Metal-compatible CVPixelBuffer，计时从锁定缓冲区到原生
`show_into_buffer` 返回并解锁为止。**不含缓冲区分配、Swift 队列等待、MethodChannel、
Flutter 取纹理、合成或物理屏幕刷新。** `cachedWithClear` 额外包含旧桥中的全缓冲区清零。

每次冷样本之前重新打开来源以清空页面缓存，操作系统文件缓存和 GPU 管线可以是热的。
两个页面交替显示，预取关闭。冷样本 8 次；缓存样本每种模式 60 或 120 次。
缓存比较使用 AB / BA 交替顺序，两个模式在同一进程中使用同一页、同一缓冲区和同一原生库。
每次缓存样本均断言 `prerenderHit=1`；两页首次缓存结果分别与冷页结果整块逐字节比较。

## 实测

设备：Apple M4，16 GiB 内存。系统版本记录在 JSON 的 `operatingSystem` 字段。
输入为两个程序生成的带图案 PNG；它们覆盖不同尺寸，不能代表所有漫画格式或内容。
独立运行之间未控制全部系统负载，不能用两种目标分辨率的冷耗时差异推导缩放性能。

| 原图尺寸 | 目标视口 | 冷页 p50 | 冷页 p95 | 缓存页 p50 | 缓存页 p95 | 样本数（冷 / 每种缓存模式） |
|---|---|---:|---:|---:|---:|---:|
| 4096×3072（12.6 MP） | 2560×1600 | 83.07 ms | 132.29 ms | 0.40 ms | 0.49 ms | 8 / 60 |
| 9504×6336（60.2 MP） | 2560×1600 | 338.42 ms | 485.17 ms | 0.46 ms | 0.77 ms | 8 / 120 |
| 9504×6336（60.2 MP） | 3840×2160 | 331.24 ms | 395.38 ms | 0.82 ms | 1.06 ms | 8 / 120 |

分位数采用 nearest rank；8 个冷样本的 p95 / p99 都等于最大值，样本量不足以稳定估计长尾。
缓存数据为当前不清零路径。原始报告保存全部样本和最大值，例如 4K 缓存页存在 5.29 ms
的最大值，不能只读 p95 就认为所有帧都低于 1.1 ms。

### 重复清零的局部收益

| 原图 / 目标 | 旧清零模式缓存 p50 | 不清零缓存 p50 | 每对样本耗时差的中位数 |
|---|---:|---:|---:|
| 60.2 MP / 2560×1600 | 0.64 ms | 0.46 ms | 0.17 ms |
| 60.2 MP / 3840×2160 | 1.15 ms | 0.82 ms | 0.34 ms |

4K BGRA 帧为 31.64 MiB（不含额外行对齐）；去掉清零减少一次等量 CPU 写入。
这是这一处修改的局部交替对照，不是所有优化的总体前后对照，也不是用户翻页提速比例。

### 冷页的时间分布

60.2 MP / 4K 的 8 个冷样本中，`decodeMs` 中位数约 246 ms，`renderMs` 约 86 ms。
12.6 MP / 2560×1600 分别约 51 ms 和 38 ms。
这里的阶段中位数采用两个中间值的平均，不能与表中 nearest-rank p50 直接求和。

- `decodeMs` 覆盖缓存查询、可能的预取等待、解码与缓存接纳，不能当成纯解码器 CPU 时间。
  本次预取关闭且每次清缓存，该阶段主要是解码。
- `renderMs` 包含渲染器锁等待、上传、mip / 缩放提交、同步回读、CPU 复制和视口缓存保存。
  缓存命中时则主要是复制视口帧。它不是 GPU 时间戳查询结果。
- macOS 当前 `submitMs` 是 `renderMs` 的兼容别名，不能解读为单独的命令提交时间；
  `queueSubmitMs` 才是 mip、主渲染和 readback 三次 `queue.submit` 的 CPU 调用耗时之和。
- `rendererLockMs` 是前台等待共享 wgpu 渲染器锁的时间；`cachedCopyMs` 是命中预渲染视口后
  写入 CVPixelBuffer 的复制时间；`frameCaptureMs` 与 `frameCachePublishMs` 是冷页把本次结果
  保存到视口缓存的 CPU 时间。
- `targetSetupMs` / `sourceSetupMs` / `uploadMs` / `mipmapEncodeMs` / `mipmapSubmitMs` /
  `renderEncodeMs` / `renderSubmitMs` / `readbackEncodeMs` / `readbackSubmitMs` 分别覆盖
  目标与源纹理准备、源上传、mip 命令准备与提交、主渲染命令准备与提交、回读命令准备与提交。
- `gpuWaitMs` 是 `map_async` 后调用 `device.poll(wait_indefinitely())` 直到 map 回调完成的墙钟时间，
  包含 GPU 排队、执行与同步开销，不能解释为 shader 独占时间；`cpuCopyMs` 是映射 staging
  缓冲复制到 CVPixelBuffer 及行尾 padding 清零的时间。
- 缓存命中时这些 GPU 分段为 0；统计在每次前台呈现开始时清空，失败不会继续显示上一帧的旧阶段。
- `showBridgeMs` 也仍然不包含 Flutter 合成；`showQueueWaitMs` 只计 Swift 调度队列。

## 内存与占用

最后一个样本的 `cacheBytes`：12.6 MP / 2560 为 127.25 MiB，60.2 MP / 2560 为
490.67 MiB，60.2 MP / 4K 为 522.70 MiB。探针只用了两页，生产阅读时邻页预取、超分轨
与不同视口缓存会改变这些数值。

PageCache 的 1 GiB 预算不包含 GPU 源纹理、mip 链、目标纹理、staging buffer、
CVPixelBuffer 池、临时解码数据、正在执行任务持有的 Arc、Flutter 纹理及其他应用内存。
它不是进程总内存的硬上限；当前页过大时还允许缓存预算溢出。

作为容量估算，9504×6336 RGBA 为 229.71 MiB；一张完整 mip 链约 306.28 MiB。
当前源纹理按尺寸复用，冷渲染仍重新上传；缓存页仍有视口 BGRA 到 CVPixelBuffer 的复制。
这些是按尺寸计算的容量，不是 Instruments 测得的 GPU 常驻量或进程峰值。

本次没有采集 CPU / GPU 利用率、功耗和整进程峰值；不能用低延迟或缓存字节推导这些指标。

## 下一步优先级

1. 补上应用级证据：记录排队、原生返回、`textureFrameAvailable`、引擎取帧与 Flutter 合成
   的同帧关联；分别测首屏、缓存翻页、连翻和缩放。物理显示延迟还需要显示侧测量。
2. 降低未缓存页的等待：测量实际 PNG / JPEG / AVIF 的解码档位，结合预取命中率和邻页
   准备耗时选择策略。不能为了减少 RGBA 字节而无条件牺牲放大后的细节。
3. 已完成 `renderMs` 的阶段分解：当前可以直接区分 renderer 锁等待、命令准备与提交、
   同步回读等待、CPU 行复制和视口缓存保存；下一步用真实图片和应用链路样本确认瓶颈占比。
4. 管理全部缓冲区的占用：结合系统内存压力收紧缓存，评估空闲时释放大源纹理，验证连翻
   中的瞬时峰值与重新分配代价。用实测选择容量，不把缓存预算当作总内存约束。
5. 评估 Metal 直接写 IOSurface / CVPixelBuffer，避免当前同步回读及 CPU 搬运。
   这需要验证 wgpu 互操作、Flutter 取帧期间的缓冲生命周期与 GPU 完成同步，尚未实现。
   也不能假定它会消除解码和着色器本身的耗时。

## 后续优化：按实际采样级生成与分配 mip

2026-10-11 同日追加：源纹理不再默认分配完整 mip 链。Lanczos 继续读取原有整数
`floor(log2(1/scale))` 等级，保留第 0 级到该级；Anime4K 仅读第 0 级，省去 mip 分配和生成。
已有同尺寸纹理容量足够时继续复用；需要更深等级或源尺寸变化时重建。
已经分配的较深 mip 不会在每次放大时立即释放，避免缩放切换反复重新分配纹理。

mip 相关源代码拆到 `wgpu_resampler/source.rs`。macOS 原生诊断增加：

- `sourceMipLevels`：共享渲染器当前源纹理的分配级数。
- `sourceGeneratedMipLevels`：最近一次源图上传后，为该次绘制准备的级数，包含第 0 级。
- `sourceTextureTexelBytes`：上述纹理按 RGBA8 texel 计算的字节数，**不是实际驱动常驻量**。

共享渲染器也用于后台预取，指标不保证属于当前显示页。统计查询用 `try_lock`；
后台渲染占锁时这三个新增字段为 `null`，不会为获取诊断阻塞等待 GPU。
PageCache 的 `cacheBytes` / 预算口径保持不变，未把 GPU 纹理字节混入其中。

### 同进程 Release 库对照

探针增加 `--compare-library`。参考库是在此项修改前保留的 Release dylib；两边分别持有
设备与缓存，使用同一份输入、同一个 CVPixelBuffer，AB / BA 交替同步执行冷页。
每对冷样本之后整块逐字节比较输出；全部 16 对均一致。报告还保存两页的整帧 SHA256。
这套对照使用两份设备资源，会增加测试进程占用，不能替代单呈现器的内存峰值测量。

| 输入 / 视口 | 修改前冷页 p50 | 修改后冷页 p50 | 修改前 renderMs 中位数 | 修改后 renderMs 中位数 | 配对 renderMs 差的中位数（后减前） |
|---|---:|---:|---:|---:|---:|
| 60.2 MP / 3840×2160 | 342.45 ms | 339.15 ms | 91.27 ms | 87.84 ms | -5.80 ms |
| 12.6 MP / 2560×1600 | 88.23 ms | 86.20 ms | 35.21 ms | 34.76 ms | -0.12 ms |

原始报告包含全部样本。4K 冷页 p95 前 / 后为 542.01 / 586.93 ms；12.6 MP 为
134.30 / 174.10 ms，长尾仍不稳定，不能据此宣布稳定的总体提速。
独立进程的初次前后测量连解码阶段也发生大幅波动，未拿那组差异作为收益证据。
当前结论是减少无用工作与按 texel 计算的容量，渲染阶段的测量显示局部收益迹象。

| 源纹理 | 修改前完整链（按 texel 计算） | 本次实际分配 | 减少容量 |
|---|---:|---:|---:|
| 9504×6336，当前读取第 1 级 | 14 级，约 306.28 MiB | 2 级，287.14 MiB | 约 19.14 MiB |
| 4096×3072，当前读取第 0 级 | 13 级，约 64 MiB | 1 级，48 MiB | 约 16 MiB |

本轮 44 项原生测试通过。新增测试覆盖非整齐尺寸、多个缩放等级、Anime4K、同尺寸换页、
从较深 mip 切回第 0 级再切回缩小，以及源尺寸变化；复用结果与新建纹理结果逐字节一致。
另验证诊断在渲染器锁被占用时及时返回 `null`。

复现时先在修改 mip 之前保留参考 Release 库（仅复制到临时路径，不修改源文件）：

```sh
cp rust/gpu_present/target/release/librossi_gpu_present.dylib /tmp/rossi-gpu-reference.dylib
# 更新至 mip 优化版本后，按上文命令构建 Release 库并编译探针。
/tmp/rossi-gpu-probe --compare-library /tmp/rossi-gpu-reference.dylib --source-size 9504x6336 --target 3840x2160 --cold 16 --warm 60 --output /tmp/rossi-gpu-mip-paired.json
```

原始对照报告：

- [60.2 MP / 4K 配对](benchmarks/macos-gpu-present-2026-10-11/mip-paired-60mp-3840x2160.json)
- [12.6 MP / 2560 配对](benchmarks/macos-gpu-present-2026-10-11/mip-paired-12mp-2560x1600.json)

## 验证与限制

本轮此前的原生测试为 40 项通过，Dart 阅读控制器测试 27 项通过；Swift 调度测试验证了
优先级、顺序屏障、400 次并发提交恰好执行一次及串行执行。移除清零后重新运行 3 项
缓冲区测试，覆盖首次渲染 / 缓存结果一致、脏目标缓冲区、行尾补边、非对齐指针和边界哨兵；
Swift 语法检查及真实 CVPixelBuffer 探针也通过。

此前 macOS 应用已编译成功。但 Flutter macOS 集成测试没有进入 GPU 用例：已有实例的锁
阻止启动，隔离用户目录后又遇到 `AppDelegate.applicationDidFinishLaunching` 启动异常。
这里不把该集成测试记为通过。尚不能据此保证完整应用上屏、功耗或峰值内存已改善。

## 复现

在仓库根目录执行，不给宿主 cargo 添加 `--target`：

```sh
CARGO_TARGET_DIR="$PWD/rust/gpu_present/target" cargo build --manifest-path rust/Cargo.toml -p rossi_gpu_present --lib --release --locked
swiftc -O script/probe_macos_gpu_present.swift -o /tmp/rossi-gpu-probe
/tmp/rossi-gpu-probe --source-size 9504x6336 --target 3840x2160 --cold 8 --warm 120 --compare-clear --output /tmp/rossi-gpu-probe-4k.json
/tmp/rossi-gpu-probe --source-size 4096x3072 --target 2560x1600 --cold 8 --warm 60 --compare-clear --output /tmp/rossi-gpu-probe-12mp.json
```

也可用 `--source /path/to/comic.cbz` 或文件夹，来源须有至少两张可解码图片。
此时 `--source-size` 不参与输入处理，具体尺寸读原生诊断；程序不会删除指定的来源。
每轮按顺序运行，避免多个探针争用 GPU。脚本默认不会在 `show` 前清零。

原始记录：

- [12.6 MP / 2560×1600](benchmarks/macos-gpu-present-2026-10-11/12mp-2560x1600.json)
- [60.2 MP / 2560×1600](benchmarks/macos-gpu-present-2026-10-11/60mp-2560x1600.json)
- [60.2 MP / 3840×2160](benchmarks/macos-gpu-present-2026-10-11/60mp-3840x2160.json)

源码入口：[`probe_macos_gpu_present.swift`](../script/probe_macos_gpu_present.swift)、
[`GpuPresentBridgeMac.swift`](../macos/Runner/GpuPresentBridgeMac.swift)、
[`mac_presenter/methods.rs`](../rust/gpu_present/src/mac_presenter/methods.rs)、
[`wgpu_resampler/render.rs`](../rust/gpu_present/src/wgpu_resampler/render.rs)。


## 后续诊断：前台呈现阶段拆分

2026-10-11 追加：分段直接作为一次 `resample_to_buffer_timed` 的返回值带回前台。
不保存共享渲染器的“最近一次耗时”，因此后台预取不会覆盖已呈现一帧的归因。
缓存命中不调用渲染器，上传、GPU 等待及 staging 行复制等阶段均为 0。
每次 show 开始清空旧耗时；失败后的 0 表示本次没有完成统计，不应解读为成功呈现。

新增测试确认阶段有限且非负、阶段合计不超过所在墙钟区间、后台渲染不覆盖前台统计，
以及缓存与首次呈现逐字节一致。45 项原生测试通过，Release 构建及 Swift 探针编译通过。
小尺寸双 Release 库对照也通过逐字节校验；该冒烟对照不作为性能证据。

新增原始报告：

- `benchmarks/macos-gpu-present-2026-10-11/phases-12mp-2560x1600.json`
- `benchmarks/macos-gpu-present-2026-10-11/phases-60mp-3840x2160.json`

每组 8 个冷样本、24 个缓存样本，增加 `cachedPhases` 保存每个缓存样本的原生阶段。
这轮测量期间另有应用、Flutter 测试与视频处理任务占用资源，没有隔离竞争负载。
绝对时间明显偏离前面的报告，且缓存复制同样变慢，**不用于判断优化的速度收益或回退**。
也不能由这些耗时推导应用独占时的 CPU / GPU 利用率或功耗。

| 阶段中位数 | 12.6 MP / 2560×1600 | 60.2 MP / 3840×2160 |
|---|---:|---:|
| decodeMs | 377.74 ms | 1259.69 ms |
| renderMs | 164.09 ms | 740.61 ms |
| uploadMs | 51.46 ms | 231.61 ms |
| queueSubmitMs | 0.13 ms | 0.35 ms |
| gpuWaitMs | 91.46 ms | 297.88 ms |
| cpuCopyMs | 5.59 ms | 26.33 ms |
| frameCaptureMs | 3.37 ms | 21.14 ms |

阶段中位数来自不同样本，不能相加还原 renderMs 的中位数。
所有缓存样本的上传、GPU 等待、staging 行复制和视口捕获阶段均为 0；
缓存复制中位数分别为 2.07 / 5.07 ms，完整缓存输出均通过逐字节一致性检查。

这些数据支持下一步优先检查解码、源图上传以及 GPU 完成等待，而非队列提交调用本身。
`gpuWaitMs` 包含着色器执行和排队，尚不能证明 readback 传输占主导。
直接输出 IOSurface 的潜在收益仍须结合 GPU 时间戳、独占负载的对照和应用级取帧验证；
当前 Flutter 应用级测试仍受启动异常阻碍，不能把独立探针视为完整上屏测试。
