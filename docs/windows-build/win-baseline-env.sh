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

# ── scoop NuGet.exe 健康检查 ──
# 历史：本机 scoop 的 NuGet.exe 曾是 0 字节（apps/nuget/7.6.0/NuGet.exe），
# 导致 permission_handler_windows 插件的 CMake 在 `nuget install` 阶段
# FATAL_ERROR。该损坏已于 2026-09-15 手工修复为 7.9.0（见
# docs/windows-build/README.md）。
# 原先这里挂的是 `/d/1Dev/tools/nuget` 兜底，但该目录已不存在，且「往 PATH
# 前面塞一个不存在的目录」只会把报错推到 CMake 阶段，所以改成直接喊出来。
if [ ! -s "/d/scoop/apps/nuget/current/NuGet.exe" ]; then
  echo "[rossi-env] 错误：scoop 的 NuGet.exe 缺失或为 0 字节，permission_handler_windows 的 CMake 会在 nuget install 阶段 FATAL_ERROR。请先 'scoop install nuget'（或按 README 手工修复），不要靠 PATH 兜底。" >&2
fi

# ── 构建环境根目录：本文件唯一需要按机器改的一行 ──
# 所有 SDK / 包缓存 / 临时目录都从这个根派生，不要再写死盘符。
# 默认 D:/1Dev 的理由见文件头背景第 1 点（C 盘空间紧张）。换机器或换盘时
# 在 source 之前覆盖即可，不必改本文件：
#   export ROSSI_WIN_ROOT=/f/rossi-env   # MSYS 风格，须与 cygpath 的输入一致
: "${ROSSI_WIN_ROOT:=/d/1Dev}"
export ROSSI_WIN_ROOT
_rossi_root_msys="$ROSSI_WIN_ROOT"
# Windows 风格反斜杠形式（cygpath 不可用时原样透传，保证 WSL 下不炸）
_rossi_root_win=$(cygpath -w "$_rossi_root_msys" 2>/dev/null || echo "$_rossi_root_msys")
# 正斜杠的 Windows 形式（D:/1Dev）—— 下面 PUB_CACHE / TMPDIR 历史上就是这个形状
_rossi_root_fwd=$(cygpath -m "$_rossi_root_msys" 2>/dev/null || echo "$_rossi_root_msys")

# ── Flutter（版本由 .fvmrc / .puro.json 锁定） ──
# 注意：PATH 必须用 MSYS 风格路径（/d/...），Windows 风格 "D:/..." 在
# Git Bash 下 which/bash 解析不到，会导致后续所有命令找不到 flutter。
export FLUTTER_ROOT="$_rossi_root_win\\flutter"
export PATH="$_rossi_root_msys/flutter/bin:$PATH"
# 缺失时立刻喊：否则只会在后面某处得到一句「flutter: command not found」，
# 看不出是 SDK 根目录没装。
if [ ! -x "$_rossi_root_msys/flutter/bin/flutter" ]; then
  echo "[rossi-env] 警告：$_rossi_root_msys/flutter/bin/flutter 不存在 —— Flutter SDK 未安装或 ROSSI_WIN_ROOT 指错了。装好后重跑；若要换位置用 'export ROSSI_WIN_ROOT=…'。" >&2
fi

# ── Dart pub 缓存：默认在 C:\Users\<u>\AppData\Local\Pub\Cache，必须改 ──
export PUB_CACHE="$_rossi_root_fwd/pub-cache"

# ── 临时目录：默认在 C:\Users\<u>\AppData\Local\Temp，必须改 ──
export TMPDIR="$_rossi_root_fwd/tmp"
export TMP="$_rossi_root_win\\tmp"
export TEMP="$_rossi_root_win\\tmp"
# 只在根目录确实存在时才建 tmp，避免 ROSSI_WIN_ROOT 打错时在别的盘上凭空造个目录
[ -d "$_rossi_root_msys" ] && mkdir -p "$_rossi_root_msys/tmp" 2>/dev/null

unset _rossi_root_msys _rossi_root_win _rossi_root_fwd

# ── rquickjs-sys 的 bindgen 需要 libclang ──
export LIBCLANG_PATH="D:/scoop/apps/llvm/current/bin"
export CLANG_PATH="D:/scoop/apps/llvm/current/bin/clang.exe"

