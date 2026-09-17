# 真 HDR（EDR）与 SDR 逆色调映射

> 本文记录一件已经被**实测否证过**的事，以及唯一可行的替代路线。
> 写作动机很具体：一条"看起来完全正确"的 HDR 实现，画面会**一点变化都没有**，
> 而原因藏在 Flutter macOS 引擎的一行硬编码里。

---

## 1. 结论先行

| 目标 | 可行通路 |
|---|---|
| SDR 画质增强（逆色调映射后压回 `[0,1]`） | Flutter 外部纹理（`FlutterTexture`） |
| **真 HDR（高光真正超过 SDR 白点）** | **只能走原生 `AppKitView` 平台视图 + 自建 EDR 图层** |
| 通过 Flutter 纹理通路输出 > 1.0 | **物理上不可能** |

---

## 2. 为什么 Flutter 纹理通路不可能出真 HDR

Flutter macOS 引擎把外部纹理的像素格式**写死**了。证据在引擎源码里（Flutter SDK 自带
完整引擎源码，路径 `/opt/homebrew/share/flutter/engine/src/flutter/`）：

```objc
// shell/platform/darwin/macos/framework/Source/FlutterExternalTexture.mm
- (BOOL)populateTextureFromRGBAPixelBuffer:(nonnull CVPixelBufferRef)pixelBuffer
                                textureOut:(nonnull FlutterMetalExternalTexture*)textureOut {
  CVReturn cvReturn =
      CVMetalTextureCacheCreateTextureFromImage(...,
                                                /*pixelFormat=*/MTLPixelFormatBGRA8Unorm,
                                                ...);
}
```

公开头文件同样把这件事写成了契约 —— `FlutterTexture.h`：

```
 * The type of the pixel buffer is one of the following:
 * - `kCVPixelFormatType_32BGRA`
 * - `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`
 * - `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`
```

`MTLPixelFormatBGRA8Unorm` 是**8 位无符号归一化**格式，可表示范围是 `[0, 1]`。
无论 Rust 侧着色器算出 `3.0` 还是 `10.0`，**赋值那一刻就被钳到 1.0**。
所以：

- Rust 侧再怎么改公式都不会让画面变更亮；
- 现象就是"改了半天、一丁点变化都没有" —— 因为超过 1.0 的部分在进 Flutter 之前就没了；
- 8 位通路能做的上限是 **SDR 增强**（把逆色调映射的结果软肩压缩回 `[0,1]`），
  那确实有肉眼可见的效果，但它不是 HDR。

顺带否掉另一个常见猜想：Flutter 的 `enableWideGamut` 也救不了。
它走 `FlutterSurface.mm` 的 `MTLPixelFormatBGRA10_XR` + `kCColorSpaceExtendedSRGB`，
只解决**广色域（P3）**；而且整个引擎源码里搜不到
`wantsExtendedDynamicRangeContent` —— 引擎从不向 macOS 申请 EDR 头顶空间。

---

## 3. 这条路的实现：原生 EDR 平台视图

绕开 Flutter 合成器，自己起一个 `CAMetalLayer`：

```swift
metalLayer.pixelFormat = .rgba16Float                     // 半精度浮点，可表示 > 1.0
metalLayer.wantsExtendedDynamicRangeContent = true         // 向 macOS 申请 EDR 头顶空间
metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
```

约定：**`1.0` = SDR 参考白（约 100 nit）**，大于 1.0 的部分由 macOS 合成器交给显示器
的 EDR 余量。本机外接 LG Y27q-30 实测 `maximumExtendedDynamicRangeColorComponentValue
= 4.36`，即白点最高可推到约 436 nit。

### 3.1 为什么必须是"平台视图"而不是自己往窗口贴 NSView

因为它必须和 Flutter 图层树**共用同一套图层顺序**：

```objc
// FlutterCompositor.mm —— 平台视图容器的 z 序 = 它在图层树里的下标
container.layer.zPosition = index;

// FlutterSurfaceManager.mm —— Flutter 自己的内容图层用同一个下标空间
layer.zPosition = info.zIndex;
```

