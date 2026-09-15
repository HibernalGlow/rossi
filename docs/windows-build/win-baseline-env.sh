#!/usr/bin/env bash
# Rossi Phase 0 — Windows 构建基线环境
# 用法：source docs/windows-build/win-baseline-env.sh
#
# 背景：
# 1) 本机 C 盘已 100% 占满（仅剩数百 MB），因此所有 SDK、包缓存、临时目录
#    一律重定向到 D 盘。否则 flutter/pub/cargo 会中途写爆系统盘。
# 2) 本机 VS BuildTools 2022 的 MSBuild 无法解析出 VC/SDK 的 include 与 lib
#    路径（VC_IncludePath / WindowsSDK_IncludePath / VC_LibraryPath_x64 /
#    WindowsSDK_LibraryPath_x64 全为空），导致任何 CMake 工程在编译器探测阶段
#    就因 LNK1104 找不到 ucrtd.lib 而失败。绕开方式是把 include/lib 路径
#    以环境变量注入——MSBuild 会把环境变量当属性读取。

# ── 0. 确保走 Git for Windows 的 GNU coreutils（否则本脚本自己就会先坏掉） ──
# 现象：某些 WorkBuddy / 终端会话里 PATH 不含 PortableGit 的 usr/bin，于是
#   bash  -> C:\Windows\System32\bash.exe    <- 这是 **WSL 启动器**，不是 Git Bash
#   sort  -> C:\Windows\System32\sort.exe    <- 不认 -V，下面版本探测直接失败
#   find  -> C:\Windows\System32\find.exe
#   sed   -> 完全缺失
# 后果有两层，而且互不相关，很容易误诊：
#   ① `sort -V` 探测 MSVC/SDK 版本失败 -> IncludePath 注入不进去 ->
#      构建在链接期报 LNK1104 找不到 ucrtd.lib；
#   ② 构建链路里任何一处调用 `bash` 都会拉起 wsl.exe，被安全策略拦截，
#      表现为 "PROGRAM BLOCKED BY SECURITY POLICY - wsl.exe"。
# 修复方式：显式把 Git 的 usr/bin 前置到 PATH。
_rossi_need_git_path=0
case "$(command -v bash 2>/dev/null)" in
  */System32/bash*) _rossi_need_git_path=1 ;;
esac
if [ "$_rossi_need_git_path" = "0" ] && ! sort -V </dev/null >/dev/null 2>&1; then
  _rossi_need_git_path=1