# ── Rust 产物留在仓库内 ──
# 原先写死 D:/1VSCODE/Projects/rossi/rust/target，仓库换位置（例如归进 Base）就失效。
# 本文件固定位于 <repo>/docs/windows-build/，据此反推仓根；必须转成 Windows 形式，
# 因为 cargo 是 Windows 可执行文件，读不懂 MSYS 的 /d/... 。
_rossi_self=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export CARGO_TARGET_DIR="$(cygpath -m "$_rossi_self/rust/target" 2>/dev/null || echo "$_rossi_self/rust/target")"
echo "[rossi-env] repo root = $_rossi_self ; CARGO_TARGET_DIR = $CARGO_TARGET_DIR"
unset _rossi_self

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

# ── dav1d：AVIF 解码的**动态**依赖 ──
# rossi_local_core 的 `avif` feature（默认开）让 Rust 侧经 image/avif-native 链接 dav1d。
# 它是动态库，必须和 zephyr.exe 同目录，否则 windcore.dll 加载失败、App 直接起不来。
# 这个变量只回答「dav1d.dll 在哪」——windows/CMakeLists.txt 据此把它装进 bundle。
# 注意：找不到它**不会**让构建失败，只会让产物缺一个运行时依赖（AVIF 页解不出来）。
_rossi_dav1d_dll=""
for _rossi_cand in \
    /d/scoop/persist/vcpkg/installed/*/bin/dav1d.dll \
    /d/scoop/apps/vcpkg/current/installed/*/bin/dav1d.dll; do
  if [ -f "$_rossi_cand" ]; then
    # CMake 认 Windows 风格路径（D:/...），MSYS 的 /d/... 它读不懂。
    _rossi_dav1d_dll=$(cygpath -m "$_rossi_cand" 2>/dev/null || echo "$_rossi_cand")
    break
  fi
done
if [ -n "$_rossi_dav1d_dll" ]; then
  export DAV1D_DLL="$_rossi_dav1d_dll"
  echo "[rossi-env] dav1d.dll = $DAV1D_DLL"
else
  echo "[rossi-env] 警告：未找到 dav1d.dll；AVIF 页运行时会解不出来（见 docs/v0.1-local-core.md）" >&2
fi
unset _rossi_dav1d_dll _rossi_cand

# ── dav1d 的 pkg-config 通道：写进 Cargo 的 [env] 段 ──
# 为什么不能只靠 export：Flutter 跑 native assets 的 hook 时**子进程环境是干净的**
# （实测 PKG_CONFIG_PATH / CARGO_HOME / CARGO_TARGET_DIR 全为空，PATH 里也没有 vcpkg），
# shell 里的 export 传不到 cargo 的 build script。表现为 `flutter build` 挂在
# dav1d-sys 的 build.rs —— 只有一句 "failed to run custom build command"，
# 而同样的 cargo 命令在终端里跑得通。Cargo 自己的 [env] 段不依赖调用者环境，
# 正好补上这一段。
# 生成物不入库（.gitignore 有 .cargo/config.toml），因为里面是本机的 vcpkg 路径。
_rossi_pkgconfig_dir=""
for _rossi_pc in /d/scoop/persist/vcpkg/installed/*/lib/pkgconfig \
                  /d/scoop/apps/vcpkg/current/installed/*/lib/pkgconfig; do
  if [ -f "$_rossi_pc/dav1d.pc" ]; then
    _rossi_pkgconfig_dir=$(cygpath -m "$_rossi_pc" 2>/dev/null || echo "$_rossi_pc")
    break
  fi
done
if [ -n "$_rossi_pkgconfig_dir" ]; then
  _rossi_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  mkdir -p "$_rossi_repo_root/.cargo"
  cat > "$_rossi_repo_root/.cargo/config.toml" <<EOF
# 本文件由 docs/windows-build/win-baseline-env.sh 生成，不入库（.gitignore 有它）。
#
# 为什么要它：Flutter 跑 native assets 的 hook 时子进程环境是干净的
# （实测 PKG_CONFIG_PATH / CARGO_HOME / CARGO_TARGET_DIR 全为空），
# shell 里的 export 传不到 cargo 的 build script。而 image 的 avif-native
# 要经 pkg-config 找 dav1d —— 少了这段，"flutter build" 会挂在 dav1d-sys 的
# build.rs，且只报 "failed to run custom build command"，很难定位。
# Cargo 的 [env] 段不依赖调用者环境，正好补这一段。
#
# force = false 表示环境变量优先：别的机器可以直接 export PKG_CONFIG_PATH 覆盖。
[env]
PKG_CONFIG_PATH = { value = "$_rossi_pkgconfig_dir", force = false }
EOF
  echo "[rossi-env] .cargo/config.toml -> $_rossi_pkgconfig_dir"
else
  echo "[rossi-env] 警告：未找到 dav1d.pc；avif 解码在构建期会失败" >&2
fi
unset _rossi_pkgconfig_dir _rossi_pc _rossi_repo_root
