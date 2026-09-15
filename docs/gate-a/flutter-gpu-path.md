# Gate A 第三条路径：Flutter GPU（`flutter_gpu`）

> 实验日期：2026-09-15　平台：Windows / Flutter 3.47.3 / Impeller OpenGLES 后端
> 验证工程：`poc/flutter-gpu-probe/`（独立工程，未触碰 Breeze 主代码）

## 0. 这份文档回答什么

前两条路径（`poc/texture-bridge/` 里的 native 与 wgpu）都是同一个思路：

```
外部渲染 → 导出 DXGI shared handle → 注册给 Flutter 合成
```

风险 2 的结论是：**wgpu 的 texture 无法直接导出 shared handle**，必须多走一次
GPU→GPU 全表面拷贝。于是自然会问：能不能换一条根本不涉及共享的路？

Flutter GPU 就是那条路。它由 Flutter 引擎自己分配纹理，`Texture.asImage()`
把纹理零拷贝包成 `ui.Image` 直接交给 Flutter 显示 —— **全程没有跨设备共享，
也没有 handle 往返**。

本文档要判定的是：这条路对 Rossi 有没有优势。

## 1. 结论摘要

| 选项 | 有没有优势 | 一句话理由 |
|---|---|---|
| Flutter 自己的 `ui.Image`（CPU 字节 → 显示） | **没有，是倒退** | 必须经 CPU 上传，直接违反 Gate A「不发生不必要的 GPU→CPU→GPU 往返」这条验收项 |
| Flutter GPU（`flutter_gpu`） | **在「零共享」这一点上有真实优势，但不能作为 wgpu 的补充** | 它无法导入外部纹理，只能**替代**整个渲染栈；且没有 compute |

对 Rossi 的落点：

- **不要为了省掉那次拷贝而换到 Flutter GPU。** 它换掉的不是一次拷贝，而是
  Rust/wgpu 整条渲染栈 —— 渲染逻辑要从 Rust 迁到 Dart，失去 Rust 生态，
  并且**失去 compute shader 能力**（超分、图像处理全部落空）。
- **要省掉那次拷贝，正确方向是给 wgpu-hal 打补丁**，让它分配的纹理带上
  `D3D12_HEAP_FLAG_SHARED`。这是**小改动**，代价是维护一个 fork。相比之下，
  换渲染栈是伤筋动骨。
- Flutter GPU 值得**持续关注**：如果未来它的 Windows 后端从 GLES 切到 D3D12、
  补上 compute、并稳定 API，它会变成一条很有吸引力的备选。当前不是。

## 2. 三条路径的本质差异

| | native / wgpu 共享纹理 | Flutter 自己的 image | Flutter GPU |
|---|---|---|---|
| 纹理归谁所有 | 我们自己（DXGI 设备） | Flutter 引擎 | Flutter 引擎 |
| 数据怎么进 Flutter | DXGI shared handle 注册 | CPU 上传字节 | 就是引擎的纹理 |
| CPU 参与 | 否 | **是（整表面）** | 否 |
| 额外 GPU 拷贝 | 1 次全表面（wgpu 路径） | 0 | 0 |
| 与 Rust/wgpu 共存 | 是 | 是（但代价高） | **否** |
| compute shader | 有（wgpu 提供） | 不适用 | **没有** |
| 成熟度 | 稳定 API | 稳定 API | **early preview** |

## 3. 实测证据（Windows）

工程用与 `texture-bridge` **完全相同的像素约定**（顶部三色带 / 中部移动白块 /
底部渐变），因此可直接复用 `capture_probe.py` 做客观校验。

### 3.1 可用性 —— 通过

| 项 | 实测值 |
|---|---|
| `gpuContext` 初始化 | 成功（`ok: true`，无异常） |
| 默认纹理格式 | `r8g8b8a8UNormInt` |
| 纹理尺寸 | 1264 × 541（非对齐） |
| `Texture.overwrite` | 成功 |
| `Texture.asImage()` | **成功，直接产出 `ui.Image`** |
| `GpuImageSurface` 创建 | 成功（1264×541，`currentImage=null`，因为未 present） |
| 像素校验 | `(255,0,0)` / `(0,255,0)` / `(0,0,255)` —— 左红中绿右蓝，**零误差** |
| 引擎渲染后端 | `Using the Impeller rendering backend (OpenGLESSDF)` |

连续运行 2000+ 帧无异常，纹理持续更新。

### 3.2 上传成本对照

同一份纹理，切「每帧是否重新上传像素」（1264×541 × 4B ≈ **2.7 MB/帧**）：

| 模式 | 帧率（Debug） |
|---|---|
| 每帧上传 2.7 MB + asImage + 显示 | 154.8 fps |
| 仅 asImage + 显示（初始化时上传一次） | 163.0 fps |

