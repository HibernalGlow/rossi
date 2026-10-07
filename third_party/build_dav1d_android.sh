#!/bin/bash
# 一次性搭建安卓交叉编译用的 dav1d 静态库（供 dav1d-sys 的 pkg-config 探测）。
# 产物在 third_party/android_sysroot/<triple>/{lib,include}，全部不入库。
set -euo pipefail

TRIPLE=aarch64-linux-android
API=21
A=/opt/homebrew/share/android-commandlinetools
NDK=$A/ndk/29.0.14206865
BIN=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin
REPO=/Users/glow/Base/Code/Freya/rossi
SRC=$REPO/third_party/dav1d-src
PREFIX=$REPO/third_party/android_sysroot/$TRIPLE

export PATH="$BIN:$PATH"
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 -b 1.5.0 https://code.videolan.org/videolan/dav1d.git "$SRC"
fi

CROSS=$REPO/third_party/meson-android-aarch64.ini
cat > "$CROSS" <<EOF
[binaries]
c = '$BIN/${TRIPLE}${API}-clang'
cpp = '$BIN/${TRIPLE}${API}-clang++'
ar = '$BIN/llvm-ar'
strip = '$BIN/llvm-strip'
ranlib = '$BIN/llvm-ranlib'
pkgconfig = 'pkg-config'

[properties]
sys_root = '$BIN/../sysroot'
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

rm -rf "$SRC/build-cross" "$PREFIX"
meson setup "$SRC/build-cross" "$SRC" \
  --cross-file "$CROSS" \
  --prefix "$PREFIX" \
  --libdir lib \
  --default-library=static \
  -Denable_tests=false \
  -Denable_examples=false \
  -Denable_tools=false \
  -Dbitdepths="['8', '16']"

ninja -C "$SRC/build-cross"
ninja -C "$SRC/build-cross" install

echo "=== installed ==="
find "$PREFIX" -name "*.pc" -o -name "*.a" | sort
pkg-config --modversion --define-prefix dav1d 2>/dev/null || true
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs --cflags dav1d
file "$PREFIX/lib/libdav1d.a" 2>/dev/null | head -2
