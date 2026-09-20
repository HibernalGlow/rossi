#!/usr/bin/env python3
"""从 poc/mask-upright.svg 生成 macOS 菜单栏（NSStatusItem）用的模板图标。

菜单栏图标只允许一种形态：纯黑图形 + 透明背景，交给系统按 template 图像着色，
这样浅色/深色菜单栏与按下高亮都能自动跟随。画布必须是正方形——tray_manager 会把
NSImage.size 强制设为 iconSize x iconSize，非正方形的位图会被纵向拉伸。

用法:
    python3 script/build_menu_bar_icon.py [--source poc/mask-upright.svg]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_app_icon import measure, read_mask  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

CANVAS = 72  # 输出边长（像素），对应 18pt 的 4 倍
GLYPH_RATIO = 0.94  # 图形长边占画布的比例
INK = "#000000"

ASSET = ROOT / "asset/image/menu_bar_icon.png"

PREVIEW_SIZES = [18, 20, 22, 32, 36]


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True)


def compose(path_d: str, box: tuple[int, int, int, int]) -> str:
    """拼出正方形画布的模板图 SVG。box 与 path 数据处于同一坐标系。"""
    bw, bh, bx, by = box
    scale = (CANVAS * GLYPH_RATIO) / bw
    tx = (CANVAS - bw * scale) / 2 - bx * scale
    ty = (CANVAS - bh * scale) / 2 - by * scale

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <g transform="translate({tx:.3f},{ty:.3f}) scale({scale:.5f})">
    <path fill="{INK}" fill-rule="evenodd" d="{path_d}"/>
  </g>
</svg>
"""


def write_previews(icon: Path, work: Path, out_dir: Path) -> list[Path]:
    """把模板图分别压到浅色/深色底上，模拟菜单栏在两种外观下的观感。

    深色条上先把图形着色成白色：系统的 template 着色就是这个行为。
    """
    out = []
    for name, (color, ink) in [("light", ("#E9E4DC", None)),
                               ("dark", ("#241D22", "#FFFFFF"))]:
        args = ["magick", "-size", f"{110 * len(PREVIEW_SIZES)}x60", "xc:" + color]
        for i, size in enumerate(PREVIEW_SIZES):
            tile = work / f"tile-{name}-{size}.png"
            cmd = ["magick", str(icon), "-filter", "lanczos", "-resize",
                   f"{size}x{size}"]
            if ink:
                cmd += ["-fill", ink, "-colorize", "100"]
            run(cmd + ["-strip", str(tile)])
            args += ["(", str(tile), ")", "-gravity", "West", "-background", color,
                     "-geometry", f"+{25 + i * 110}+0", "-composite"]
        strip = work / f"menu-bar-{name}.png"
        run(args + ["-filter", "point", "-resize", "200%", "-strip", str(strip)])
        out_dir.mkdir(parents=True, exist_ok=True)
        dst = out_dir / strip.name
        dst.write_bytes(strip.read_bytes())
        out.append(dst)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=ROOT / "poc/mask-upright.svg")
    ap.add_argument("--preview-dir", type=Path, default=ROOT / "build/menu-bar-icon")
    args = ap.parse_args()

    source: Path = args.source
    if not source.is_absolute():
        source = ROOT / source

    path_d, _ = read_mask(source)
    vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', source.read_text(encoding="utf-8"))
    vb_w, vb_h = int(vb.group(1)), int(vb.group(2))

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        # 按 viewBox 原始尺寸栅格化，此时像素坐标与 path 数据 1:1，量出的包围盒可直接用
        probe = work / "probe.png"
        run(["rsvg-convert", "-w", str(vb_w), "-h", str(vb_h), str(source),
             "-o", str(probe)])
        box = measure(probe)
        print(f"面具包围盒: {box[0]}x{box[1]} @ {box[2]},{box[3]}")

        src = work / "menu_bar_icon.svg"
        src.write_text(compose(path_d, box), encoding="utf-8")
        run(["rsvg-convert", "-w", str(CANVAS), "-h", str(CANVAS), str(src),
             "-o", str(ASSET)])
        print(f"  -> {ASSET.relative_to(ROOT)}")

        for strip in write_previews(ASSET, work, args.preview_dir):
            print(f"  预览: {strip}")


if __name__ == "__main__":
    main()
