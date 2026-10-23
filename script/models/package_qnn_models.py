#!/usr/bin/env python3
"""Package Android QNN (Qualcomm NPU) super-resolution models into realsr-qnn-android.7z.

Usage:
    python script/models/package_qnn_models.py [source_dir]

The source directory defaults to third_party/qnn-dlc/ and is expected to
contain the FP16 DLC models plus the SHA-256 manifest, extracted from the
Apache-2.0 upstream release (HaoweiLi97/mihon_img_upscale):

    manifest.json
    realcugan-se-x2-no-denoise.dlc
    realcugan-pro-x2-denoise3x.dlc

Only the models referenced by
lib/page/setting/real_sr/service/android_qnn_model_config.dart are packaged
(phase 1: the two candidates above).

How to (re)build the source directory from the upstream release APK:

    gh release download v1.3.16 -R HaoweiLi97/mihon_img_upscale \\
        -p "app-arm64-v8a-release.apk" -O /tmp/mihon.apk
    unzip -o -j /tmp/mihon.apk \\
        "assets/qnn-models/manifest.json" \\
        "assets/qnn-models/realcugan-se-x2-no-denoise.dlc" \\
        "assets/qnn-models/realcugan-pro-x2-denoise3x.dlc" \\
        -d third_party/qnn-dlc/

The archive layout matches what the app expects after extraction into
<getFilePath()>/super_resolution/:

    qnn/manifest.json
    qnn/<model>.dlc

The output archive is written to:
    realsr-qnn-android.7z

Upload this file to the QNN model hosting repository
(HibernalGlow/breeze-binary, see AndroidQnnModelConfig.binaryRepoBaseUrl).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = REPO_ROOT / "third_party" / "qnn-dlc"
OUTPUT = REPO_ROOT / "realsr-qnn-android.7z"

# 与 lib/page/setting/real_sr/service/android_qnn_model_config.dart 的
# AndroidQnnModel 枚举保持一致；改模型清单时两处同步。
PACKAGED_MODELS = [
    "realcugan-se-x2-no-denoise",
    "realcugan-pro-x2-denoise3x",
]


def find_py7zr():
    try:
        import py7zr
        return py7zr
    except ImportError:
        return None


def find_7z_tool():
    """Find an available 7z command-line tool (Bandizip `bz` or 7-Zip `7z`)."""
    for name in ("bz", "7z", "7za"):
        path = shutil.which(name)
        if path:
            return path, name
    return None, None


def create_7z_py7zr(py7zr, output: Path, file_pairs):
    with py7zr.SevenZipFile(output, "w") as archive:
        for full_path, arcname in file_pairs:
            archive.write(full_path, arcname)


def create_7z_cli(tool, tool_name, output: Path, file_pairs):
    staging = output.parent / ".realsr_qnn_staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    try:
        for full_path, arcname in file_pairs:
            dest = staging / arcname
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(full_path, dest)
        # Bandizip `bz` 与 7-Zip `7z` 的 a 命令兼容。
        subprocess.run(
            [tool, "a", str(output)] + [str(p) for p in staging.rglob("*") if p.is_file()],
            check=True,
            cwd=staging,
        )
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.is_dir():
        print(f"Source directory not found: {source}", file=sys.stderr)
        return 1

    files = [Path(source, "manifest.json")]
    for model in PACKAGED_MODELS:
        files.append(Path(source, f"{model}.dlc"))

    missing = [str(f) for f in files if not f.is_file()]
    if missing:
        print("Missing files:", file=sys.stderr)
        for item in missing:
            print(f"  {item}", file=sys.stderr)
        return 1

    file_pairs = [(f, f"qnn/{f.name}") for f in files]

    if OUTPUT.exists():
        OUTPUT.unlink()

    py7zr = find_py7zr()
    tool, _tool_name = find_7z_tool()
    if py7zr is not None:
        create_7z_py7zr(py7zr, OUTPUT, file_pairs)
    elif tool is not None:
        create_7z_cli(tool, _tool_name, OUTPUT, file_pairs)
    else:
        print(
            "Neither py7zr nor a 7z tool (bz/7z/7za) is available.",
            file=sys.stderr,
        )
        return 1

    size_mb = OUTPUT.stat().st_size / (1024 * 1024)
    print(f"Wrote {OUTPUT} ({size_mb:.2f} MiB)")
    print("Next: upload it to HibernalGlow/breeze-binary (main branch),")
    print("the app downloads it from:")
    print("  https://github.com/HibernalGlow/breeze-binary/raw/main/realsr-qnn-android.7z")
    return 0


if __name__ == "__main__":
    sys.exit(main())
