#!/usr/bin/env python3
"""从 poc/mask-upright.svg 生成各桌面平台的应用图标。

主图严格遵循 macOS 图标网格：1024 画布内放置 824x824 超椭圆（n=5，实测自
系统自带图标的轮廓），四周各留 100px。小尺寸由主图等比降采样得到。

用法:
    python3 script/build_app_icon.py [--source poc/mask-upright.svg]
"""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CANVAS = 1024
ART = 824  # 图形边长，实测 Apple 系统图标为画布的 80.5%
PAD = (CANVAS - ART) // 2  # 100
EXPONENT = 5.0  # 超椭圆指数，n=5 与 macOS squircle 轮廓拟合误差最小

MASK_WIDTH_RATIO = 0.92  # 面具宽度占图形边长的比例
MASK_OPTICAL_DROP = 0.02  # 视觉重心下移量，给上方的尖角留出呼吸

BG_TOP = "#F5F1EA"
BG_BOTTOM = "#E7DFD3"
EDGE = "#CFC5B7"

MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [256, 128, 64, 48, 32, 16]

MACOS_SET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
ASSET_DIR = ROOT / "asset/image"
WINDOWS_RES = ROOT / "windows/runner/resources"


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, check=True, capture_output=True, **kw)
    return proc


def read_mask(source: Path) -> tuple[str, str]:
    """取出面具的 path 数据与填充色。"""
    svg = source.read_text(encoding="utf-8")
    fill = re.search(r'fill="(#([0-9A-Fa-f]{6}))"', svg)
    body = re.search(r'<path[^>]*\sd="([^"]+)"', svg, re.S)
    if not fill or not body:
        sys.exit(f"{source} 中找不到 fill 颜色或 <path d=...>")
    return " ".join(body.group(1).split()), fill.group(1)


def measure(path: Path) -> tuple[int, int, int, int]:
    """量出透明图形的实际包围盒 (w, h, x, y)。"""
    out = run(
        [
            "magick", str(path), "-alpha", "extract", "-fuzz", "2%",
            "-trim", "-format", "%wx%h%O", "info:",
        ]
    ).stdout.decode()
    w, h, x, y = re.match(r"(\d+)x(\d+)([+-]\d+)([+-]\d+)", out.strip()).groups()
    return int(w), int(h), int(x), int(y)


def squircle_path(size: float, exponent: float, steps: int = 96) -> str:
    """生成超椭圆（squircle）路径，用于裁切背景与描边。"""
    half = size / 2
    pts = []
    for i in range(steps * 4):
        t = i * 2 * math.pi / (steps * 4)
        ct, st = math.cos(t), math.sin(t)
        x = half * abs(ct) ** (2 / exponent) * (1 if ct >= 0 else -1)
        y = half * abs(st) ** (2 / exponent) * (1 if st >= 0 else -1)
        pts.append((round(PAD + half + x, 2), round(PAD + half + y, 2)))
    body = " ".join(f"{'M' if i == 0 else 'L'}{x},{y}" for i, (x, y) in enumerate(pts))
    return f"{body} Z"


def compose(mask_d: str, mask_color: str, mask_box: tuple[int, int, int, int]) -> str:
    """拼出 1024 主图 SVG。mask_box 与 path 数据处于同一坐标系。"""
    bw, bh, bx, by = mask_box
    scale = (ART * MASK_WIDTH_RATIO) / bw
    # 让面具包围盒中心对齐图形中心，再按视觉重心下移
    cx = bx + bw / 2
    cy = by + bh / 2
    tx = CANVAS / 2 - scale * cx
    ty = CANVAS / 2 + ART * MASK_OPTICAL_DROP - scale * cy
    tile = squircle_path(ART, EXPONENT)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <clipPath id="tile"><path d="{tile}"/></clipPath>
    <linearGradient id="paper" x1="0" y1="{PAD}" x2="0" y2="{PAD + ART}" gradientUnits="userSpaceOnUse">
      <stop stop-color="{BG_TOP}"/>
      <stop offset="1" stop-color="{BG_BOTTOM}"/>
    </linearGradient>
    <!-- 暖色暗角：米白底在浅色桌面上容易丢轮廓，靠它把图形边缘撑出来。 -->
    <radialGradient id="vignette" cx="0.5" cy="0.42" r="0.75">
      <stop offset="0.5" stop-color="#8A7A66" stop-opacity="0"/>
      <stop offset="1" stop-color="#8A7A66" stop-opacity="0.26"/>
    </radialGradient>
    <filter id="fibers" x="{bx - 8}" y="{by - 8}" width="{bw + 16}" height="{bh + 16}" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="0.17 0.24" numOctaves="2" seed="24" result="fibers"/>
      <feColorMatrix in="fibers" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0" result="height"/>
      <feDiffuseLighting in="height" surfaceScale="0.5" diffuseConstant="1.01" lighting-color="#ffffff" result="relief">
        <feDistantLight azimuth="225" elevation="62"/>
      </feDiffuseLighting>
      <feComposite in="SourceGraphic" in2="relief" operator="arithmetic" k1="0" k2="1" k3="0.13" k4="-0.119" result="ink"/>
      <feSpecularLighting in="height" surfaceScale="0.5" specularConstant="0.05" specularExponent="6" lighting-color="#e5c3cf" result="gloss">
        <feDistantLight azimuth="225" elevation="62"/>
      </feSpecularLighting>
      <feComposite in="ink" in2="gloss" operator="arithmetic" k1="0" k2="1" k3="0.05" k4="0" result="texture"/>
      <feMorphology in="SourceAlpha" operator="erode" radius="0.8" result="core"/>
      <feGaussianBlur in="core" stdDeviation="0.5" result="soft-core"/>
      <feComposite in="SourceAlpha" in2="soft-core" operator="out" result="rim"/>
      <feFlood flood-color="#762D3F" flood-opacity="0.22" result="rim-color"/>
      <feComposite in="rim-color" in2="rim" operator="in" result="edge"/>
      <feComposite in="edge" in2="texture" operator="over" result="finished"/>
      <feComposite in="finished" in2="SourceAlpha" operator="in"/>
    </filter>
  </defs>

  <g clip-path="url(#tile)">
    <rect width="{CANVAS}" height="{CANVAS}" fill="url(#paper)"/>
    <rect width="{CANVAS}" height="{CANVAS}" fill="url(#vignette)"/>
    <path d="{tile}" fill="none" stroke="{EDGE}" stroke-width="3" stroke-opacity="0.85"/>
    <g transform="translate({tx:.2f},{ty:.2f}) scale({scale:.5f})">
      <path fill="{mask_color}" fill-rule="evenodd" filter="url(#fibers)" d="{mask_d}"/>
    </g>
  </g>
