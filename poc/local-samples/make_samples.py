#!/usr/bin/env python3
"""生成 `local_core` 的观察用样本（v0.1 判据 A 的手测夹具）。

为什么要有这个脚本：判据 A 的手测需要「一个散图文件夹 + 一个 CBZ + 一个 CBR」，
而且**拒绝路径也要能当场复现**（固实 RAR / 加密 RAR）。这些东西不该靠临时找资源，
应当可重复生成。

图片来自 `vendor/mimageviewer/htdocs/` 的真实截图（按内容去重），
所以它们是**真实内容**而不是纯色测试图 —— 低熵图会让耗时/带宽看起来好得不真实。

用法：
    python poc/local-samples/make_samples.py

产物（`build/` 下，Flutter 默认忽略，不会进仓）：
    build/local-samples/pages/          散图文件夹，1.png..20.png + 干扰项
    build/local-samples/sample.cbz      非固实 zip
    build/local-samples/sample.cbr      非固实、未加密 rar
    build/local-samples/solid.cbr       固实 —— 应被**拒绝**（RarSolid）
    build/local-samples/encrypted.cbr   加密 —— 应被**拒绝**（RarEncrypted）
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC_ROOTS = [REPO / "vendor" / "mimageviewer" / "htdocs"]
OUT = REPO / "build" / "local-samples"

PAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
WANT_PAGES = 20

# 只认能被 local_core 当页面解码的扩展名。webp/超大 png 优先，
# 尺寸大一些才有观察价值。
MIN_BYTES = 60_000


def find_rar() -> str | None:
    for cand in ("rar", "rar.exe"):
        p = shutil.which(cand)
        if p:
            return p
    for p in (r"D:\scoop\shims\rar.exe", r"C:\Program Files\WinRAR\Rar.exe"):
        if os.path.exists(p):
            return p
    return None


def collect_images() -> list[Path]:
    """按内容哈希去重，挑出体积够大的真实图片。"""
    seen: set[str] = set()
    picked: list[Path] = []
    for root in SRC_ROOTS:
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            if ".git" in dirpath:
                continue
            for name in sorted(filenames):
                p = Path(dirpath) / name
                if p.suffix.lower() not in PAGE_EXTS:
                    continue
                try:
                    size = p.stat().st_size
                except OSError:
                    continue
                if size < MIN_BYTES:
                    continue
                digest = hashlib.sha256(p.read_bytes()).hexdigest()
                if digest in seen:
                    continue
                seen.add(digest)
                picked.append(p)
                if len(picked) >= WANT_PAGES:
                    return picked
    return picked


def build_folder(pages_dir: Path, images: list[Path]) -> None:
    if pages_dir.exists():
        shutil.rmtree(pages_dir)
    pages_dir.mkdir(parents=True)

    for i, src in enumerate(images, start=1):
        # 刻意用**非零填充**的编号：1.png / 2.png / ... / 20.png。
        # 字典序会给出 1,10,11,...,2,20,3…，自然序必须给出 1..20 ——
        # 这是「页序由 Rust 侧自然序决定」这条设计在 UI 上唯一看得见的地方。
        shutil.copyfile(src, pages_dir / f"{i}{src.suffix.lower()}")

    # 干扰项，用来验证过滤规则而不是靠运气：
    (pages_dir / "notes.txt").write_text("不是页面\n", encoding="utf-8")  # 扩展名不在白名单
    (pages_dir / "._page1.png").write_bytes(b"\x00\x01")  # macOS 资源叉，应被忽略
    (pages_dir / ".hidden.png").write_bytes(b"\x00\x01")  # 隐藏文件，应被忽略
    (pages_dir / "封面.png").write_bytes((images[0]).read_bytes())  # 非 ASCII 名


def build_zip(out: Path, pages_dir: Path) -> None:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(pages_dir.iterdir()):
            if p.is_file():
                zf.write(p, arcname=p.name)


def run_rar(rar: str, out: Path, pages_dir: Path, extra: list[str]) -> None:
    files = [p.name for p in sorted(pages_dir.iterdir()) if p.is_file()]
    cmd = [rar, "a", "-ep", "-idq", *extra, str(out), *files]
    r = subprocess.run(cmd, cwd=pages_dir, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ! rar 失败 rc={r.returncode}: {r.stdout.strip()} {r.stderr.strip()}")
    else:
        print(f"  生成 {out.name}  ({out.stat().st_size / 1024:.0f} KB)")


def main() -> int:
    images = collect_images()
    if len(images) < WANT_PAGES:
        print(f"只找到 {len(images)} 张可用图片，少于 {WANT_PAGES} 张", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    pages_dir = OUT / "pages"
    build_folder(pages_dir, images)
    print(f"文件夹来源：{pages_dir}  （{len(list(pages_dir.iterdir()))} 个文件）")

    build_zip(OUT / "sample.cbz", pages_dir)
    print(f"  生成 sample.cbz  ({(OUT / 'sample.cbz').stat().st_size / 1024:.0f} KB)")

    rar = find_rar()
    if not rar:
        print("  ! 未找到 rar.exe，跳过 CBR 样本（含两条拒绝路径）")
        return 2

    run_rar(rar, OUT / "sample.cbr", pages_dir, ["-m1"])
    run_rar(rar, OUT / "solid.cbr", pages_dir, ["-s", "-m1"])
    run_rar(rar, OUT / "encrypted.cbr", pages_dir, ["-p123", "-m1"])

    print("\n完成。用探针复核（在 rust/ 下）：")
    for name in ("sample.cbz", "sample.cbr", "solid.cbr", "encrypted.cbr"):
        print(f"  cargo run -p rossi_local_core --bin local_probe -- ../build/local-samples/{name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
