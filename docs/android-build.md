# Android 构建：Rust 核心（windcore）的交叉编译前置

> 这份讲的是 **`rust/` 那一坨（windcore + local_core + ocr_core）** 怎么在 Android 上编出来，
> 以及一路踩到的四道墙各自的根因与修法。超分那条 waifu2x CLI 的路子另有一份：
> `docs/android_realsr_build.md`（那部分是 ncnn/OpenCV 的 C++ 构建，与本文无关）。
>
> 本文所有「实测」都是 2026-10-02 在本机（macOS 27 / arm64）跑出来的；
> **哪一条没验，文中会写清楚**。

---

## 0. 一句话现状

`cargo build -p windcore --target aarch64-linux-android` 已经能产出可用的
`libwindcore.so`（ELF aarch64；`DT_NEEDED` 只有 `libc++_shared / libc / liblog / libdl / libm`）。
之前「安卓端全是占位」的根因不是 Dart 层的能力缺失，而是这本仓的 Rust 核心
**从来没有为 Android 编过**：`hook/build.dart` 的安卓分支缺三样环境，
而缺了它们，失败点一个比一个远离真正的原因。

## 1. 本机前置（一次性）

| 东西 | 怎么来 | 注意 |
|---|---|---|
| Android SDK | `/opt/homebrew/share/android-commandlinetools` | `android/local.properties` 的 `sdk.dir` 必须指这儿；默认值曾指向只有 `platform-tools` 的 Caskroom 目录 |
| NDK `29.0.14206865` | `sdkmanager "ndk;29.0.14206865"` | 版本从 `android/app/build.gradle.kts` 的 `ndkVersion` 读，两边要一致 |
| CMake `3.22.1` | `sdkmanager "cmake;3.22.1"` | Gradle 侧要 |
| Rust 的 android std | `rustup target add aarch64-linux-android --toolchain 1.96.1` | **装进实际被用到的那条工具链**：`rust/rust-toolchain.toml` 钉 1.96.1，而 `rustup run 1.96.1 cargo` 会连 rustc 一起切过去；判据看 `~/.rustup/toolchains/1.96.1-aarch64-apple-darwin/lib/rustlib/aarch64-linux-android/` **目录在不在** |
| dav1d 交叉静态库 | `bash third_party/build_dav1d_android.sh` | 见 §2。产物落在 `third_party/android_sysroot/<triple>/`（不入库） |

`third_party/android_build_env.sh` 是给**终端里手动跑 cargo / flutter** 用的环境片
（工具链 bin 前置 + `PKG_CONFIG_LIBDIR` + `CARGO_PROFILE_DEV_STRIP=none`）。
**APK 构建不依赖它** —— 那三样现在由 `hook/build.dart` 自己给（§3）。

## 2. dav1d：为什么必须自己交叉编

`image` 的 `avif-native` → `dav1d-sys`（v0.8.3）。这个 crate **只有 pkg-config 一条路**：
Cargo.toml 里没有 `[features]`，build.rs 用 `system-deps` 探测系统 dav1d。

- 交叉编译时 pkg-config 默认拒绝（`pkg-config has not been configured to support
  cross-compilation`），需要 `PKG_CONFIG_ALLOW_CROSS=1`；
- 它自带的兜底是 `git clone dav1d + meson setup`（**不带 cross file**）——
  会在交叉构建里编出**宿主架构**的 `.a`，而 staticlib 不解析符号，
  错误要到最终链接才炸。所以不能指望它；
- 用 `PKG_CONFIG_PATH` 也**不够**：它是**追加**系统搜索路径，brew 那份宿主的
  `dav1d.pc` 仍会被命中。必须用 **`PKG_CONFIG_LIBDIR`**（替换整个搜索路径）。

`third_party/build_dav1d_android.sh` 做的事：clone dav1d 1.5.0 → 用 NDK clang 的
meson cross file 编成**静态**库（`-Ddefault-library=static`）→ 装进
`third_party/android_sysroot/<triple>/{lib,include}`，于是
`lib/libdav1d.a` + `lib/pkgconfig/dav1d.pc` 都在，静态吸收，不用往 APK 塞额外 `.so`。
验收：`llvm-ar t` 出来的成员是 `ELF 64-bit LSB relocatable, ARM aarch64`（含 `arm_64_*.S.o`）。

### 2.1 `-lpthread` 那道坎

`ort-sys` 给 Android 发的链接参数里有 `-lpthread`，而 bionic 的 pthread **就在 libc 里**、
NDK 的 sysroot 里没有 `libpthread.so`（`ld.lld: error: unable to find library -lpthread`）。
修法是在自己的 sysroot 里放一个**链接脚本**（不是空库）：

```sh
printf 'INPUT(-lc)\n' > third_party/android_sysroot/aarch64-linux-android/lib/libpthread.so
```

这个目录本来就在链接搜索路径上（dav1d 的 `.pc` 带进去的），所以不用另加 `-L`。

