# Android QNN NPU 超分：出包与真机验收 Runbook

> 阶段一（移植自 mihon_img_upscale）的代码已合入 main。带 NPU 的 APK 必须在
>装有 QAIRT SDK 的机器上构建；CI 产物是 stub（`ROSSI_ENABLE_QNN=0`），安装后
> NPU 引擎会如实报「不可用」。本文是出包 + 两台目标真机（SM8475 / SM8750）的
> 验收步骤与参考基线。

## 0. 前置

- QAIRT SDK **2.49.0.260730**（Qualcomm 官网下载，与 Maven Central 的
  `qnn-runtime:2.49.0` AAR 严格同版）；解压后把路径写进 `android/local.properties`：

  ```properties
  qnn.sdk.dir=/path/to/qairt/2.49.0.260730
  ```

- Android SDK / NDK 29.0.14206865（与 `android/app/build.gradle.kts` 一致）。
- 模型包已托管：`https://github.com/HibernalGlow/breeze-binary/raw/main/realsr-qnn-android.7z`
  （SHA-256 `ab28e693…ed50d6`，应用内自动下载，无需随包）。
- macOS 构建机注意：**Homebrew 的 rust 会挡住 rustup**（`/opt/homebrew/bin/rustc`
  是不带 android std 的 brew 版），rust/hook 会以
  `E0463: can't find crate for core/std` 失败。把钉住的工具链放到 PATH 最前：
  `export PATH="$HOME/.rustup/toolchains/1.96.1-aarch64-apple-darwin/bin:$PATH"`，
  并按 `hook/build.dart` 报错提示设 `ANDROID_NDK_HOME`。
- ferrous-opencc 的 `embedded_map.rs` 若引用了已不存在的旧 hook 缓存路径
  （报 `couldn't read …/build/<hash>/…/out/*.ocb`），把现有 out 目录的
  `*.ocb` 复制到报错里的那个路径即可继续（本机曾观察到删掉的缓存目录被
  旧文件"复活"，根因未明——疑似有文件同步工具在还原 `.dart_tool`）。

## 1. 出带 NPU 的 APK

```bash
# 默认只打 v69 / v79 两档 HTP Skel（约 +121 MB）；目标机正好是这两档
dart ./script/build/build_apk.dart

# 要覆盖更多骁龙（v73/v75/v81，约 +175 MB）时：
#   在 android/gradle.properties 或命令行 -PqnnHtpArchitectures=all
```

确认产物包含 NPU 运行库（任选其一）：

```bash
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep -E 'libQnnHtp.so|libQnnModelDlc.so|libQnnHtpV69|libQnnHtpV79|librealsr_qnn.so'
```

应看到 `librealsr_qnn.so`、`libQnnHtp.so`、`libQnnSystem.so`、`libQnnModelDlc.so`
与 V69/V79 的 Skel/Stub；缺 `libQnnModelDlc.so` 说明 SDK 没接上（只影响设备端
编译上下文，探测仍可用）。DSP / GPU / V68/V73/V75/V81 的库默认被裁剪
（`build.gradle.kts` 的 packaging excludes），出现即说明裁剪配置失效。

## 2. 真机验收清单（每台机器各跑一遍）

安装后：**设置 → 超分 → 模型区**。

1. **探测**：引擎下拉选「NPU（Qualcomm QNN）」后，几秒内应显示
   「检测到 Qualcomm HTP v69（或 v79），NPU 可用」。
   - 显示「不可用」→ 看日志：`adb logcat -s RealSrQnn QnnBackend QualcommHtp QnnModelContexts`。
2. **模型下载**：模型管理区下载（走 breeze-binary），或手动导入 7z；
   导入校验通过即 manifest 哈希核对无误。
3. **上下文准备**：点「准备」——首次约 1–2 s（设备端编译），完成后
   「NPU 上下文已就绪」；失败会显示原因，可重试。
4. **画质对照**（核心验收）：同一批低清漫画页，NPU 的 SE 2× / Pro 2× 降噪3
   与 Vulkan 的 Real-CUGAN 各超分一次，对比线条、文字、网点。
   注意 Pro + 单色页会走 75% 收缩还原方案（网点防护），重点看大平网区域
   有无摩尔纹 / 色块。
5. **整页耗时**：同一页分别用两个引擎计时（日志
   `QNN HTP processing completed in X ms` 与 waifu2x CLI 行），
   记录典型页（约 800×1200）与信息量大的页。
6. **内存与发热**：连续翻 20–30 页后的进程内存
   （设置里已有内存监视通道）与机身发热主观评价；退出阅读器后 NPU 上下文
   会交还（SrSessionGuard），再次进入首页应有 ~45 ms 级上下文重载（日志可证）。
7. **失败语义**：断网/删 DLC 后选 NPU 超分——应明确报错并保留原图，
   **不得**悄悄退回 Vulkan 出图。

## 3. 参考基线（上游 SM8475 / Android 15 / QAIRT 2.49.0 实测，非承诺值）

| 项 | 上游实测 |
|---|---|
| 首次编译上下文（Pro 2× 降噪3） | ~1.72 s |
| 复用后加载上下文 | ~45 ms |
| 单块 256×256 推理（含拷贝） | ~99 ms |
| 测试进程峰值 RSS | ~423 MiB |

上游明确**没有**整页耗时与 Vulkan 对照数据——第 5、6 步的数字由本验收补齐，
作为是否扩展模型清单 / 启动 MihonSY Vulkan 阶段二的依据。

## 4. 验收后的分支

- 通过 → 决定是否启动阶段二（MihonSY 三模型进程内 Vulkan 引擎，方案见
  upstream-sync 讨论记录）；可考虑放宽 `qnnHtpArchitectures` 覆盖更多机型。
- 不通过 → 优先看：上下文编译失败原因（日志有 QNN 原始错误串）、分块接缝
  （对照整图推理）、色彩偏移（单色防护是否误触发）。
