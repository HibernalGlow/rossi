<a id="top"></a>

<p align="center">
  <img src="./assets/readme/hero.svg" width="100%"
       alt="Rossi —— 跨平台漫画阅读器。把任意第三方图源，装进同一个书架。Any third-party comic source, one shared bookshelf. 支持 Android、iOS、Windows、macOS、Linux，MPL-2.0 授权。">
</p>

<p align="center">
  <b>中文</b> · <a href="#english">English</a>
</p>

## Rossi 是什么

一个用 **Flutter + Rust** 写的跨平台漫画阅读器。

它自己**不带任何漫画内容**。书从哪来，全靠**插件**：一个 JS 文件描述清楚「列表怎么取、搜索怎么发、图片怎么还原」，Rust 侧的 QuickJS 沙箱负责把它跑起来。装什么插件，就读什么源；不装，它就是个读本地 CBZ 的干净书架。

内置哔咔与禁漫两个插件，编译时打包进二进制，开箱即用。

---

## 能力一览

### 图源与搜索

- 内置哔咔、禁漫；也可自行安装 `.js` / `.cjs` / `.br` 插件，或从[插件列表](https://github.com/deretame/Breeze-plugin-list)一键下载、手动更新、拖拽排序。
- **聚合搜索**：一次向多个源发问。搜索支持标签语法与排除词，并带搜索历史。
- EHentai 标签词典随包，中英对照，不用自己猜标签。
- 本地 CBZ / ZIP 与压缩包直接读，不需要先解压。

### 阅读

- 六种读法：从右到左（日漫原样）、从左到右、条漫纵向、双页并排（可无缝拼接、可首页错版）、横长页自动分割、自动滚动。
- **每一本都能单独覆盖设置**，不动全局那一份。
- 墨水屏优化、音量键翻页、左右手模式、环境色背景、缩略图快速跳转、操作栏常驻。
- 桌面端键位全可自定义：键盘、鼠标、鼠标侧键、滚轮、手柄、触屏、区域手势，分「全局」与「阅读器」两套上下文。

### 书架与下载

- 收藏分**本地**与**云端**两种，收藏夹可分组。
- 追更页专门列出「更新了但还没看」的。
- 自研下载队列：任务管理器、失败增量重试、边下边读，可导出 ZIP / 相册 / 文件夹，也能重新导入。
- **WebDAV 与 S3 同步**（含 path-style 开关），支持手动触发上传下载。

### 画面增强

- 四条超分路线，按平台自动挑可用的一档：Rossi 原生 CoreML（ANE / GPU）、mImage ONNX（DirectML / CoreML EP / CPU）、桌面 NCNN（waifu2x、Real-CUGAN）、Android 内置 waifu2x CLI。
- 只在低于设定分辨率时才跑，前后各预取若干页，换模型或换倍率会重算缓存而不是继续显示旧的。
- 超分权重不随包，首次使用时下载。

### 漫画翻译（成品页）

- 检测 → 识别 → 擦字 → 翻译 → 回填，产出一页**重排过的**图，而不是在原文上叠字幕。
- 译文引擎三档自选：API 端点（云端，或本机 Ollama / Foundry Local）、本机混元 Hy-MT2、Apple 系统翻译（端侧离线免费）。
- 术语表每行一条「原文=译文」，专名可以自己钉。
- 目前只做 Windows / Linux / macOS，详见[这一节](#ocr-details)。

### 其他

- 应用内检查更新与更新日志；20 档预设主题色（默认那档就是图标上的「面具红」）+ 跟随系统深浅色 + 动态取色。
- 自定义阅读字体；数据备份导入导出；缓存管理；GitHub / jsdelivr 加速代理；手势与 PIN 应用锁。
- macOS / Linux 系统托盘。

---

## 它是怎么跑起来的

<p align="center">
  <img src="./assets/readme/plugin-architecture.svg" width="100%"
       alt="流程图：第三方图源（内置哔咔、禁漫、自定义 JS）交给 Rust 侧 windcore 沙箱，由 QuickJS 执行插件、reqwest 发请求、负责解码与反混淆和压缩包处理，再经 flutter_rust_bridge 交给 Flutter 界面层的发现、聚合搜索、书架与阅读器。">
</p>

链路是 `Dart → Flutter Rust Bridge → Rust → QuickJS`。插件代码不在 Dart 里跑，也不碰平台 API：它只能描述「发什么请求、怎么解析、图片怎么还原」，网络和文件能力由宿主按 feature 授予。

> ⚠️ **插件仍是 beta 阶段**，API 可能有较大改动，目前更适合学习而非正式开发。
> 但请记住：插件在沙箱内依然能发网络请求、读写文件——**装一个插件，等于信任它写的那段代码。**

- 插件开发文档：<https://deretame.github.io/plugin-dev-docs/>
- 插件列表：<https://github.com/deretame/Breeze-plugin-list>

---

## 六种读法

<p align="center">
  <img src="./assets/readme/reading-experience.svg" width="100%"
       alt="六格示意图：从右到左、从左到右、条漫连读、双页无缝、横长页分割、自动滚动。每一项都能只对当前这本生效。">
</p>

方向、翻页、双页配对、自动滚动间隔这些都不止一个开关，所以做成了「全局一份 + 每本单独覆盖一份」。桌面端还有一套完整的按键绑定编辑器，键盘、鼠标、侧键、滚轮、手柄、触屏、区域手势都能重映射。

---

## 四条超分路线

<p align="center">
  <img src="./assets/readme/super-resolution.svg" width="100%"
       alt="上方是网点糊块经超分恢复为清晰网点的示意图与四条策略；下方是引擎与平台的对应矩阵：Rossi 原生 CoreML 支持 iOS 与 macOS，mImage ONNX 支持 iOS、Windows、macOS、Linux，桌面 NCNN 支持 Windows 与 Linux，内置 waifu2x CLI 只在 Android 上自动使用。">
</p>

矩阵里打勾的是**这条路线在这个平台上真的能跑**。选引擎时不用记这张表——默认值就是本平台可用档里的推荐项，但如果你从别的平台同步过来一个本平台跑不了的设置，它会落回默认而不是报错。

---

<a id="ocr-details"></a>

## 漫画翻译（成品页）

<p align="center">
  <img src="./assets/readme/ocr-translate.svg" width="100%"
       alt="六步流水线：01 检测文字框 PP-OCRv4 det，02 识别台词 manga-ocr，03 擦掉原文 LaMa，04 翻译（三档可选），05 回填排版 霞鹜文楷，06 成品页并在阅读器里按译切换。下方列出三档译文引擎，并注明目前只做 Windows、Linux、macOS。">
</p>

和「叠加一层翻译」的区别在于：这条路会**把原文从图上擦掉**，再按气泡形状把译文排回去，产出的是一张可以直接看的图。在阅读器工具条上按「译」，只切换当前这一页。

需要知道的限制：

- **只有 Windows / Linux / macOS 有。** Android 与 iOS 是有意排除的，不是待办——本仓的 ONNX Runtime 在 linux/android 两段没注册任何加速器 EP，而识别模型是 fp32 的 ViT + BERT，移动端要可用得先做 int8 重导出。所以入口在移动端整条不画，而不是点了报错。
- 权重不随包，约 **660 MB**，首次使用时在设置页下载（PP-OCRv4 检测 + manga-ocr 识别 + LaMa 擦字）。
- 三档译文引擎各有取舍：API 端点要网络或本机服务、支持术语表；混元 Hy-MT2 要自己起 `llama-server`；Apple 系统翻译端侧离线免费，但**没有术语表接口**，这一档下专名会按通用译法翻。
- 端点当时不可用会**降级**：那一页只做擦字与原文回填，不会卡住整本。
- 成品页有缓存，换模型或换字体后可以一键清空（不会动原图）。
- 每一页的六道关都记一行日志，出问题在设置页里能直接看到是哪一步。

---

## 下载与安装

前往 [Releases 页面](https://github.com/deretame/Breeze/releases) 选择对应平台的文件：

| 平台 | 文件 | 安装方式 |
| :--- | :--- | :--- |
| Android / 鸿蒙 | `app-arm64-v8a-release.apk` | 直接安装 |
| Windows | `windows-installer.exe` | 双击运行 |
| macOS | `Breeze-macOS.dmg` 或 Homebrew | `brew install --cask breeze` |
| Linux | `breeze.flatpak` 或 `breeze_*.deb` | Flatpak / apt |
| iOS / iPadOS | `Breeze-iOS.ipa` | 侧载并自行签名 |

<details>
<summary><b>Android / 鸿蒙</b></summary>

下载 `app-arm64-v8a-release.apk` 直接安装。

> **注意**：中国大陆内因未经审核应用可能无法安装，可以使用 [GBox](https://gboxlab.com/i18n/zh-Hant/)、[出境易](https://www.chujingapp.com/) 或 [GSpace](https://gspaceteam.com/)（鸿蒙系统可通过应用商店下载）的方式绕过系统安装器，以安装应用。

</details>

<details>
<summary><b>Windows</b></summary>

下载 `windows-installer.exe` 后直接运行即可完成安装。

需要 Visual Studio (C++) 或相应的 GCC 工具链支持 Rust 的本地编译产物运行。

</details>

<details>
<summary><b>macOS</b></summary>

**方法 1：Homebrew（推荐）**

```bash
brew tap deretame/breeze
brew install --cask breeze

# 升级
brew upgrade breeze

# 彻底卸载，连同数据库、缓存和配置一起清理
# 注意：不会删除你手动导出的文件，但会清空 App 内部数据
brew uninstall --zap breeze
```

**方法 2：手动安装 DMG**

1. 下载最新的 `Breeze-macOS.dmg`。
2. 双击打开，把 `Breeze.app` 拖入 `Applications`（应用程序）文件夹。

> ⚠️ **首次启动（Gatekeeper）**
> 本项目是开源免费软件，未进行 Apple 开发者签名。首次打开若提示**「应用已损坏」**或**「无法验证开发者」**，在终端执行放行命令后即可正常使用：
>
> ```bash
> xattr -cr /Applications/Breeze.app
> ```
>
> 备选：在「应用程序」文件夹中找到 Breeze，按住 `Control` 键点击应用图标，在弹出菜单中选择「打开」。

</details>

<details>
<summary><b>Linux</b></summary>

同时提供 Flatpak 和 DEB 两种包。

**方式 1：DEB**（Debian/Ubuntu 及衍生版）

当前 Release 只提供 `amd64` 架构的 DEB 包。

```shell
# 当前目录只有刚下载的 DEB 包时可以直接用通配符
sudo apt install ./breeze_*.deb

breeze                    # 启动
sudo apt remove breeze    # 卸载
```

`apt` 会自动处理所需的系统依赖。安装完成后可以从应用菜单启动 **Breeze**，也可以在终端直接运行 `breeze`。

> **注意**：DEB 包不保证在所有 Debian/Ubuntu 衍生发行版上的兼容性和可用性。如果安装或运行异常，请改用 Flatpak 版本。

**方式 2：Flatpak**

1. 未配置 Flatpak 的先参考 [Flatpak 快速设置指南](https://flathub.org/zh-Hans/setup)。
   中国大陆用户建议配置 [CERNET 镜像源](https://help.mirrors.cernet.edu.cn/flathub/) 提速。
2. 本项目基于 GNOME 50 Runtime 构建，先装运行时：

   ```shell
   flatpak install flathub org.gnome.Platform//50
   ```

3. 下载 Release 里的 `breeze.flatpak` 并安装：

   ```shell
   flatpak install --user breeze.flatpak
   ```

4. 运行：

   ```shell
   flatpak run io.github.windy.breeze
   ```

</details>

<details>
<summary><b>iOS / iPadOS</b></summary>

iOS 系统封闭，未上架 App Store 的应用需要**侧载 (Sideloading) 并自行签名**。下载无签名的 `Breeze-iOS.ipa`，再用下列工具之一安装。

**推荐：AltStore** —— 目前最稳定且对新手友好，支持通过同一局域网下的电脑自动续签。

- 官网：<https://altstore.io/>
- [AltStore 官方图文指南（英文）](https://faq.altstore.io/)
- [知乎：基于 AltStore 的越狱工具自签教程](https://zhuanlan.zhihu.com/p/143936759)
- [哔哩哔哩：iOS 无限自签 IPA 玩法](https://b23.tv/UbuuJTZ)

**其他自签 / 免签方案**

- **Sideloadly**：免越狱，支持 Windows 和 macOS 的桌面自签工具。[官网与教程](https://sideloadly.io/)
- **TrollStore（巨魔商店）**：如果你的 iOS 版本在漏洞支持范围内，**强烈推荐**，可永久免签安装、永不掉签。[支持版本及安装指南](https://ios.cfw.guide/installing-trollstore/)

</details>

---

## 参与开发

> 面向想改代码的人。只是想用，看完上面就够了。

### 1. 核心工具链

- **Flutter SDK**：需通过 `flutter doctor` 验证。
- **Rust Toolchain**：通过 `rustup` 安装，并添加相应的交叉编译 Target（如 `aarch64-linux-android`）。
- **LLVM / Clang**：涉及 `rustqjs` 等需要解析 C 头的库，必须安装 LLVM（Windows 下推荐 `choco install llvm` 或从官网下载），并配置 `LIBCLANG_PATH`。

### 2. 环境变量

| 变量名 | 说明 | 示例路径（参考） |
| :--- | :--- | :--- |
| **JAVA_HOME** | 编译 Android、Windows 和 Linux 必需 | `C:\Program Files\Android\Android Studio\jbr` |
| **ANDROID_NDK_HOME** | Rust 交叉编译 Android 库必需 | `...\AppData\Local\Android\Sdk\ndk\29.0.14206865` |
| **LIBCLANG_PATH** | 供 `bindgen`（Rust）生成 FFI 绑定使用 | `C:\Program Files\LLVM\bin` |

> 请确保 `PATH` 中包含 `javac` 与 `clang` 的二进制路径。

### 3. 依赖与代码生成

```bash
# 根项目 Flutter 依赖
flutter pub get

# 改过 auto_route / freezed / json_serializable / objectbox / FRB 之后必须重跑
dart ./script/code_generate.dart
```

### 4. 平台特定说明

- **Android**：确保 `local.properties` 指向正确的 SDK 路径。
- **Windows / Linux**：确保安装了 Visual Studio (C++) 或相应的 GCC 工具链，以支持 Rust 的本地编译。
- **仓库结构、构建脚本与约定**：见 [`AGENTS.md`](./AGENTS.md) 与 [`docs/`](./docs/)。

---

<a id="english"></a>

## Rossi in English

<p align="center">
  <a href="#top">中文</a> · <b>English</b>
</p>

A cross-platform manga reader written in **Flutter + Rust**.

It ships **no comic content at all** — where the comics come from is entirely up to **plugins**. One JS file describes how to list, how to search and how to restore the images; a QuickJS sandbox on the Rust side runs it. Install a plugin and that source becomes readable; install none and it stays a clean bookshelf for local CBZ files.

Two plugins, Bika and JM, are built in: `rust/build.rs` downloads their bundles at compile time, so the first run already works.

### Capabilities

#### Sources and search

- Bika and JM built in; install your own `.js` / `.cjs` / `.br` plugins, or pull them from the [plugin list](https://github.com/deretame/Breeze-plugin-list) — one-tap download, manual update, drag to reorder.
- **Aggregate search** asks several sources in one go. Tag syntax and excluded terms are supported, and searches are kept in history.
- The EHentai tag dictionary ships with the app, bilingual, so you don't have to guess tag names.
- Local CBZ / ZIP archives read directly, with no extraction step.

#### Reading

- Six modes: right to left (Japanese order, unmirrored), left to right, webtoon top to bottom, double page (seamless, optional leading blank), split landscape pages, auto read.
- **Every comic can override the settings** without touching the global set.
- E-ink tuning, volume-key page turns, left/right hand mode, ambient background colour, thumbnail scrubbing, persistent control bar.
- Desktop bindings are fully editable: keyboard, mouse, side buttons, wheel, gamepad, touch and region gestures, in separate global and reader contexts.

#### Bookshelf and downloads

- Favorites come in **local** and **cloud** kinds, and can be grouped.
- The follow tab lists exactly what updated but has not been read yet.
- A custom download queue: task manager, incremental retry of failures, read while downloading, export to ZIP / gallery / folder, and re-import.
- **WebDAV and S3 sync** (with a path-style toggle), plus manual upload and download.

#### Picture quality

- Four super-resolution routes, and the app picks a working one per platform: Rossi native CoreML (ANE / GPU), mImage ONNX (DirectML / CoreML EP / CPU), desktop NCNN (waifu2x, Real-CUGAN), and the bundled waifu2x CLI on Android.
- Only runs below a resolution you set, prefetches pages on both sides of the current one, and recomputes the cache when you change model or scale instead of keeping the old result on screen.
- Weights are not bundled; they download on first use.

#### Manga translation (finished pages)

- Detect → recognize → erase → translate → re-typeset, producing a **redrawn page**, not subtitles laid over the original.
- Three translation engines to choose from: an API endpoint (cloud, or local Ollama / Foundry Local), local Hunyuan Hy-MT2, and Apple's system translation (on-device, offline, free).
- Glossary: one `source=target` per line, so proper nouns stay where you put them.
- Windows / Linux / macOS only for now — see [this section](#translation-details).

#### Elsewhere

- In-app update check and changelog; 20 preset theme colours (the default one is the mask red from the icon), light/dark following the system, and dynamic colour.
- Custom reading font; data backup import and export; cache management; GitHub / jsdelivr acceleration proxies; gesture and PIN app lock.
- System tray on macOS and Linux.

---

### How it runs

<p align="center">
  <img src="./assets/readme/plugin-architecture.en.svg" width="100%"
       alt="Flow diagram: comic sources (built-in Bika and JM, plus custom JS plugins) feed into the Rust-side windcore sandbox, where QuickJS executes plugin code, reqwest performs requests, and decoding, de-obfuscation and archive handling happen; flutter_rust_bridge then hands everything to the Flutter UI layer — discovery, aggregate search, bookshelf and reader.">
</p>

The chain is `Dart → Flutter Rust Bridge → Rust → QuickJS`. Plugin code never runs inside Dart and never touches platform APIs: it can only describe which request to send, how to parse the answer and how to restore the image. Network and file capabilities are granted per feature by the host.

> ⚠️ **Plugins are still beta** — the API may change substantially, and today it suits learning better than shipping.
> But remember: inside the sandbox a plugin can still make network requests and read or write files. **Installing a plugin means trusting the code it contains.**

- Plugin development docs: <https://deretame.github.io/plugin-dev-docs/>
- Plugin list: <https://github.com/deretame/Breeze-plugin-list>

---

### Six ways to read

<p align="center">
  <img src="./assets/readme/reading-experience.en.svg" width="100%"
       alt="Six cells: right to left, left to right, webtoon top to bottom, seamless double page, split landscape pages, auto read. Each one can apply to the current comic only.">
</p>

Direction, page turning, double-page pairing and auto-scroll intervals each have more than one switch, so the model is one global set plus a per-comic override. Desktop adds a complete binding editor where keyboard, mouse, side buttons, wheel, gamepad, touch and region gestures can all be remapped.

---

### Four super-resolution routes

<p align="center">
  <img src="./assets/readme/super-resolution.en.svg" width="100%"
       alt="Top: a smeared screentone patch restored to clean dots by super-resolution, with four policies. Bottom: the engine and platform matrix — Rossi native CoreML on iOS and macOS, mImage ONNX on iOS, Windows, macOS and Linux, desktop NCNN on Windows and Linux, and the bundled waifu2x CLI used automatically on Android only.">
</p>

A tick means **this route actually runs on this platform**. You don't have to memorise the table to pick an engine: the default is the recommended option among the ones your platform supports. If a setting synced in from another platform names an engine that cannot run here, it falls back to the default instead of erroring.

| Engine | Backends | Where it runs |
| :--- | :--- | :--- |
| Rossi native CoreML | ANE / GPU | iOS, macOS |
| mImage ONNX | DirectML · CoreML EP · CPU | iOS, Windows, macOS, Linux |
| Desktop NCNN | waifu2x · Real-CUGAN | Windows, Linux |
| Bundled waifu2x CLI | no engine choice, auto-selected | Android |

---

<a id="translation-details"></a>

### Manga translation (finished pages)

<p align="center">
  <img src="./assets/readme/ocr-translate.en.svg" width="100%"
       alt="Six-step pipeline: 01 detect text boxes with PP-OCRv4 det, 02 recognize speech with manga-ocr, 03 erase the original text with LaMa, 04 translate with one of three engines, 05 re-typeset with LXGW WenKai, 06 finished page, toggled per page in the reader. Below, the three translation engines, and a note that this is Windows, Linux and macOS only.">
</p>

Unlike overlaying a translation, this path **erases the original text from the image** and re-typesets the translation into the shape of the bubble, so what you get is a page you can simply read. In the reader toolbar, tap Translate to switch the current page only.

Limits worth knowing:

- **Desktop only.** Android and iOS are excluded on purpose, not left on a backlog: this repo's ONNX Runtime registers no accelerator EP for the linux/android sections, and the recognizer is an fp32 ViT + BERT — making it usable on mobile needs an int8 re-export first. So the entry point is not drawn at all on mobile, rather than drawn and then erroring.
- Weights are not bundled: about **660 MB**, downloaded from the settings page on first use (PP-OCRv4 det + manga-ocr recognition + LaMa erase).
- Each engine trades something off: the API endpoint needs network or a local service and supports the glossary; Hunyuan Hy-MT2 needs you to start `llama-server` yourself; Apple system translation is on-device, offline and free, but **exposes no glossary API**, so on that route proper nouns get the generic translation.
- If the endpoint is unavailable at that moment the page **degrades**: it is erased and re-typeset with the source text instead of stalling the whole chapter.
- Finished pages are cached, and there is a one-tap clear after changing model or font (your originals are never touched).
- All six stages write one log line per page, so when something goes wrong the settings page shows you which stage.

---

### Download and install

Go to the [Releases page](https://github.com/deretame/Breeze/releases) and pick your platform:

| Platform | File | Install |
| :--- | :--- | :--- |
| Android / HarmonyOS | `app-arm64-v8a-release.apk` | Install directly |
| Windows | `windows-installer.exe` | Double-click |
| macOS | `Breeze-macOS.dmg` or Homebrew | `brew install --cask breeze` |
| Linux | `breeze.flatpak` or `breeze_*.deb` | Flatpak / apt |
| iOS / iPadOS | `Breeze-iOS.ipa` | Sideload and re-sign yourself |

<details>
<summary><b>Android / HarmonyOS</b></summary>

Download `app-arm64-v8a-release.apk` and install it directly.

> **Note**: in mainland China an unreviewed app may refuse to install. [GBox](https://gboxlab.com/i18n/zh-Hant/), [出境易](https://www.chujingapp.com/) or [GSpace](https://gspaceteam.com/) (all available in the HarmonyOS app store) work around the system installer.

</details>

<details>
<summary><b>Windows</b></summary>

Download `windows-installer.exe` and run it to install.

Running the Rust-compiled parts locally needs Visual Studio (C++) or an equivalent GCC toolchain.

</details>

<details>
<summary><b>macOS</b></summary>

**Option 1: Homebrew (recommended)**

```bash
brew tap deretame/breeze
brew install --cask breeze

# upgrade
brew upgrade breeze

# remove completely, including database, cache and configuration
# note: files you exported by hand are kept, but in-app data is wiped
brew uninstall --zap breeze
```

**Option 2: install the DMG manually**

1. Download the latest `Breeze-macOS.dmg`.
2. Open it and drag `Breeze.app` into `Applications`.

> ⚠️ **First launch (Gatekeeper)**
> This is free open-source software and carries no Apple developer signature. If macOS says the app is **damaged** or **cannot be verified**, run this in Terminal and it will open normally:
>
> ```bash
> xattr -cr /Applications/Breeze.app
> ```
>
> Alternative: in the Applications folder, hold `Control` and click the app icon, then choose Open from the context menu.

</details>

<details>
<summary><b>Linux</b></summary>

Both Flatpak and DEB packages are published.

**Option 1: DEB** (Debian/Ubuntu and derivatives)

Current releases publish `amd64` DEB only.

```shell
# if the downloaded DEB is the only one in this directory, a glob works
sudo apt install ./breeze_*.deb

breeze                    # start
sudo apt remove breeze    # remove
```

`apt` resolves the system dependencies for you. Afterwards start **Breeze** from the application menu, or run `breeze` in a terminal.

> **Note**: the DEB is not guaranteed to work on every Debian/Ubuntu derivative. If install or startup misbehaves, use the Flatpak build.

**Option 2: Flatpak**

1. If Flatpak is not set up yet, see the [Flathub quick setup guide](https://flathub.org/zh-Hans/setup).
   From mainland China, the [CERNET mirror](https://help.mirrors.cernet.edu.cn/flathub/) is considerably faster.
2. This project builds against the GNOME 50 runtime, so install that first:

   ```shell
   flatpak install flathub org.gnome.Platform//50
   ```

3. Download `breeze.flatpak` from the release and install it:

   ```shell
   flatpak install --user breeze.flatpak
   ```

4. Run it:

   ```shell
   flatpak run io.github.windy.breeze
   ```

</details>

<details>
<summary><b>iOS / iPadOS</b></summary>

iOS is closed: anything not from the App Store has to be **sideloaded and re-signed by you**. Download the unsigned `Breeze-iOS.ipa`, then install it with one of the tools below.

**Recommended: AltStore** — currently the most stable and the friendliest to newcomers, and it re-signs automatically over the local network from a computer.

- Site: <https://altstore.io/>
- [Official AltStore walkthrough](https://faq.altstore.io/)
- [知乎: AltStore-based self-signing tutorial (Chinese)](https://zhuanlan.zhihu.com/p/143936759)
- [哔哩哔哩: unlimited self-signed IPA on iOS (Chinese)](https://b23.tv/UbuuJTZ)

**Other self-signing / no-sign options**

- **Sideloadly**: no jailbreak, desktop self-signing tool for Windows and macOS. [Site and guide](https://sideloadly.io/)
- **TrollStore**: if your iOS version is within the exploit's range, **strongly recommended** — permanent unsigned installs that never drop their signature. [Supported versions and install guide](https://ios.cfw.guide/installing-trollstore/)

</details>

---

### Building from source

> For anyone changing the code. If you only want to read, you can stop above.

#### 1. Core toolchain

- **Flutter SDK**: must pass `flutter doctor`.
- **Rust toolchain**: install via `rustup` and add the cross-compilation targets you need (for example `aarch64-linux-android`).
- **LLVM / Clang**: libraries such as `rustqjs` parse C headers, so LLVM is required (on Windows, `choco install llvm` or the upstream installer), with `LIBCLANG_PATH` configured.

#### 2. Environment variables

| Variable | Why | Example path |
| :--- | :--- | :--- |
| **JAVA_HOME** | Required to build Android, Windows and Linux | `C:\Program Files\Android\Android Studio\jbr` |
| **ANDROID_NDK_HOME** | Required to cross-compile the Rust library for Android | `...\AppData\Local\Android\Sdk\ndk\29.0.14206865` |
| **LIBCLANG_PATH** | Used by `bindgen` (Rust) to generate FFI bindings | `C:\Program Files\LLVM\bin` |

> Make sure `javac` and `clang` are both on `PATH`.

#### 3. Dependencies and code generation

```bash
# root project Flutter dependencies
flutter pub get

# required again after touching auto_route / freezed / json_serializable / objectbox / FRB
dart ./script/code_generate.dart
```

#### 4. Platform notes

- **Android**: point `local.properties` at the right SDK path.
- **Windows / Linux**: install Visual Studio (C++) or an equivalent GCC toolchain so the Rust parts can compile locally.
- **Repository layout, build scripts and conventions**: see [`AGENTS.md`](./AGENTS.md) and [`docs/`](./docs/).

---

> A short English summary of the disclaimer below, for convenience. **The Chinese text is the authoritative version.**
> The app is provided as-is with no warranty of any kind; the developer is not liable for any damage from using, modifying or redistributing it. You are responsible for checking that your use is lawful where you are, and for the content any third-party plugin fetches — the app itself ships none. External contributions represent their authors only. Keep working on a plugin's source before installing it: it runs code you did not write.

---

## 💖 鸣谢

| [![Sentry Logo](asset/sentry-wordmark-dark-400x119.png)](https://sentry.io/) | 本项目由 **[Sentry](https://sentry.io/)** 提供全方位的错误监控赞助，其 Sponsored Business 计划帮助我们更快速地捕获并修复崩溃，提升用户体验。 |
| :--- | :--- |

同时感谢 **[Aidoku](https://github.com/Aidoku/Aidoku)** 项目，本项目在 iOS / macOS 图片超分实现上参考了 Aidoku 的思路与模型处理方式。

---

## 开源项目免责声明

<details>
<summary>点击展开完整声明（8 条）</summary>

1. **项目性质与声明**
   本项目为开源软件，由本人独立开发并维护。项目以“原样”形式提供，开发者不对项目的功能完整性、稳定性、安全性或适用性作出任何明示或暗示的担保。
2. **责任限制**
   开发者对因使用、修改或分发本项目（包括但不限于直接使用、二次开发或集成至其他项目）而导致的任何直接、间接、特殊、附带或后果性损害不承担任何责任。这些损害可能包括但不限于数据丢失、设备损坏、业务中断、利润损失或其他经济损失。
3. **用户责任**
   用户在使用本项目时，应自行评估其适用性并承担所有风险。用户须确保其使用行为符合所在国家或地区的法律法规及道德规范。开发者不对用户因违反法律法规或不当使用本项目而导致的任何后果负责。
4. **第三方依赖与资源**
   本项目可能依赖或引用第三方库、工具、服务或其他资源。开发者不对这些第三方资源的内容、功能、安全性或合法性负责。用户应自行评估并承担使用第三方资源的风险。
5. **无担保声明**
   开发者明确声明不对本项目提供任何形式的担保，包括但不限于：

   - 适销性担保；
   - 特定用途适用性担保；
   - 不侵犯第三方权利担保；
   - 无错误或无中断运行担保。

6. **项目修改与终止**
   开发者保留随时修改、暂停或终止本项目的权利，且无需提前通知用户。开发者不对因项目修改、暂停或终止而导致的任何后果负责。
7. **贡献者责任**
   如果本项目接受外部贡献，贡献者的行为仅代表其个人立场，不代表开发者的观点或立场。开发者对贡献者的行为及其贡献内容不承担责任。
8. **法律合规性**
   用户在使用本项目时，应确保其行为符合所在国家或地区的法律法规。开发者不对用户因违反法律法规而导致的任何后果负责。

**重要提示**
在使用本项目之前，请仔细阅读并理解本免责声明。如果您不同意本声明的任何条款，请立即停止使用本项目。继续使用本项目即表示您已阅读、理解并同意本免责声明的全部内容。

</details>

---

## 许可证

本项目以 **Mozilla Public License 2.0** 授权，详见 [LICENSE](./LICENSE)。

应用本身不包含任何漫画内容，所有内容由第三方插件从其各自的来源获取。开发与使用时需遵守所在地区法律法规。

---

**开发者信息**

- 开发者：**[windy](https://github.com/deretame)**
- 项目仓库：**[Breeze](https://github.com/deretame/Breeze)**
- 联系方式：**[telegram(电报)](https://t.me/breeze_zh_cn)**

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=deretame/Breeze&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=deretame/Breeze&type=Date" />
    <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=deretame/Breeze&type=Date" />
  </picture>
</p>
