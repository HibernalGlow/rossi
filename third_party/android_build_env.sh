#!/bin/bash
# 本机安卓交叉编译环境（source 它，别执行）。
#
# 为什么要这么一坨：Flutter 的 native-assets 钩子会 `rustup run 1.96.1 cargo build`
# 并把父进程环境透传给 cargo，所以这三样都得在**跑 flutter build 的那个 shell** 里设好：
#  1. 工具链自己的 bin 前置 —— `rustup run X cargo`  exec 的是工具链的 cargo，
#     但 cargo 再按 PATH 找 **rustc**；不前置就落到 Homebrew 的 1.98.1 上，
#     那份 sysroot 里没有 aarch64-linux-android 的 std，症状是给最小的 crate
#     都报 `E0463: can't find crate for core`。
#  2. NDK 的 llvm bin —— cc-rs/bindgen 找得到工具。
#  3. PKG_CONFIG_LIBDIR 指向交叉编出来的 dav1d 静态库，并且**只**给这一个目录：
#     用 PKG_CONFIG_PATH 的话 brew 的宿主 dav1d.pc 也在搜索路径里，交叉探测
#     会命中 macOS 那份，编出来是错架构的链接（staticlib 不解析符号，
#     要到最终链接才炸）。
#
# 与 hook/build.dart 的 `_androidEnvironmentVariables` 是互补关系：CC_/AR_/BINDGEN
# 那些由它自己给（它按 codeConfig 里的 NDK 路径生成），这里只补它没转发的
# PKG_CONFIG_* 与 PATH 上的工具链。
A=/opt/homebrew/share/android-commandlinetools
NDK=$A/ndk/29.0.14206865
REPO=/Users/glow/Base/Code/Freya/rossi

export ANDROID_HOME=$A
export ANDROID_SDK_ROOT=$A
export ANDROID_NDK_HOME=$NDK
export ANDROID_NDK_ROOT=$NDK
export JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.12.1/libexec/openjdk.jdk/Contents/Home

export PATH="$HOME/.rustup/toolchains/1.96.1-aarch64-apple-darwin/bin:$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin:$PATH"
export PKG_CONFIG_LIBDIR="$REPO/third_party/android_sysroot/aarch64-linux-android/lib/pkgconfig"
# 同一个值再填一份 PKG_CONFIG_PATH：`.cargo/config.toml` 的 [env] 段里有一条
# 从 Windows 那台机器带来的 PKG_CONFIG_PATH（D:/scoop/...，force=false）。
# force=false 的语义是「已有就不动」，所以这里显式给一个值，那条陈旧路径就进不来。
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export PKG_CONFIG_ALLOW_CROSS=1
# rust-toolchain.toml 钉的 1.96.1 在这台 macOS 27 上：
# 它的 strip 步骤会把 rquickjs-macro 那个 proc-macro dylib 改写成 dyld 拒载的
# Mach-O（"mis-aligned LINKEDIT string pool"），而 rustc 把「载不进去」报成
# **E0463: can't find crate for rquickjs_macro**（一句 dlopen 的影子都没有）。
# 隔离实测：同工具链 `CARGO_PROFILE_DEV_STRIP=none` 可载、1.98.1 默认也可载 ⇒
# 关掉这一步即可，不必动工具链钉版。
export CARGO_PROFILE_DEV_STRIP=none
export ROSSI_ANDROID=1