</svg>
"""


def render_master(svg: str, work: Path) -> Path:
    src = work / "app_icon.svg"
    src.write_text(svg, encoding="utf-8")
    master = work / "master.png"
    run(["rsvg-convert", "-w", str(CANVAS), "-h", str(CANVAS), str(src), "-o", str(master)])
    return master


def resample(src: Path, dst: Path, size: int) -> None:
    # -strip 去掉 tIME 等元数据，否则每次重跑都会产生只有时间戳差异的提交
    run(["magick", str(src), "-filter", "lanczos", "-resize", f"{size}x{size}",
         "-strip", str(dst)])


def write_previews(master: Path, work: Path) -> list[Path]:
    """把图标分别压到浅色/深色壁纸上，便于肉眼验收小尺寸表现。"""
    out = []
    for name, color in [("light", "#E9E4DC"), ("dark", "#241D22")]:
        strip = work / f"on-{name}.png"
        args = ["magick", "-size", "760x150", "xc:" + color]
        for i, size in enumerate([128, 64, 32, 24, 16]):
            tile = work / f"tile-{name}-{size}.png"
            resample(master, tile, size)
            args += ["(", str(tile), "-filter", "point", "-resize",
                     f"{size * 2}x{size * 2}", ")", "-gravity", "West"]
            args += ["-geometry", f"+{12 + i * 150}+0", "-composite"]
        run(args + [str(strip)])
        out.append(strip)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=ROOT / "poc/mask-upright.svg")
    ap.add_argument("--preview-dir", type=Path,
                    default=ROOT / "build/icon-preview")
    args = ap.parse_args()

    source: Path = args.source
    if not source.is_absolute():
        source = ROOT / source

    mask_d, mask_color = read_mask(source)
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

        master = render_master(compose(mask_d, mask_color, box), work)

        for size in MACOS_SIZES:
            dst = MACOS_SET / f"app_icon_{size}.png"
            resample(master, dst, size)
            print(f"  -> {dst.relative_to(ROOT)}")

        # Linux（flatpak 与 deb 共用）与应用内展示用的 512 图
        resample(master, ASSET_DIR / "app-icon.png", 512)
        print(f"  -> {ASSET_DIR.relative_to(ROOT) / 'app-icon.png'}")

        # Windows：多尺寸 ICO，避免 16px 处由 256px 强行缩放导致的糊边
        sizes = ",".join(str(s) for s in ICO_SIZES)
        ico = work / "app_icon.ico"
        run(["magick", master, "-define", f"icon:auto-resize={sizes}", str(ico)])
        for target in (ASSET_DIR / "app_icon.ico", WINDOWS_RES / "app_icon.ico"):
            target.write_bytes(ico.read_bytes())
            print(f"  -> {target.relative_to(ROOT)}")

        args.preview_dir.mkdir(parents=True, exist_ok=True)
        for strip in write_previews(master, work):
            out = args.preview_dir / strip.name
            out.write_bytes(strip.read_bytes())
            print(f"  预览: {out}")
        (args.preview_dir / "master.png").write_bytes(master.read_bytes())


if __name__ == "__main__":
    main()