**这两个数字必须谨慎解读。** 它们的差距只有 3%，但不代表「CPU 上传很便宜」：
两个模式都撞在 163 fps 附近，这更像是刷新率/帧调度上限，而不是 GPU 能力上限。
换句话说，**这个实验没有跑到上传成为瓶颈的区间**，3% 是「被上限掩盖后的残差」，
不能当作上传的真实代价。

能确定的只有两点：

1. `asImage()` + 显示这条链路本身能稳定跑满该上限（约 163 fps）。
2. 每帧 420 MB/s 量级的 CPU→GPU 上传（2.7 MB × 155）没有把它拖垮。

要量化上传的真实代价，得在更大的纹理上测（漫画页实际可能宽 2000–4000 px），
本次未做。

## 4. 三个硬约束

这三条都不是推测，有符号表或源码为依据。

### 4.1 没有 compute shader

`flutter_windows.dll` 里导出的全部 `InternalFlutterGpu_*` 符号中，渲染侧有完整的
`RenderPass_*`（`BindPipeline` / `SetColorAttachment` / `Draw` / `DrawIndexed` …），
但**没有任何 compute 相关符号** —— 没有 compute pass，没有 dispatch。

对 Rossi 是决定性的：**超分（RealSR 卷积）、图像预处理这类必须在 GPU 上做
通用计算的能力，用 Flutter GPU 实现不了。** 这些恰恰是 Reader 的核心能力。

### 4.2 无法导入外部纹理 —— 只能替代，不能共存

`GpuContext.createTexture` 只能由引擎自己分配纹理；公开 API 里没有
「用外部 `ID3D12Resource` / shared handle 包一个 `Texture`」的入口。
`Texture.fromImage` 看起来像，但它只接受 **Flutter 自己的 `ui.Image`**
（注释明确要求 image 由 `RepaintBoundary.toImage` 产生，即 GPU-backed 的引擎纹理），
拿不到我们外部创建的纹理。

结论：**Flutter GPU 与 wgpu 无法混用。** 它不能承接 wgpu 的渲染结果，
只能取代 wgpu 去渲染。这直接冲击 Rossi「渲染管线放在 Rust」的架构前提。

### 4.3 实验状态，且默认关闭

- 官方文档原文：*"Flutter GPU is in an early preview state and does not guarantee
  API stability."* 并建议切到 **master channel**。
- Windows 引擎的 C API 里，开关是一个**默认 false 的字段**：
  `FlutterDesktopEngineProperties::enable_flutter_gpu`，对应
  `DartProject::set_enable_flutter_gpu()`。模板 runner **从不调用它**，
  必须改原生代码才能打开 —— 这一点很容易误判成「Windows 不支持」。
- shader 必须由 `impellerc` 编译成 `.shaderbundle`，SDK 里没有现成示例工程。

## 5. 一个顺带确认的结论：命令行开关到不了 Dart

Fluent GPU 的对照开关最初设计成读 `--no-upload` 命令行参数，实测**没生效**。
排查结果：

- runner 的 `GetCommandLineArguments()` **不过滤任何参数**，全部交给引擎；
- 但带 `--` 前缀的参数会被 embedder 当作**引擎开关消费掉**，到不了
  `main(List<String> args)`。

所以对照开关最终改用环境变量驱动。这条对以后调试验证程序有用 ——
**别指望自定义 `--xxx` 参数能传到 Dart 侧**。

## 6. 复现方法

```bash
cd poc/flutter-gpu-probe
source ../../docs/windows-build/win-baseline-env.sh   # 内含 PATH 与 MSVC/SDK 修复
flutter build windows --debug

# 每帧上传模式
./build/windows/x64/runner/Debug/flutter_gpu_probe.exe

# 关闭每帧上传（仅 asImage + 显示）
ROSSI_GPU_NO_UPLOAD=1 ./build/windows/x64/runner/Debug/flutter_gpu_probe.exe
```

诊断数据落在 exe 同目录的 `flutter-gpu-stats.json`；像素校验复用
`poc/texture-bridge/tools/capture_probe.py`。

## 7. 已知薄弱点 / 未验证

- **没有实测 shader 渲染**。本次只验证了「纹理 → asImage → 显示」这条通道，
  没有用 `RenderPass` + `ShaderLibrary` 真实绘制过。符号表证明这套 API 存在，
  但 Windows/GLES 后端下能否正常工作**未验证**。
- 全部数据来自 Debug 构建，Release 未测。
- 帧率被刷新率上限掩盖，未触及真实瓶颈。
- macOS 未测（Flutter GPU 在 macOS 走 Metal，理论上支持度更好）。
- `ui.Image` 生命周期：本工程每帧 `asImage()` 后 `dispose()` 上一帧，
  长时间运行的显存行为未做浸泡测试。若要正式使用，应优先考虑
  `GpuImageSurface.currentImage`（由 Surface 自行管理后备纹理池）。