fi
if [ "$_rossi_need_git_path" = "1" ]; then
  for _rossi_git_usr in \
      "/c/Users/$USERNAME/.workbuddy/binaries/PortableGit/versions"/*/usr/bin \
      "/c/Program Files/Git/usr/bin" \
      "/c/Program Files (x86)/Git/usr/bin"; do
    if [ -x "$_rossi_git_usr/bash" ]; then
      export PATH="$_rossi_git_usr:$PATH"
      echo "[rossi-env] 已前置 Git coreutils: $_rossi_git_usr" >&2
      break
    fi
  done
  unset _rossi_git_usr
fi
unset _rossi_need_git_path

# ── scoop NuGet.exe 兜底（默认不启用） ──
# 历史：本机 scoop 的 NuGet.exe 曾是 0 字节（apps/nuget/7.6.0/NuGet.exe），
# 导致 permission_handler_windows 插件的 CMake 在 `nuget install` 阶段
# FATAL_ERROR。该损坏已于 2026-09-15 手工修复为 7.9.0（见
# docs/windows-build/README.md）。
# 这里只在检测到 scoop 侧仍为空/缺失时才挂兜底，避免污染基线环境。
if [ ! -s "/d/scoop/apps/nuget/current/NuGet.exe" ]; then
  echo "[rossi-env] 警告：scoop 的 NuGet.exe 不可用，启用 /d/1Dev/tools/nuget 兜底" >&2
  export PATH="/d/1Dev/tools/nuget:$PATH"
fi

# ── Flutter 3.47.3 (与 .fvmrc / .puro.json 一致) ──
# 注意：PATH 必须用 MSYS 风格路径（/d/...），Windows 风格 "D:/..." 在
# Git Bash 下 which/bash 解析不到，会导致后续所有命令找不到 flutter。
export FLUTTER_ROOT="D:\\1Dev\\flutter"
export PATH="/d/1Dev/flutter/bin:$PATH"

# ── Dart pub 缓存：默认在 C:\Users\<u>\AppData\Local\Pub\Cache，必须改 ──
export PUB_CACHE="D:/1Dev/pub-cache"

# ── 临时目录：默认在 C:\Users\<u>\AppData\Local\Temp，必须改 ──
export TMPDIR="D:/1Dev/tmp"
export TMP="D:\\1Dev\\tmp"
export TEMP="D:\\1Dev\\tmp"

# ── rquickjs-sys 的 bindgen 需要 libclang ──
export LIBCLANG_PATH="D:/scoop/apps/llvm/current/bin"
export CLANG_PATH="D:/scoop/apps/llvm/current/bin/clang.exe"

# ── Rust 产物留在 D 盘项目内（rust/target 默认即可） ──
export CARGO_TARGET_DIR="D:/1VSCODE/Projects/rossi/rust/target"

# ── MSVC / Windows SDK 路径注入（本机必需，见上文背景第 2 点） ──
_rossi_vs_root="C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools"
_rossi_kits_root="C:/Program Files (x86)/Windows Kits/10"

# 取 MSVC 工具集目录下唯一/最新的版本
_rossi_msvc_ver=""
if [ -d "$_rossi_vs_root/VC/Tools/MSVC" ]; then
  _rossi_msvc_ver=$(ls -1 "$_rossi_vs_root/VC/Tools/MSVC" 2>/dev/null | sort -V | tail -1)
fi

# 取 Windows SDK 最新版本（以 Lib 目录为准）
_rossi_sdk_ver=""
if [ -d "$_rossi_kits_root/Lib" ]; then
  _rossi_sdk_ver=$(ls -1 "$_rossi_kits_root/Lib" 2>/dev/null | sort -V | tail -1)
fi

if [ -n "$_rossi_msvc_ver" ] && [ -n "$_rossi_sdk_ver" ]; then
  _rossi_msvc="C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Tools\\MSVC\\$_rossi_msvc_ver"
  _rossi_sdk="C:\\Program Files (x86)\\Windows Kits\\10"

  # ATL(atlmfc) 的 include / lib 不在 MSVC 默认目录下，必须单独追加：
  #   atlbase.h 在 <MSVC>\atlmfc\include，atls.lib 在 <MSVC>\atlmfc\lib\x64
  # 只有装了 Microsoft.VisualStudio.Component.VC.ATL 才有这个目录，故做条件判断。
  _rossi_atl_inc=""
  _rossi_atl_lib=""
  if [ -d "$_rossi_vs_root/VC/Tools/MSVC/$_rossi_msvc_ver/atlmfc/include" ]; then
    _rossi_atl_inc=";$_rossi_msvc\\atlmfc\\include"
    _rossi_atl_lib=";$_rossi_msvc\\atlmfc\\lib\\x64"
  fi

  export IncludePath="$_rossi_msvc\\include$_rossi_atl_inc;$_rossi_sdk\\Include\\$_rossi_sdk_ver\\ucrt;$_rossi_sdk\\Include\\$_rossi_sdk_ver\\shared;$_rossi_sdk\\Include\\$_rossi_sdk_ver\\um"
  export LibraryPath="$_rossi_msvc\\lib\\x64$_rossi_atl_lib;$_rossi_sdk\\Lib\\$_rossi_sdk_ver\\ucrt\\x64;$_rossi_sdk\\Lib\\$_rossi_sdk_ver\\um\\x64"
  echo "[rossi-env] MSVC=$_rossi_msvc_ver  WindowsSDK=$_rossi_sdk_ver  ATL=$([ -n "$_rossi_atl_lib" ] && echo 已装 || echo 未装)  (已注入 IncludePath/LibraryPath)"
else
  echo "[rossi-env] 警告：未能探测到 MSVC 或 Windows SDK，Windows 构建可能失败" >&2
fi
unset _rossi_msvc _rossi_sdk _rossi_vs_root _rossi_kits_root _rossi_msvc_ver _rossi_sdk_ver _rossi_atl_inc _rossi_atl_lib

# ── 镜像加速：Flutter 自举 Dart SDK / 引擎产物走国内镜像 ──
# 实测 storage.flutter-io.cn 约 5.7MB/s，googleapis 约 0.38MB/s
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# ── 关闭 Flutter 遥测与版本检查，压掉基线构建的噪声变量 ──
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