## 3. `hook/build.dart` 的安卓分支要给的三样

宿主分支本来就透了 `PKG_CONFIG_PATH`（为 dav1d 而设），安卓分支此前**一样都没给**。
Flutter 起 hook 子进程时**环境是干净的**（本仓 `.cargo/config.toml` 的注释里早有实测记录），
所以这三样只能由 hook 自己写进 cargo 的环境：

1. `PKG_CONFIG_LIBDIR` + `PKG_CONFIG_PATH` + `PKG_CONFIG_ALLOW_CROSS=1`
   → 指向 `third_party/android_sysroot/<triple>/lib/pkgconfig`（§2）。
   目录不存在时不设，并打一行 stderr 说明「dav1d 会退回去编宿主架构」。
2. `CXXFLAGS_<triple>=-DUNIX_TIME_NS` → vendored unrar（`vendor/mimageviewer` 是
   **submodule**，补丁进不去）的 `ulinks.cpp` 在 `__linux` 下走 `lutimes`，
   bionic 没这个函数；定义 `UNIX_TIME_NS` 走它自己写好的 `utimensat` 分支。
3. `CARGO_PROFILE_DEV_STRIP=none` → 见 §4。

## 4. 最贵的一个坑：`E0463: can't find crate for rquickjs_macro`

症状：编译 `rquickjs`（windcore 的依赖，QuickJS 插件运行时的上层绑定）时报
`E0463: can't find crate for rquickjs_macro`。**它跟交叉编译无关、跟 NDK 无关、
跟 pkg-config 无关**，而且报错信息里连一句 dlopen 的影子都没有。

隔离实测（每一步只动一个变量，逐条 dlopen 验产物）：

| 变量 | 产物大小 | `ctypes.CDLL` |
|---|---|---|
| rustc **1.96.1**（`rust-toolchain.toml` 钉的那条）+ 默认 strip | 7.73 MB | **拒载**：`mis-aligned LINKEDIT string pool` |
| rustc 1.96.1 + `CARGO_PROFILE_DEV_STRIP=none` | 7.70 MB | 可载 |
| rustc **1.98.1**（Homebrew）+ 默认 | 6.97 MB | 可载 |

也就是说：**1.96.1 的 strip 这一步在这台 macOS 27 上会把那个 proc-macro dylib
改写成 dyld 拒载的 Mach-O**，而 rustc 把「载不进去」报成了「找不到 crate」。
`rustup run 1.96.1 cargo` 会把工具链 bin 前置到 PATH，所以钩子路径同样走 1.96.1。

修法是给 dev profile 关掉这一步（`CARGO_PROFILE_DEV_STRIP=none`），**不动工具链钉版**。
`--target` 与「宿主编译」都复现了同一条（我先后怀疑过 NDK 的 PATH 前置与全局
`BINDGEN_EXTRA_CLANG_ARGS`，**两条都不成立**，别再从那儿找）。

诊断手法值得留着：`cargo … -vv` 里抄出 `--extern rquickjs_macro=<path>` 的**那个路径**，
再去 `python3 -c "import ctypes; ctypes.CDLL('<path>')"` —— dyld 的真实原因只有这一步能看到。

## 5. ONNX（`ort`）在 Android 上的实际情况

- `ort-sys` 的发行表里 **`aarch64-linux-android` 只有一条**（`nnapi` 那条）；
  `armv7-linux-androideabi` / `x86_64-linux-android` **没有发行包**。
- 本仓三段 `[target.*]` 里，android 落在「其余（linux/android）」那段，EP 特性集为空。
- 实测链接结果：ORT **静态**进了 `libwindcore.so`（`DT_NEEDED` 里没有 `libonnxruntime.so`，
  也没有未解析的 `Ort*` 符号）。运行期额外要的只有 **`libc++_shared.so`**。
- **功能上仍是关着的**：`lib/service/ocr/ocr_settings.dart` 的 `ocrSupportedHere`
  只给桌面三平台；ADR-0018 §决定 6 明确写了移动端不做（manga-ocr 是 fp32、
  权重约 441 MB，要可用得先做 int8/QDQ 重导出）。**「能编」≠「已开」**，这两个别混。

## 6. 还没验的（明确记账）

- **APK 里到底有没有 `libc++_shared.so`**：`libwindcore.so` 的 `DT_NEEDED` 要它，
  少了它 `RustLib.init()` 会在真机上抛。装包前用
  `unzip -l app-debug.apk | grep c++_shared` 核一次；缺了就补进 `jniLibs`。
- **真机**：装包 + `RustLib.init()` 走到哪一步、插件运行时（qjs）能不能加载内置插件，
  都还没在设备上跑过。
- **armv7 / x86_64**：`ort` 没有发行包（§5），那两条 ABI 现在编不出来；
  `build_apk.dart` 默认是分 ABI 的，这一点会挡住「三 ABI 全出」。