于是：

1. 位置与尺寸交给 Flutter 布局，不需要手工同步窗口坐标；
2. 阅读器的顶/底控制栏画在页面**之上**时 zPosition 更大，会正确压在 HDR 画面上，
   不会被原生图层盖掉。

自己贴 NSView 两条都做不到（第二条尤其致命：贴上去就把整个阅读器 UI 盖住了）。

### 3.2 上屏用 blit 而不是画三角形

源缓冲与 drawable 是**同格式同尺寸**的纹理，直接 `MTLBlitCommandEncoder`
拷过去即可：不需要着色器、不需要渲染管线，更重要的是**不引入任何色彩转换** ——
任何多余的转换都会把 > 1.0 的部分重新压回 SDR。

---

## 4. Rust 侧：逆色调映射 + 线性落地

### 4.1 算法（libplacebo 风格）

```
sRGB 解码 ──► 线性 RGB
                 │
                 ▼
      Y = dot(RGB, (0.2126, 0.7152, 0.0722))          Rec.709 亮度
                 │
                 ▼
      Y_exp = Y + (boost - 1) · Y^2.5                  逆色调映射曲线
                 │
                 ▼
      Y_out = soft_shoulder(Y_exp, limit)              软肩渐近压缩
                 │
                 ▼
      RGB_out = RGB · (Y_out / Y)                      按亮度比率缩放色度
                 │
                 ▼
      highlight_desaturate(RGB_out, Y_out, limit)      极高光去饱和
```

几个关键性质（都有单测钉住）：

- **暗部不动**：`Y = 0` 时增益为 0；`Y = 0.18`（18% 中性灰）时 `0.18^2.5 ≈ 0.013`，
  黑线墨迹不发灰；
- **白点拿满**：`Y → 1` 时 `1^2.5 = 1`，`Y_exp = boost`，纸白被抬到指定倍率；
- **色相不漂**：以亮度标量为载体整体缩放 `R:G:B`，从根本上杜绝逐通道 boost 造成的
  饱和度爆炸与偏色；
- **软肩不炸白**：接近 `peak` 时指数渐近收敛，实测 `boost=8 / peak=4` 收敛在 `3.992`。

### 4.2 `output_encoding`：同一个着色器，两种落地方式

着色器里有一个 `output_encoding` uniform，它**由目标纹理格式推导**，不由调用方随便给：

| 目标格式 | `output_encoding` | 行为 |
|---|---|---|
| `Bgra8Unorm`（8 位） | `0` | 压回 `[0,1]` 并 sRGB 编码 → 只能 SDR 增强 |
| `Rgba16Float`（浮点） | `1` | **直接输出线性值、不钳上限** → 真 HDR |

同时它决定了关掉色调映射（`mode = 0`）时的行为：8 位目标直通（源本来就是 sRGB 编码的），
浮点目标必须先 `srgb_to_linear` 解开，否则整幅画面会明显偏暗。

### 4.3 输出通路与色调映射参数是两件事

```c
// 色调映射参数
int32_t rossi_gpu_present_set_hdr(void* p, uint32_t mode, float boost, float peak, ...);
// 输出通路：0 = Flutter 纹理（8 位），1 = EDR 平台视图（浮点）
int32_t rossi_gpu_present_set_output_mode(void* p, uint32_t mode, ...);
// 当前输出每像素字节数：4 = BGRA8，8 = RGBA16F
int32_t rossi_gpu_present_output_bpp(void* p);
```

拆开是必须的：同一组色调映射参数在两条通路上都合法，只是 8 位通路最后会被压回 SDR。
退回 8 位通路时 `set_output_mode` 会显式把"扩展线性"降级为 SDR 增强 ——
与其继续报着这个名字却只能得到钳制结果，不如让状态可读。

`rossi_gpu_present_output_bpp` 是**判断真 HDR 到底有没有生效的唯一外部硬证据**：
`8` 说明在浮点通路上，`4` 说明还在 8 位通路上。界面上直接显示这个数。

---

