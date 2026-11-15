#!/usr/bin/env python3
"""把 NDK 的 libc++_shared.so 补进 jniLibs —— CI 构建必需。

Rust 交叉编出的 libwindcore.so 动态链接 NDK 的 C++ 共享运行时，但 Flutter
native-assets 不会自动打包它。本机靠手工放进 jniLibs 的副本能跑；该目录被
.gitignore 忽略，CI checkout 里没有，于是启动时 System.loadLibrary 抛
`UnsatisfiedLinkError: dlopen failed: library "libc++_shared.so" not found`，
v0.1.2 / v0.1.3 / v0.1.3.1 的 CI 包都因此闪退。

本脚本从与 build.gradle.kts 的 ndkVersion 对应的 NDK 复制同一份库，
保证 CI 与本机一致；NDK 升级时不需要改这里。
"""
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GRADLE = ROOT / "android/app/build.gradle.kts"
JNI = ROOT / "android/app/src/main/jniLibs/arm64-v8a"
LIB = "libc++_shared.so"
HOST_TAGS = {
    "linux": "linux-x86_64",
    "darwin": "darwin-x86_64",
    "win32": "windows-x86_64",
}


def ndk_version() -> str | None:
    match = re.search(r'ndkVersion\s*=\s*"([^"]+)"', GRADLE.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def find_ndk() -> Path | None:
    for key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = os.environ.get(key)
        if value and Path(value).is_dir():
            return Path(value)

    version = ndk_version()
    if not version:
        return None
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        base = os.environ.get(key)
        if base:
            candidate = Path(base) / "ndk" / version
            if candidate.is_dir():
                return candidate
    for base in (
        Path("/opt/homebrew/share/android-commandlinetools"),
        Path.home() / "Library/Android/sdk",
    ):
        candidate = base / "ndk" / version
        if candidate.is_dir():
            return candidate
    return None


def main() -> int:
    ndk = find_ndk()
    if ndk is None:
        print("[libc++] 找不到 NDK：请设 ANDROID_NDK_HOME / ANDROID_HOME", file=sys.stderr)
        return 1
    tag = HOST_TAGS.get(sys.platform)
    if tag is None:
        print(f"[libc++] 不支持的平台: {sys.platform}", file=sys.stderr)
        return 1

    src = ndk / f"toolchains/llvm/prebuilt/{tag}/sysroot/usr/lib/aarch64-linux-android/{LIB}"
    if not src.is_file():
        print(f"[libc++] NDK 里没有 {src}", file=sys.stderr)
        return 1

    JNI.mkdir(parents=True, exist_ok=True)
    dst = JNI / LIB
    shutil.copy2(src, dst)
    print(f"[libc++] {src} -> {dst} ({dst.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
