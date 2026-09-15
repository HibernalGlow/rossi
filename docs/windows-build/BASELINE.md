# Windows 构建基线（Phase 0）

- 采集时间：**2026-09-15 22:20 → 22:31**
- 平台：Windows / x64
- 命令：`dart ./script/build_windows.dart --prepare-only`
  （`--prepare-only` = 只跑到 Flutter release 构建；Tauri 安装器打包属发布链路，**不进基线**）

---

## 1. 结论

| 项 | 值 |
|---|---|
| 结果 | **成功**（`exit=0`） |
| 总耗时 | **679 s（11 分 19 秒）** |
| 产物目录 | `build/windows/x64/runner/Release/` |
| 产物总体积 | **68 MB**（其中 `data/` 17 MB） |
| 文件数 | 2 个 `.exe`、20 个 `.dll` |
| 关键产物 | `zephyr.exe` 76.5 KB、`windcore.dll` **25.3 MB**、`flutter_windows.dll` 20.3 MB |
| 构建日志 | `.workbuddy/logs/win-build-20260915-222000.log` |

> **重要前提：这是一次「增量」构建，不是全新构建。**
> `.dart_tool/` 被保留（其中 `hooks_runner/shared/zephyr/build/*/target/` 约 1.7 G
> 是 Rust 的 native-assets 产物），本次**复用了已编译好的 `windcore.dll`**（mtime 21:45，来自更早一次运行）。
> 清掉 `.dart_tool/` 后的全新构建会多出约 15–20 分钟的 Rust 编译，**该数字尚未实测**。
> 后续要在 Gate A 里做前后对比时，必须用同一口径（都是增量、或都是全新）才有意义。

---

## 2. 工具链版本（实测）

| 组件 | 版本 |
|---|---|
| Flutter | **3.47.3** stable（revision `e8113bf456`，2026-09-04） |
| Flutter Engine | `0e228ec8c8d2abc9fcf1d053e8a40665bb859ec7`（revision `06a2e2a110`） |
| Dart（随 Flutter） | 3.13.3 |
| rustc | 1.98.1（默认工具链）；`rust/rust-toolchain.toml` 另有钉版 |
| CMake | 3.31.6-msvc6（VS BuildTools 自带） |
| MSVC 工具集 | 14.44.35207 |
| Windows SDK | 10.0.26100 |
| Visual Studio | BuildTools 2022 17.14.31 |

---

## 3. 产物清单（`build/windows/x64/runner/Release/`）

| 文件 | 字节 | 说明 |
|---|---:|---|
| `zephyr.exe` | 78,336 | Flutter Windows runner 主程序 |
| `windcore.dll` | 26,555,392 | **Rust 主体**（FRB + QuickJS 运行时 + 内置插件 bundle），最大的单个产物 |
| `flutter_windows.dll` | 21,274,112 | Flutter 引擎 |
| `objectbox.dll` | 1,919,488 | ObjectBox 原生库 |
| `flutter_inappwebview_windows_plugin.dll` | 968,704 | |
| `crashpad_handler.exe` | 695,296 | Sentry 崩溃捕获 |
| `sentry.dll` | 454,144 | |
| `crashpad_wer.dll` | 13,312 | |
| `permission_handler_windows_plugin.dll` | 117,248 | |
| `dartjni.dll` | 59,904 | |
| 其余 12 个插件 dll | — | battery_plus / connectivity_plus / dynamic_color / file_selector / flutter_local_notifications / gal / objectbox_flutter_libs / screen_retriever / tray_manager / url_launcher / window_manager 等 |
| `data/`（17 MB） | — | `flutter_assets`、`icudtl.dat`、`app.so`（AOT）等 |

依赖关系上的两点观察（对后续 GPU Reader 有参考价值）：

- `windcore.dll` 比 Flutter 引擎还大（25.3 MB vs 20.3 MB），是**当前包体的主要构成**。
  内置插件 bundle 是编译期从 CDN 下载并打包进二进制的，后续做包体优化时这里是第一嫌疑。
- 桌面端**没有**任何超分相关的原生库（`ncnn` / `waifu2x` / CoreML 都不在）——
  RealSR 模型改为首次使用时下载，与 `AGENTS.md` 的描述一致。

---

## 4. 复现步骤

```bash
cd <repo>
source docs/windows-build/win-baseline-env.sh      # 必须，见该文件注释
dart ./script/build_windows.dart --prepare-only
```

**注意**：涉及删除/替换的步骤（如 `rm -rf build/windows`）在本机必须提权执行，
否则删除会被静默回滚、旧缓存被继承（详见 `README.md` §7.2 与 §7.3）。

---

## 5. 本次踩过的坑（索引）

本次从零搭环境到构建成功，共排除 5 类阻塞，全部记录在同目录 `README.md`：

| # | 问题 | README 章节 |
|---|---|---|
| 1 | 本机无 Flutter SDK / C 盘满 / MSBuild 解析不出 MSVC+SDK 路径 | §0、§7.1 |
| 2 | scoop 的 `NuGet.exe` 是 0 字节 → 插件 CMake 失败 | §2–§5 |
| 3 | NuGet 用户配置里有已废弃源（`nuget.cdn.azure.cn` NXDOMAIN） | §6.4 |
| 4 | VS 缺 ATL 组件 → 装 ATL 时又踩了安装器 3 个坑 | §7.0 |
| 5 | **陈旧 CMake 缓存 → INSTALL 写到 `C:\Program Files\zephyr`** | §7.2 |

第 5 条最隐蔽：症状是 `error MSB3073`（纯噪声），真因要手动跑一次
`cmake -DBUILD_TYPE=Release -P cmake_install.cmake` 才能看到。

---

## 6. 下一步（Phase 0 剩余）

- [x] Windows release 构建基线 —— 本文
- [ ] macOS 构建基线（Gate A 的另一验收平台，需在 macOS 机器上做）
- [ ] **现有 Reader 的性能基线**：帧率 / 内存 / 翻页延迟
- [ ] 全新构建（清 `.dart_tool/`）的耗时，用于区分冷/热构建

第三项是最关键的：**没有它，Gate A 就没有对照物，「达标」无法定义。**