## 5. 怎么验证真的在出 HDR

1. 打开**本地**漫画（文件夹 / `.cbz` / `.cbr`）。远端图源不走 GPU 呈现器，这条路不适用。
2. 阅读器中央点击 → 设置 → **阅读** 标签 → 找到 **HDR 与画质增强 (GPU 逆色调映射)**。
   它在"阅读背景"下面（和显示相关的选项放在一起）。
3. 看它显示的两行状态：
   - `🍎 屏幕支持 EDR，当前头顶空间 4.36x（约 436 nit）`
   - `输出通路: RGBA16F 线性浮点（真 HDR）`
4. 选 **真 HDR**，调"高光与白点提升倍率"。

日志里应当出现：

```
[MainFlutterWindow] 已注册 EDR 平台视图工厂 rossi/hdr_surface
[RossiHdrView] EDR 图层就绪 device=Apple M... pixelFormat=rgba16Float colorspace=extendedLinearSRGB
[RossiHdrView] 分配 HDR 缓冲 2560x1440 (64RGBAHalf, extendedLinear)
[GpuPresentBridgeMac] 输出通路 = RGBA16F 线性浮点（EDR，可真 HDR）
```

也可以直接从终端跑起来看 stderr：

```bash
./build/macos/Build/Products/Release/Breeze.app/Contents/MacOS/Breeze 2>&1 | grep -E "RossiHdr|输出通路"
```

调试页（设置 → 全局设置 → 调试 → GPU 上屏）里同样有 HDR 控制条与
`输出: RGBA16F 浮点（真 HDR）　图层: 已接管` 的实时读数。

### 5.1 看什么才算"真 HDR"

不是"更亮"，而是**高光不再被削平**：白底漫画在 `boost = 2` 时纸白约为 200 nit，
在 436 nit 余量的屏幕上它会在**暗环境里明显"发光"**，同时黑线保持纯黑。
把系统显示设置里的 SDR 内容亮度滑块拉低，这种差距会更明显 ——
SDR 内容跟着变暗，EDR 的高光不会。

---

## 6. 实测记录（Rust 侧单测）

`cargo test -p rossi_gpu_present --lib`，全部在真实 wgpu/Metal 适配器上跑：

| 测试 | 断言 | 实测输出 |
|---|---|---|
| `test_hdr_extended_linear_white_exceeds_sdr_limit` | 白点 > 2.0 | `R=3, G=3, B=3, A=1` |
| `test_hdr_extended_linear_peak_rolloff` | `boost=8/peak=4` 收敛且不超峰 | `R=3.9921875` |
| `test_hdr_extended_linear_black_stays_black` | 纯黑 < 0.005 | 通过 |
| `test_hdr_float_target_outputs_linear_not_srgb` | 中灰 128 解成线性 0.2158 | `0.21582031` |
| `test_hdr_sdr_boost_on_float_target_is_linear_and_bounded` | 浮点目标下 SDR 增强收敛于 1.0 | `0.9980469` |
| `test_hdr_sdr_boost_stays_within_sdr_bounds` | 8 位通路不溢出回卷 | 通过 |

---

## 7. 已知边界

- **只有本地漫画**：GPU 呈现器本来就只服务本地来源；远端图源走
  `ImageDisplay` 的 CPU/网络路径，HDR 不适用于它。
- **只有 macOS**：`AppKitView` 是 macOS 专有。Windows 的对应物是
  DXGI swapchain + `DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709`（scRGB），
  结构相同，但需要另写一个 `windows/runner` 侧的平台视图与 Rust 侧通路。
- **平台视图是"昂贵"操作**：Flutter 文档明确说应尽量避免。这里只在用户显式开启
  HDR 时才挂载；默认关闭时整个盒子原样交给 `ImageSurface`，路径与从前逐位一致。
- **`hitTestBehavior` 必须是 `transparent`**：默认的 `opaque` 会把画面区域的点击与
  滑动全部吃掉，后果是翻页、呼出控制栏全失效 —— 画面看着没问题，但阅读器变成一张图。
