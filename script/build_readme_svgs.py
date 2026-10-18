#!/usr/bin/env python3
"""生成 README 用的 SVG 插图（中文一份 + 英文一份）。

为什么要有这个脚本：README 里同一张图有中英两份，手改两份必然漂移；图里的
圆角/色调/字号又是设计约定（和纸底 + 面具红 + M3E 非对称圆角 22/22/6/22）。
把「画法」放在这里、把「文案」放在 `TEXTS` 里，两侧就只差语言。

用法：
    python3 script/build_readme_svgs.py           # 写 assets/readme/*.svg
    python3 script/build_readme_svgs.py --check   # 只校验，不写盘（CI/判据用）

产物命名：`<name>.svg` 为中文，`<name>.en.svg` 为英文。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "readme"

# ---- 设计令牌（与 poc/mask-upright.svg 的面具红同源） ----
PAPER_TOP = "#F5F1EA"
PAPER_BOTTOM = "#E7DFD3"
CARD = "#FFFFFF"
INK = "#2A2320"
MUTED = "#8A7A66"
LINE = "#CFC5B7"
WINE = "#9C4B5E"
WINE_DEEP = "#762D3F"
TEAL = "#4F7A6F"

SANS = (
    "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', "
    "'Hiragino Sans GB', 'Microsoft YaHei', sans-serif"
)
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"


# ---------------------------------------------------------------- 基础绘制


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def tw(s: str, size: float, mono: bool = False) -> float:
    """粗略字宽，只用来给胶囊/格子留位置，不做精排。"""
    w = 0.0
    for ch in s:
        o = ord(ch)
        if o > 0x2E80:  # CJK 全角
            w += size
        elif ch in " ·/→←—|·":
            w += size * 0.42
        elif ch in "iljI.,:;'|!()[]":
            w += size * 0.32
        else:
            w += size * (0.62 if mono else 0.56)
    return w


def text(
    x: float,
    y: float,
    s: str,
    *,
    size: float = 20,
    fill: str = INK,
    weight: int | None = None,
    anchor: str | None = None,
    mono: bool = False,
    opacity: float | None = None,
    spacing: float | None = None,
) -> str:
    a = f' text-anchor="{anchor}"' if anchor else ""
    w = f' font-weight="{weight}"' if weight else ""
    o = f' fill-opacity="{opacity}"' if opacity is not None else ""
    sp = f' letter-spacing="{spacing}"' if spacing is not None else ""
    fam = MONO if mono else SANS
    return (
        f'<text x="{x:g}" y="{y:g}" font-family="{fam}" font-size="{size:g}"'
        f'{w}{o}{a}{sp} fill="{fill}">{esc(s)}</text>'
    )


def squash(x: float, y: float, w: float, h: float, r=(22, 22, 6, 22)) -> str:
    """M3E 的非对称圆角矩形（TL / TR / BR / BL 各一档）。"""
    tl, tr, br, bl = r
    return (
        f"M{x + tl:g},{y:g} H{x + w - tr:g} "
        f"A{tr:g},{tr:g} 0 0 1 {x + w:g},{y + tr:g} "
        f"V{y + h - br:g} A{br:g},{br:g} 0 0 1 {x + w - br:g},{y + h:g} "
        f"H{x + bl:g} A{bl:g},{bl:g} 0 0 1 {x:g},{y + h - bl:g} "
        f"V{y + tl:g} A{tl:g},{tl:g} 0 0 1 {x + tl:g},{y:g} Z"
    )


def card(
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    rx: float = 18,
    fill: str = CARD,
    fill_opacity: float = 0.42,
    stroke: str | None = LINE,
    sw: float = 1.5,
    dash: str | None = None,
    asymmetric: bool = False,
) -> str:
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    if dash:
        st += f' stroke-dasharray="{dash}"'
    if asymmetric:
        return (
            f'<path d="{squash(x, y, w, h, (22, 22, 6, 22))}" fill="{fill}" '
            f'fill-opacity="{fill_opacity}"{st}/>'
        )
    return (
        f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx:g}" '
        f'fill="{fill}" fill-opacity="{fill_opacity}"{st}/>'
    )


def accent_card(x: float, y: float, w: float, h: float, **kw) -> str:
    kw.setdefault("fill", WINE)
    kw.setdefault("fill_opacity", 0.09)
    kw.setdefault("stroke", WINE)
    kw.setdefault("asymmetric", True)
    return card(x, y, w, h, **kw)


def pill(
    x: float,
    y: float,
    s: str,
    *,
    size: float = 17,
    fg: str = WINE_DEEP,
    bg: str = WINE,
    bg_opacity: float = 0.10,
    h: float = 30,
    mono: bool = False,
    stroke: str | None = None,
    pad: float = 26,
) -> tuple[str, float]:
    w = tw(s, size, mono) + pad
    st = f' stroke="{stroke}" stroke-width="1.2"' if stroke else ""
    out = (
        f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{h / 2:g}" '
        f'fill="{bg}" fill-opacity="{bg_opacity}"{st}/>'
        + text(
            x + w / 2,
            y + h / 2 + size * 0.36,
            s,
            size=size,
            fill=fg,
            anchor="middle",
            mono=mono,
        )
    )
    return out, w


def arrow(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    *,
    color: str = WINE,
    sw: float = 2,
    dash: str | None = None,
) -> str:
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<line x1="{x1:g}" y1="{y1:g}" x2="{x2:g}" y2="{y2:g}" stroke="{color}" '
        f'stroke-width="{sw}"{d} marker-end="url(#arrowhead)" '
        f'stroke-linecap="round"/>'
    )


def dot(x: float, y: float, r: float = 4, color: str = WINE) -> str:
    return f'<circle cx="{x:g}" cy="{y:g}" r="{r:g}" fill="{color}"/>'


def check(x: float, y: float, color: str = WINE_DEEP) -> str:
    return (
        f'<path d="M{x - 7:g},{y:g} l5,6 l10,-13" fill="none" stroke="{color}" '
        f'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'
    )


def dash(x: float, y: float, color: str = MUTED) -> str:
    return f'<line x1="{x - 6:g}" y1="{y:g}" x2="{x + 6:g}" y2="{y:g}" stroke="{color}" stroke-width="2.4" stroke-linecap="round"/>'


def cookie_seat(x: float, y: float, s: float, *, fill=WINE, opacity=0.12) -> str:
    """M3E 的 cookie 形图标座：四瓣、边中收成尖角。"""
    cx, cy, r = x + s / 2, y + s / 2, s / 2
    return (
        f'<path d="M{cx - r:g},{cy:g} '
        f'Q{cx - r * 0.55:g},{cy - r * 1.35:g} {cx:g},{cy - r:g} '
        f'Q{cx + r * 1.35:g},{cy - r * 0.55:g} {cx + r:g},{cy:g} '
        f'Q{cx + r * 0.55:g},{cy + r * 1.35:g} {cx:g},{cy + r:g} '
        f'Q{cx - r * 1.35:g},{cy + r * 0.55:g} {cx - r:g},{cy:g} Z" '
        f'fill="{fill}" fill-opacity="{opacity}"/>'
    )


def page_glyph(
    x: float, y: float, w: float, h: float, *, lines: int = 3, accent: bool = False
) -> str:
    """一页漫画：外框 + 几条分格线。"""
    out = [
        f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="4" '
        f'fill="{"#9C4B5E" if accent else CARD}" '
        f'fill-opacity="{0.14 if accent else 0.9}" stroke="{LINE}" stroke-width="1.4"/>'
    ]
    step = h / (lines + 1)
    for i in range(lines):
        yy = y + step * (i + 1)
        out.append(
            f'<line x1="{x + 6:g}" y1="{yy:g}" x2="{x + w - 6:g}" y2="{yy:g}" '
            f'stroke="{LINE}" stroke-width="1.4"/>'
        )
    return "".join(out)


def header(
    title: str,
    *,
    eyebrow: str = "",
    width: float = 1200,
    top: float = 78,
    rule: bool = True,
) -> str:
    out = [text(64, top, title, size=34, weight=700)]
    if eyebrow:
        out.append(
            text(width - 64, top, eyebrow, size=17, fill=MUTED, anchor="end", mono=True)
        )
    if rule:
        out.append(f'<rect x="64" y="{top + 16}" width="56" height="5" rx="2.5" fill="{WINE_DEEP}"/>')
    return "".join(out)


def frame(w: float, h: float, title: str, desc: str, body: str) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg"
     width="{w:g}" height="{h:g}" viewBox="0 0 {w:g} {h:g}"
     role="img" aria-labelledby="title desc">
  <title id="title">{esc(title)}</title>
  <desc id="desc">{esc(desc)}</desc>

  <defs>
    <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{PAPER_TOP}"/>
      <stop offset="1" stop-color="{PAPER_BOTTOM}"/>
    </linearGradient>
    <marker id="arrowhead" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="{WINE}"/>
    </marker>
  </defs>

  <rect width="{w:g}" height="{h:g}" rx="26" fill="url(#paper)"/>

{body}
</svg>
"""


# ---------------------------------------------------------------- 各张图


def hero(lang: str) -> str:
    t = TEXTS[lang]["hero"]
    body = f"""
  <!-- 漫画分格线：面具的眼眶是镂空的，所以这两条线会正好从眼睛里透出来 -->
  <g stroke="{LINE}" stroke-width="2" opacity="0.5">
    <line x1="979" y1="150" x2="979" y2="392"/>
    <line x1="1069" y1="150" x2="1069" y2="392"/>
  </g>

  <!-- 应用图标真身，path 数据原样取自 poc/mask-upright.svg，未重绘 -->
  <g transform="translate(730.79 173.34) scale(0.52)">
    <path fill="{WINE}" fill-rule="evenodd" d="M 69.89,412.80 C 52.57,402.92 38.15,384.62 33.10,350.38 C 25.84,301.47 46.33,259.52 82.49,228.78 C 108.48,203.59 142.40,185.60 172.80,185.60 L 403.36,185.60 L 496.51,32.00 L 578.98,185.60 L 675.42,32.00 C 711.57,127.45 743.51,205.32 761.88,274.57 C 778.08,326.72 756.63,375.63 730.08,412.80 Z M 429.13,237.41 L 537.20,323.82 C 534.10,342.39 525.06,355.78 507.11,361.76 C 474.06,373.93 444.97,363.73 428.51,336.24 C 417.77,318.50 416.70,277.09 429.13,237.41 Z M 591.75,329.47 L 696.56,246.02 C 707.80,274.26 708.70,310.21 693.80,338.80 C 680.41,364.35 655.99,378.17 633.01,372.73 C 615.68,368.42 602.28,351.78 591.75,329.47 Z"/>
  </g>

  <line x1="64" y1="392" x2="1136" y2="392" stroke="{LINE}" stroke-width="2"/>

  {text(64, 104, t["eyebrow"], size=18, fill=MUTED, mono=True, spacing=3.2)}
  {text(64, 214, "Rossi", size=116, weight=700, fill=WINE, spacing=-2)}
  <rect x="64" y="240" width="84" height="6" rx="3" fill="{WINE_DEEP}"/>
  {text(64, 296, t["line1"], size=30)}
  {text(64, 330, t["line2"], size=21, fill=INK, opacity=0.78)}

  {text(64, 366, t["keywords"], size=18, fill=MUTED)}
  {text(64, 424, t["platforms"], size=18, fill=MUTED, mono=True)}
  {text(1136, 424, "MPL-2.0", size=18, fill=MUTED, anchor="end", mono=True)}
"""
    body = body.replace("<text", "<text")  # keep flake quiet
    return frame(1200, 440, t["title"], t["desc"], body)


def plugin_architecture(lang: str) -> str:
    t = TEXTS[lang]["arch"]
    parts = [header(t["title"], eyebrow="dart → frb → rust → quickjs")]

    # 插件层
    parts.append(card(64, 138, 1072, 88, rx=20))
    parts.append(text(88, 172, t["plugin_label"], size=17, fill=MUTED, mono=True))
    x = 88
    for s in t["plugins"]:
        p, w = pill(x, 186, s, size=18, h=30)
        parts.append(p)
        x += w + 10
    parts.append(text(1112, 204, t["plugin_note"], size=16, fill=MUTED, anchor="end"))

    parts.append(arrow(600, 228, 600, 262))

    # Rust 侧
    parts.append(card(64, 264, 1072, 132, rx=20, fill=WINE, fill_opacity=0.05, stroke=WINE, sw=1.5))
    parts.append(text(88, 296, t["rust_label"], size=17, fill=WINE_DEEP, mono=True))
    tiles = t["rust_tiles"]
    tx, ty = 88, 310
    tw_ = 196
    for i, (name, sub) in enumerate(tiles):
        col, row = i % 5, i // 5
        cx = tx + col * (tw_ + 10)
        cy = ty + row * 62
        parts.append(card(cx, cy, tw_, 54, rx=10, fill=CARD, fill_opacity=0.62))
        parts.append(text(cx + 14, cy + 24, name, size=16, weight=600))
        parts.append(text(cx + 14, cy + 44, sub, size=13, fill=MUTED, mono=True))

    parts.append(arrow(600, 396, 600, 426))

    # 桥
    parts.append(
        f'<rect x="64" y="428" width="1072" height="46" rx="12" fill="{WINE}" fill-opacity="0.1" stroke="{WINE}" stroke-width="1.5"/>'
    )
    parts.append(text(600, 457, t["bridge"], size=19, fill=WINE_DEEP, anchor="middle", weight=600))

    parts.append(arrow(600, 474, 600, 506))

    # Flutter 层
    parts.append(card(64, 508, 1072, 84, rx=20))
    parts.append(text(88, 540, t["ui_label"], size=17, fill=MUTED, mono=True))
    x = 88
    for s in t["ui_items"]:
        p, w = pill(x, 554, s, size=18, h=30, bg=INK, bg_opacity=0.06, fg=INK)
        parts.append(p)
        x += w + 10

    parts.append(text(64, 624, t["footnote"], size=17, fill=MUTED))
    return frame(1200, 656, t["title"], t["desc"], "\n  ".join(parts))


def workbench(lang: str) -> str:
    t = TEXTS[lang]["workbench"]
    parts = [header(t["title"], eyebrow="workspace")]

    # 外框
    parts.append(
        f'<rect x="64" y="132" width="1072" height="430" rx="20" fill="{CARD}" fill-opacity="0.30" stroke="{LINE}" stroke-width="1.5"/>'
    )

    # 左泳道
    parts.append(card(80, 148, 258, 398, rx=16, fill=CARD, fill_opacity=0.55))
    parts.append(text(96, 178, t["lane_left"], size=20, weight=700))
    x = 96
    for s in t["lane_left_tabs"]:
        p, w = pill(x, 190, s, size=13, h=24, pad=18)
        parts.append(p)
        x += w + 5

    # 卡片：收藏 / 历史 / 下载
    labels = t["cards"]
    cy = 226
    for i, (name, meta) in enumerate(labels):
        parts.append(accent_card(96, cy, 226, 62, fill_opacity=0.06 if i else 0.12))
        parts.append(cookie_seat(108, cy + 14, 30, opacity=0.18 if i == 0 else 0.1))
        parts.append(text(148, cy + 28, name, size=17, weight=600))
        parts.append(text(148, cy + 48, meta, size=14, fill=MUTED))
        cy += 70

    # 洞察条
    parts.append(text(96, 448, t["insight_label"], size=15, fill=MUTED, mono=True))
    for i in range(7):
        hgt = [10, 18, 12, 24, 16, 9, 20][i]
        parts.append(
            f'<rect x="{96 + i * 26}" y="{490 - hgt}" width="14" height="{hgt}" rx="4" '
            f'fill="{WINE}" fill-opacity="{0.18 + i * 0.05:.2f}"/>'
        )
    parts.append(text(96, 524, t["insight_note"], size=14, fill=MUTED))

    # 中央阅读器
    parts.append(card(354, 148, 492, 398, rx=16, fill=INK, fill_opacity=0.04, stroke=LINE))
    parts.append(text(370, 178, t["lane_center"], size=20, weight=700))
    # 独占按钮：两个对角括号
    parts.append(
        f'<g stroke="{WINE_DEEP}" stroke-width="2" fill="none" stroke-linecap="round">'
        f'<path d="M796,172 v-6 h6"/><path d="M824,166 h6 v6"/>'
        f'<path d="M796,178 v6 h6"/><path d="M830,178 v6 h-6"/></g>'
    )
    # 页面：左当前、右预取
    parts.append(page_glyph(408, 200, 150, 268, lines=4))
    parts.append(page_glyph(566, 200, 150, 268, lines=4, accent=True))
    parts.append(text(483, 496, t["page_hint_1"], size=14, fill=MUTED, anchor="middle"))
    parts.append(text(641, 496, t["page_hint_2"], size=14, fill=MUTED, anchor="middle"))
    # 底栏工具条
    parts.append(card(370, 512, 460, 26, rx=13, fill=CARD, fill_opacity=0.8))
    for i in range(6):
        parts.append(dot(392 + i * 26, 525, 4, WINE if i != 3 else WINE_DEEP))
    parts.append(text(822, 528, t["toolbar_note"], size=12, fill=MUTED, anchor="end"))

    # 右泳道
    parts.append(card(862, 148, 258, 398, rx=16, fill=CARD, fill_opacity=0.55))
    parts.append(text(878, 178, t["lane_right"], size=20, weight=700))
    tx = 878
    for i, s in enumerate(t["lane_right_tabs"]):
        if i == 3:
            tx = 878
        p, w = pill(tx, 190 + (i // 3) * 30, s, size=13, h=24, pad=18, bg=INK, bg_opacity=0.06, fg=INK)
        parts.append(p)
        tx += w + 5
    ry = 262
    for name, meta in t["right_cards"]:
        parts.append(card(878, ry, 226, 52, rx=12, fill=CARD, fill_opacity=0.7))
        parts.append(text(892, ry + 23, name, size=16, weight=600))
        parts.append(text(892, ry + 42, meta, size=13, fill=MUTED))
        ry += 58

    # 底部说明
    notes = t["notes"]
    ny = 592
    for i, n in enumerate(notes):
        parts.append(dot(70, ny + i * 30 - 5, 3.5, WINE))
        parts.append(text(84, ny + i * 30, n, size=17, fill=MUTED))

    return frame(1200, 690, t["title"], t["desc"], "\n  ".join(parts))


def operation_binding(lang: str) -> str:
    t = TEXTS[lang]["binding"]
    parts = [header(t["title"], eyebrow="adr-0009 · 0015")]

    # 左：输入
    parts.append(text(64, 156, t["col_input"], size=17, fill=MUTED, mono=True))
    ix, iy = 64, 172
    for i, s in enumerate(t["inputs"]):
        col, row = i % 2, i // 2
        p, _ = pill(ix + col * 122, iy + row * 44, s, size=16, h=32, bg=INK, bg_opacity=0.05, fg=INK)
        parts.append(p)

    parts.append(arrow(310, 300, 352, 300))

    # 中：绑定
    parts.append(text(360, 156, t["col_binding"], size=17, fill=MUTED, mono=True))
    by = 176
    for i, (inp, ctx, act) in enumerate(t["bindings"]):
        parts.append(card(360, by, 470, 66, rx=12, fill=CARD, fill_opacity=0.55))
        parts.append(text(378, by + 27, inp, size=16, weight=600, mono=True))
        p, w = pill(830 - 16 - tw(ctx, 13) - 18, by + 10, ctx, size=13, h=22, pad=18)
        parts.append(p)
        parts.append(text(378, by + 52, f"→ {act}", size=14, fill=WINE_DEEP, mono=True))
        by += 70

    parts.append(arrow(846, 300, 886, 300))

    # 右：动作注册表
    parts.append(text(894, 156, t["col_action"], size=17, fill=MUTED, mono=True))
    ay = 176
    for name, label in t["actions"]:
        parts.append(card(894, ay, 242, 44, rx=10, fill=CARD, fill_opacity=0.55))
        parts.append(dot(910, ay + 22, 3.5, WINE))
        parts.append(text(922, ay + 20, name, size=15, mono=True))
        parts.append(text(922, ay + 36, label, size=13, fill=MUTED))
        ay += 52

    # 底部三条纪律
    box_y = 476
    parts.append(card(64, box_y, 1072, 96, rx=16, fill=WINE, fill_opacity=0.06, stroke=WINE))
    for i, s in enumerate(t["rules"]):
        parts.append(check(92, box_y + 30 + i * 28))
        parts.append(text(112, box_y + 35 + i * 28, s, size=17))

    parts.append(text(64, 610, t["footnote"], size=16, fill=MUTED))
    return frame(1200, 640, t["title"], t["desc"], "\n  ".join(parts))


def reading_experience(lang: str) -> str:
    t = TEXTS[lang]["reading"]
    parts = [header(t["title"], eyebrow="reading direction")]

    modes = t["modes"]
    for i, (name, sub, kind) in enumerate(modes):
        col, row = i % 3, i // 3
        x = 64 + col * 368
        y = 146 + row * 174
        parts.append(card(x, y, 336, 150, rx=18))
        gx, gy = x + 26, y + 24

        if kind == "rtl":
            parts.append(page_glyph(gx, gy + 18, 36, 48, lines=1, accent=True))
            parts.append(page_glyph(gx + 46, gy + 18, 36, 48, lines=1))
            parts.append(arrow(gx + 70, gy + 6, gx + 16, gy + 6))
        elif kind == "ltr":
            parts.append(page_glyph(gx, gy + 18, 36, 48, lines=1))
            parts.append(page_glyph(gx + 46, gy + 18, 36, 48, lines=1, accent=True))
            parts.append(arrow(gx + 16, gy + 6, gx + 70, gy + 6))
        elif kind == "scroll":
            parts.append(page_glyph(gx + 14, gy, 44, 76, lines=3))
            parts.append(arrow(gx + 74, gy + 8, gx + 74, gy + 66))
        elif kind == "double":
            parts.append(page_glyph(gx, gy + 18, 41, 48, lines=1, accent=True))
            parts.append(page_glyph(gx + 41, gy + 18, 41, 48, lines=1, accent=True))
            parts.append(
                f'<line x1="{gx + 41}" y1="{gy + 12}" x2="{gx + 41}" y2="{gy + 72}" stroke="{WINE_DEEP}" stroke-width="1.5" stroke-dasharray="4 3"/>'
            )
        elif kind == "split":
            parts.append(page_glyph(gx, gy + 14, 86, 40, lines=0))
            parts.append(
                f'<line x1="{gx + 43}" y1="{gy + 8}" x2="{gx + 43}" y2="{gy + 60}" stroke="{WINE}" stroke-width="1.5" stroke-dasharray="5 4"/>'
            )
            parts.append(arrow(gx + 38, gy - 2, gx + 12, gy - 2))
            parts.append(arrow(gx + 48, gy - 2, gx + 74, gy - 2))
        elif kind == "auto":
            parts.append(page_glyph(gx + 14, gy, 44, 76, lines=3))
            for k in range(3):
                parts.append(
                    f'<line x1="{gx + 20}" y1="{gy + 14 + k * 24}" x2="{gx + 52}" y2="{gy + 14 + k * 24}" stroke="{WINE}" stroke-width="2"/>'
                )
            parts.append(arrow(gx + 74, gy + 8, gx + 74, gy + 66))

        parts.append(text(gx + 106, y + 62, name, size=22, weight=600))
        parts.append(text(gx, y + 126, sub, size=16, fill=MUTED))

    # 底部：新工具
    fy = 512
    parts.append(f'<line x1="64" y1="{fy}" x2="1136" y2="{fy}" stroke="{LINE}" stroke-width="1.5"/>')
    parts.append(text(64, fy + 32, t["extras_label"], size=17, fill=MUTED, mono=True))
    x = 64
    for s in t["extras"]:
        p, w = pill(x, fy + 46, s, size=16, h=30, bg=INK, bg_opacity=0.06, fg=INK)
        parts.append(p)
        x += w + 8
    parts.append(text(64, fy + 106, t["footnote"], size=17, fill=MUTED))
    return frame(1200, 640, t["title"], t["desc"], "\n  ".join(parts))


def display_pipeline(lang: str) -> str:
    t = TEXTS[lang]["display"]
    parts = [header(t["title"], eyebrow="render pipeline")]

    stages = t["stages"]
    n = len(stages)
    gap = 16
    total = 1072
    bw = (total - gap * (n - 1)) / n
    y = 168
    for i, (name, sub) in enumerate(stages):
        x = 64 + i * (bw + gap)
        accent = name == t["source_tag"]
        parts.append(
            card(
                x,
                y,
                bw,
                92,
                rx=14,
                fill=WINE if accent else CARD,
                fill_opacity=0.12 if accent else 0.55,
                stroke=WINE if accent else LINE,
            )
        )
        parts.append(text(x + 14, y + 30, t["stage_no"] % (i + 1), size=12, fill=MUTED, mono=True))
        parts.append(text(x + 14, y + 58, name, size=max(15, 19 - max(0, len(name) - 5)), weight=600))
        parts.append(text(x + 14, y + 80, sub, size=13, fill=MUTED))
        if i < n - 1:
            parts.append(arrow(x + bw + 2, y + 46, x + bw + gap - 4, y + 46))

    # 「非破坏」括号
    by = 296
    parts.append(
        f'<path d="M64,{by + 26} V{by + 10} H{64 + total},V{by + 26}" fill="none" stroke="{WINE}" stroke-width="1.6" stroke-dasharray="5 4"/>'
    )
    parts.append(text(64 + total / 2, by + 50, t["bracket"], size=16, fill=WINE_DEEP, anchor="middle"))

    # 三块说明
    cols = t["notes"]
    ny = 356
    for i, (label, body) in enumerate(cols):
        x = 64 + i * 364
        parts.append(card(x, ny, 344, 96, rx=14, fill=CARD, fill_opacity=0.5))
        parts.append(text(x + 16, ny + 30, label, size=16, weight=600, fill=WINE_DEEP))
        parts.append(text(x + 16, ny + 56, body[0], size=15, fill=MUTED))
        if len(body) > 1:
            parts.append(text(x + 16, ny + 78, body[1], size=15, fill=MUTED))

    # 对比原图 chip
    p, _ = pill(64, 486, t["compare"], size=17, h=34)
    parts.append(p)
    parts.append(text(196, 510, t["compare_note"], size=16, fill=MUTED))

    parts.append(text(64, 574, t["footnote"], size=16, fill=MUTED))
    return frame(1200, 600, t["title"], t["desc"], "\n  ".join(parts))


def super_resolution(lang: str) -> str:
    t = TEXTS[lang]["sr"]
    parts = [header(t["title"], eyebrow="super resolution")]

    # 左：网点对比
    parts.append(card(64, 148, 300, 190, rx=18))
    parts.append(text(88, 180, t["before"], size=15, fill=MUTED))
    parts.append(text(88, 322, t["before_sub"], size=13, fill=MUTED))
    for r in range(5):
        for c in range(5):
            parts.append(f'<circle cx="{96 + c * 14}" cy="{200 + r * 14}" r="5.2" fill="{WINE}" fill-opacity="0.16"/>')
    parts.append(text(206, 180, t["after"], size=15, fill=MUTED))
    parts.append(text(206, 322, t["after_sub"], size=13, fill=MUTED))
    for r in range(5):
        for c in range(5):
            parts.append(f'<circle cx="{214 + c * 14}" cy="{200 + r * 14}" r="3.1" fill="{WINE_DEEP}" fill-opacity="0.55"/>')
    parts.append(text(214, 200 + 4 * 14 + 4 + 26, "", size=12, fill=MUTED))

    # 右：四条路线
    rx0 = 388
    parts.append(text(rx0, 180, t["routes_label"], size=17, fill=MUTED, mono=True))
    ry = 196
    for name, where, note in t["routes"]:
        parts.append(card(rx0, ry, 748, 34, rx=10, fill=CARD, fill_opacity=0.5))
        parts.append(text(rx0 + 14, ry + 23, name, size=16, weight=600))
        parts.append(text(rx0 + 250, ry + 23, where, size=14, fill=MUTED, mono=True))
        parts.append(text(rx0 + 748 - 14, ry + 23, note, size=14, fill=MUTED, anchor="end"))
        ry += 38

    # 矩阵
    my = 384
    cols = t["platforms"]
    parts.append(text(64, my - 12, t["matrix_label"], size=17, fill=MUTED, mono=True))
    col_x = [520, 660, 800, 940, 1080]
    for i, p in enumerate(cols):
        parts.append(text(col_x[i], my + 12, p, size=15, fill=MUTED, anchor="middle", mono=True))
    engines = t["matrix"]
    for r, (engine, cells) in enumerate(engines):
        yy = my + 30 + r * 42
        parts.append(text(64, yy + 22, engine, size=16, weight=600))
        for c, ok in enumerate(cells):
            cx = col_x[c]
            if ok:
                parts.append(check(cx, yy + 16))
            else:
                parts.append(dash(cx, yy + 16))
    parts.append(f'<line x1="64" y1="{my + 24}" x2="1136" y2="{my + 24}" stroke="{LINE}" stroke-width="1.5"/>')

    parts.append(text(64, my + 232, t["footnote"], size=16, fill=MUTED))
    return frame(1200, my + 250 + 24, t["title"], t["desc"], "\n  ".join(parts))


def ocr_translate(lang: str) -> str:
    t = TEXTS[lang]["ocr"]
    parts = [header(t["title"], eyebrow="finished page")]

    steps = t["steps"]
    n = len(steps)
    bw = (1072 - 14 * (n - 1)) / n
    y = 158
    for i, (no, name, sub) in enumerate(steps):
        x = 64 + i * (bw + 14)
        parts.append(card(x, y, bw, 104, rx=14, fill=CARD, fill_opacity=0.55))
        parts.append(text(x + 14, y + 28, no, size=13, fill=WINE_DEEP, mono=True, weight=700))
        parts.append(text(x + 14, y + 58, name, size=max(15, 18 - max(0, len(name) - 6)), weight=600))
        parts.append(text(x + 14, y + 82, sub, size=12, fill=MUTED))
        if i < n - 1:
            parts.append(arrow(x + bw + 2, y + 52, x + bw + 10, y + 52))

    # 三档引擎
    ey = 300
    parts.append(text(64, ey - 12, t["engines_label"], size=17, fill=MUTED, mono=True))
    x = 64
    for name, sub in t["engines"]:
        parts.append(accent_card(x, ey, 344, 76, fill_opacity=0.07))
        parts.append(text(x + 16, ey + 30, name, size=17, weight=600))
        parts.append(text(x + 16, ey + 54, sub, size=14, fill=MUTED))
        x += 364

    # 限制
    ly = 410
    parts.append(card(64, ly, 1072, 128, rx=16, fill=INK, fill_opacity=0.03, stroke=LINE))
    for i, s in enumerate(t["limits"]):
        parts.append(dot(88, ly + 30 + i * 30, 3.5, WINE))
        parts.append(text(102, ly + 35 + i * 30, s, size=16, fill=MUTED))

    parts.append(text(64, ly + 168, t["footnote"], size=16, fill=MUTED))
    return frame(1200, ly + 190, t["title"], t["desc"], "\n  ".join(parts))


def expressive(lang: str) -> str:
    t = TEXTS[lang]["expressive"]
    parts = [header(t["title"], eyebrow="material 3 expressive")]

    tiles = t["tiles"]
    n = len(tiles)
    bw = (1072 - 16 * (n - 1)) / n
    y = 158
    for i, (name, sub, kind) in enumerate(tiles):
        x = 64 + i * (bw + 16)
        parts.append(card(x, y, bw, 170, rx=18, fill=CARD, fill_opacity=0.5))
        cx = x + bw / 2
        if kind == "squircle":
            parts.append(
                f'<path d="{squash(cx - 42, y + 24, 84, 64, (28, 28, 4, 28))}" fill="{WINE}" fill-opacity="0.16" stroke="{WINE}" stroke-width="1.4"/>'
            )
        elif kind == "cookie":
            parts.append(cookie_seat(cx - 34, y + 22, 68, opacity=0.16))
            parts.append(dot(cx, y + 56, 6, WINE_DEEP))
        elif kind == "spring":
            parts.append(
                f'<path d="M{cx - 44},{y + 74} C{cx - 20},{y + 20} {cx + 6},{y + 96} {cx + 44},{y + 40}" '
                f'fill="none" stroke="{WINE}" stroke-width="2.4" stroke-linecap="round"/>'
            )
        elif kind == "layers":
            for k in range(3):
                parts.append(
                    f'<rect x="{cx - 34 + k * 8}" y="{y + 30 + k * 10}" width="58" height="34" rx="8" '
                    f'fill="{WINE}" fill-opacity="{0.06 + k * 0.05:.2f}"/>'
                )
        elif kind == "pill":
            p, _ = pill(cx - 42, y + 44, t["pill_sample"], size=15, h=32)
            parts.append(p)

        parts.append(text(cx, y + 122, name, size=17, weight=600, anchor="middle"))
        parts.append(text(cx, y + 148, sub, size=13, fill=MUTED, anchor="middle"))

    parts.append(text(64, 372, t["footnote"], size=17, fill=MUTED))
    return frame(1200, 410, t["title"], t["desc"], "\n  ".join(parts))


def data_flow(lang: str) -> str:
    t = TEXTS[lang]["data"]
    parts = [header(t["title"], eyebrow="download · sync · backup")]

    cols = t["columns"]
    for i, (title, items, foot) in enumerate(cols):
        x = 64 + i * 364
        y = 158
        parts.append(card(x, y, 344, 300, rx=18, fill=CARD, fill_opacity=0.5))
        parts.append(text(x + 18, y + 34, title, size=20, weight=700))
        parts.append(f'<rect x="{x + 18}" y="{y + 44}" width="40" height="4" rx="2" fill="{WINE_DEEP}"/>')
        iy = y + 76
        for s in items:
            parts.append(dot(x + 24, iy - 5, 3.4, WINE))
            parts.append(text(x + 38, iy, s, size=15, fill=INK, opacity=0.86))
            iy += 30
        parts.append(text(x + 18, y + 276, foot, size=13, fill=MUTED))

    # 底部：一条数据进出的横轴
    ay = 496
    parts.append(f'<line x1="64" y1="{ay}" x2="1136" y2="{ay}" stroke="{LINE}" stroke-width="1.5"/>')
    parts.append(text(64, ay + 34, t["axis_label"], size=16, fill=MUTED, mono=True))
    x = 64
    for s in t["axis"]:
        p, w = pill(x, ay + 48, s, size=15, h=30, bg=INK, bg_opacity=0.06, fg=INK)
        parts.append(p)
        x += w + 8
    parts.append(text(64, ay + 112, t["footnote"], size=16, fill=MUTED))
    return frame(1200, 640, t["title"], t["desc"], "\n  ".join(parts))


# ---------------------------------------------------------------- 文案


TEXTS: dict[str, dict[str, dict]] = {
    "zh": {
        "hero": {
            "title": "Rossi —— 跨平台漫画阅读器",
            "desc": (
                "和纸色卡片上，左侧是 Rossi 字样、中英双语的一句话定位，"
                "以及 Material 3 Expressive 与工作台的落款；右侧是应用图标那只酒红色猫面具，"
                "它趴在一条横线上，两只眼睛是镂空的分格窗，透出背后的漫画分格线。"
            ),
            "eyebrow": "FLUTTER + RUST · MATERIAL 3 EXPRESSIVE",
            "line1": "把任意第三方图源，装进同一个书架。",
            "line2": "Any third-party comic source, one shared bookshelf.",
            "keywords": "图源插件 · 工作台泳道 · 本地与云端收藏 · 超分 · 成品页翻译 · 视频页",
            "platforms": "Android · iOS · Windows · macOS · Linux",
        },
        "arch": {
            "title": "它是怎么跑起来的",
            "desc": (
                "四层竖排：插件层（内置哔咔、禁漫与自装 JS）向下进入 Rust 侧 windcore，"
                "里面是 QuickJS 沙箱、reqwest、解码与反混淆、归档与视频；"
                "再经 flutter_rust_bridge 交给 Flutter 界面层的工作台、发现、阅读器、书架与设置。"
            ),
            "plugin_label": "PLUGINS · JS",
            "plugins": ["内置哔咔", "内置禁漫", "自装 .js / .cjs / .br"],
            "plugin_note": "编译期打包进二进制",
            "rust_label": "RUST · windcore",
            "rust_tiles": [
                ("QuickJS 沙箱", "插件只能发请求、读文件"),
                ("reqwest", "网络由宿主授予"),
                ("解码 · 反混淆", "降采样在出口"),
                ("归档 local_core", "CBZ / CBR / 7z"),
                ("上屏 gpu_present", "GPU 共享纹理"),
            ],
            "bridge": "flutter_rust_bridge —— 只过数据，不过权限",
            "ui_label": "FLUTTER",
            "ui_items": ["工作台泳道", "发现 · 聚合搜索", "阅读器", "书架 · 下载", "设置 · 同步"],
            "footnote": "插件代码不在 Dart 里跑，也不碰平台 API；能做什么由宿主按 feature 授予。",
        },
        "workbench": {
            "title": "工作台：泳道 → 面板 → 卡片",
            "desc": (
                "三列示意：左泳道是书架、收藏、历史、下载与洞察卡片；中央是阅读器泳道，"
                "可一键独占整条可用宽；右泳道是发现、文件管理器、页序、插件、控制与信息面板。"
                "底部说明鼠标在哪条泳道键位就归哪条、面板可折叠重排。"
            ),
            "lane_left": "书架",
            "lane_left_tabs": ["收藏", "历史", "下载"],
            "cards": [
                ("我的收藏", "本地 · 云端 · 分组"),
                ("阅读历史", "最近在读"),
                ("下载与离线", "队列 · 存储统计"),
            ],
            "insight_label": "INSIGHTS · 近 7 日",
            "insight_note": "连续阅读 · 热力 · 来源拆分",
            "lane_center": "阅读器",
            "page_hint_1": "左：当前页",
            "page_hint_2": "右：预取的下一页",
            "page_hint_3": "GPU 共享纹理上屏",
            "toolbar_note": "读法 · 裁边 · 超分 · 译",
            "lane_right": "发现",
            "lane_right_tabs": ["文件", "页序", "插件", "控制", "信息", "工具"],
            "right_cards": [
                ("文件管理器", "标签页 · 多选 · 回收站"),
                ("页内目录", "跳页 · 搜索 · 面板控制"),
                ("图源与扩展", "插件状态卡"),
            ],
            "notes": [
                "泳道可折叠、可重排；中央那条可以独占整条可用宽。",
                "鼠标在哪条泳道，键位就归哪条——输入即时归属，不必先等动画停稳。",
                "每张卡片按跨度自选档位，窄槽位与全宽都不溢出。",
            ],
        },
        "binding": {
            "title": "操作绑定：输入 → 动作",
            "desc": (
                "左侧七类输入（键盘、鼠标、侧键、滚轮、手柄、触屏、区域手势）映射到中间带上下文的绑定，"
                "再指向右侧动作注册表里的稳定 id；底部三条纪律：冲突阻止保存、绑定包可导出导入、低优先级上下文可被隔离。"
            ),
            "col_input": "INPUT",
            "inputs": ["键盘", "鼠标", "鼠标侧键", "滚轮", "手柄", "触屏", "区域手势"],
            "col_binding": "BINDING",
            "bindings": [
                ("Space · 滚轮↓", "阅读器", "reader.next-page"),
                ("键盘 ←→", "阅读器", "reader.page-turn"),
                ("侧键 X1", "全局", "shelf.open-selected"),
                ("长按画面", "阅读器", "reader.loupe"),
            ],
            "col_action": "ACTION",
            "actions": [
                ("reader.next-page", "下一页"),
                ("reader.page-turn", "按读法翻页"),
                ("reader.loupe", "页面放大镜"),
                ("shelf.open-selected", "打开选中"),
            ],
            "rules": [
                "同一上下文里两条绑定撞同一个输入 → 阻止保存，不是警告。",
                "绑定包是 JSON（format + format_version），换机与分享都靠它。",
                "上下文有优先级，低优先级可在高优先级下被隔离。",
            ],
            "footnote": "动作必须由注册表声明（id + 显示名 + 分类 + 上下文），不能藏在 controller 私有方法里。",
        },
        "reading": {
            "title": "六种读法，同一套手势",
            "desc": (
                "六格示意图：从右到左、从左到右、条漫纵向、双页无缝、横长页分割、自动滚动。"
                "底部补充放大镜、手动页序、幻灯片、章节已读与轮盘等新工具。"
            ),
            "modes": [
                ("从右到左", "日漫原样，不需要镜像", "rtl"),
                ("从左到右", "国漫与译制版走这一档", "ltr"),
                ("条漫连读", "从上到下滚动，也能点击翻页", "scroll"),
                ("双页无缝", "左右各占一半，消掉中缝留白", "double"),
                ("横长页分割", "跨页大图切成左右两半读", "split"),
                ("自动滚动", "间隔与距离可调，含墨水屏优化", "auto"),
            ],
            "extras_label": "ALSO IN THE READER",
            "extras": ["页面放大镜", "手动页序", "幻灯片自动翻页", "章节已读标记", "径向轮盘"],
            "footnote": "以上每一项都能只对当前这本生效；桌面端键盘、鼠标、侧键、滚轮、手柄、触屏的绑定全部可改。",
        },
        "display": {
            "title": "非破坏式显示处理层",
            "desc": (
                "七个阶段横向排列：解码原图、裁边、降噪、调色、超分、翻译、上屏。"
                "下方说明每一步都产出可失效的派生位图，原图永远是真相；缓存键把内容与参数版本一起编进去。"
            ),
            "stages": [
                ("解码原图", "降采样在出口"),
                ("裁边", "自动去白边"),
                ("降噪", "JPEG / AI"),
                ("调色", "色调补正"),
                ("超分", "按需 · 预取两侧"),
                ("翻译", "成品页"),
                ("上屏", "GPU 纹理"),
            ],
            "source_tag": "解码原图",
            "stage_no": "%02d",
            "bracket": "以上每一步都不改原文件，只产出派生位图",
            "notes": [
                ("原图是唯一真相", ["派生位图缺失或被清掉", "时静默回落，不阻塞翻页。"]),
                ("缓存键编全输入", ["译文语言、模型、倍率、字体、", "参数版本，少一项就是静默错误。"]),
                ("换参数就重算", ["换模型或换倍率不会继续", "显示旧结果，而是重算缓存。"]),
            ],
            "compare": "对比原图",
            "compare_note": "按住即看原图，松手回到处理后的画面。",
            "footnote": "本层不改 PageSource 的形状：一页还是一张图，只是这张图的来源可以被替换。",
        },
        "sr": {
            "title": "四条超分路线",
            "desc": (
                "左侧是糊掉的网点与恢复后的网点对比；右侧列出四条超分路线及其适用平台矩阵，"
                "打勾表示这条路线在该平台上真的能跑。"
            ),
            "before": "原始网点",
            "before_sub": "压缩糊块",
            "after": "超分之后",
            "after_sub": "网点分开",
            "routes_label": "ROUTES",
            "routes": [
                ("Rossi 原生 CoreML", "ANE / GPU", "iOS · macOS"),
                ("mImage ONNX", "DirectML · CoreML EP · CPU", "iOS · Windows · macOS · Linux"),
                ("桌面 NCNN", "waifu2x · Real-CUGAN", "Windows · Linux"),
                ("内置 waifu2x CLI", "无引擎可选，自动", "Android"),
            ],
            "matrix_label": "PLATFORM MATRIX",
            "platforms": ["Android", "iOS", "Windows", "macOS", "Linux"],
            "matrix": [
                ("Rossi 原生 CoreML", [False, True, False, True, False]),
                ("mImage ONNX", [False, True, True, True, True]),
                ("桌面 NCNN", [False, False, True, False, True]),
                ("内置 waifu2x CLI", [True, False, False, False, False]),
            ],
            "footnote": "只在低于设定分辨率时才跑，前后各预取若干页；权重不随包，首次使用时下载。",
        },
        "ocr": {
            "title": "漫画翻译：产出一张能直接看的成品页",
            "desc": (
                "六步流水线：检测文字框、识别台词、擦掉原文、翻译、回填排版、成品页；"
                "下方是三档译文引擎与桌面端限制说明。"
            ),
            "steps": [
                ("01", "检测", "PP-OCRv4 det"),
                ("02", "识别", "manga-ocr"),
                ("03", "擦字", "LaMa"),
                ("04", "翻译", "三档可选"),
                ("05", "回填", "霞鹜文楷"),
                ("06", "成品页", "按页切换"),
            ],
            "engines_label": "TRANSLATION ENGINES",
            "engines": [
                ("API 端点", "云端，或本机 Ollama / Foundry Local"),
                ("混元 Hy-MT2", "本机 llama-server"),
                ("Apple 系统翻译", "端侧离线免费，无术语表"),
            ],
            "limits": [
                "只有 Windows / Linux / macOS：移动端是刻意排除，不是待办。",
                "权重约 660 MB，首次使用时在设置页下载。",
                "端点不可用时降级为擦字 + 原文回填，不会卡住整本。",
            ],
            "footnote": "每一页的六道关都记一行日志，出问题在设置页里能直接看到是哪一步。",
        },
        "expressive": {
            "title": "同一套 Material 3 Expressive 语言",
            "desc": (
                "五格展示设计语言：非对称圆角、cookie 形图标座、弹簧驱动的数值、"
                "容器色分层而非描边投影、胶囊状态；覆盖工作台、设置页、阅读轮盘与提示条。"
            ),
            "tiles": [
                ("非对称圆角", "22 / 22 / 6 / 22", "squircle"),
                ("cookie 图标座", "图标落在凹边里", "cookie"),
                ("弹簧数值", "空间弹簧，不写死时长", "spring"),
                ("容器分层", "不描边、不投影", "layers"),
                ("胶囊状态", "一颗点 + 一个词", "pill"),
            ],
            "pill_sample": "就绪",
            "footnote": "墨水屏与「减少动态效果」下弹簧直接落位；量不到的数画 —— ，不回落成 0。",
        },
        "data": {
            "title": "数据怎么进出这台机器",
            "desc": (
                "三列：下载队列（优先级、失败重试、边下边读、导出）、云同步（块级 LWW、WebDAV / S3）、"
                "本地备份；底部是导出格式与存储统计。"
            ),
            "columns": [
                (
                    "下载队列",
                    [
                        "优先级与批量操作",
                        "失败增量重试",
                        "边下边读",
                        "章节闸门与存储统计",
                        "导出 ZIP / 相册 / 文件夹",
                    ],
                    "自研队列，不走系统下载器",
                ),
                (
                    "云同步",
                    [
                        "块级 LWW",
                        "WebDAV（含 path-style）",
                        "S3 / 兼容对象存储",
                        "只同步偏好，不同步本机事实",
                        "手动触发上传下载",
                    ],
                    "workspace 块直接读磁盘布局",
                ),
                (
                    "本地备份",
                    [
                        "备份编解码与控件",
                        "整库导入导出",
                        "换机迁移",
                        "绑定包单独导出",
                        "缓存可单独清理",
                    ],
                    "导出文件不随卸载被清",
                ),
            ],
            "axis_label": "EXPORT",
            "axis": ["ZIP", "相册", "文件夹", "绑定包 JSON", "备份文件"],
            "footnote": "同步只搬「用户偏好」，不搬「这台机器的事实 / 这一秒的画面」。",
        },
    },
    "en": {
        "hero": {
            "title": "Rossi — a cross-platform manga reader",
            "desc": (
                "A washi-paper card: on the left the Rossi wordmark, a bilingual one-line pitch and the "
                "Material 3 Expressive / workspace credits; on the right the wine-red cat mask from the app "
                "icon resting on a shelf line, its hollow eye panels revealing manga gutters behind it."
            ),
            "eyebrow": "FLUTTER + RUST · MATERIAL 3 EXPRESSIVE",
            "line1": "Any third-party comic source, one shared bookshelf.",
            "line2": "把任意第三方图源，装进同一个书架。",
            "keywords": "Source plugins · Workspace lanes · Local & cloud favourites · Upscaling · Page translation · Video pages",
            "platforms": "Android · iOS · Windows · macOS · Linux",
        },
        "arch": {
            "title": "How it runs",
            "desc": (
                "Four stacked layers: the plugin layer (built-in Bika and JM plus your own JS) feeds the Rust-side "
                "windcore — QuickJS sandbox, reqwest, decoding, archives, video — which reaches the Flutter UI "
                "through flutter_rust_bridge: workspace, discovery, reader, bookshelf, settings."
            ),
            "plugin_label": "PLUGINS · JS",
            "plugins": ["Bika built in", "JM built in", "Your own .js / .cjs / .br"],
            "plugin_note": "bundled at compile time",
            "rust_label": "RUST · windcore",
            "rust_tiles": [
                ("QuickJS sandbox", "requests and files only"),
                ("reqwest", "network granted by host"),
                ("Decode · de-obfuscate", "downscale at the exit"),
                ("Archives local_core", "CBZ / CBR / 7z"),
                ("Present gpu_present", "shared GPU texture"),
            ],
            "bridge": "flutter_rust_bridge — data crosses, permissions do not",
            "ui_label": "FLUTTER",
            "ui_items": ["Workspace lanes", "Discover · search", "Reader", "Shelf · downloads", "Settings · sync"],
            "footnote": "Plugin code never runs in Dart and never touches platform APIs; the host grants capabilities per feature.",
        },
        "workbench": {
            "title": "Workspace: lanes → panels → cards",
            "desc": (
                "Three columns: the left lane holds shelf, favourites, history, downloads and insight cards; the "
                "centre is the reader lane, which can take the whole usable width; the right lane holds discovery, "
                "file manager, page list, plugins, control and info panels. Notes explain lane input targeting."
            ),
            "lane_left": "Shelf",
            "lane_left_tabs": ["Saved", "History", "Downloads"],
            "cards": [
                ("Favourites", "local · cloud · groups"),
                ("History", "recently read"),
                ("Downloads", "queue · storage stats"),
            ],
            "insight_label": "INSIGHTS · LAST 7 DAYS",
            "insight_note": "streak · heatmap · source split",
            "lane_center": "Reader",
            "page_hint_1": "left: current page",
            "page_hint_2": "right: prefetched next",
            "page_hint_3": "shared GPU texture",
            "toolbar_note": "mode · trim · upscale · translate",
            "lane_right": "Discover",
            "lane_right_tabs": ["Files", "Pages", "Plugins", "Control", "Info", "Tools"],
            "right_cards": [
                ("File manager", "tabs · multi-select · trash"),
                ("Page list", "jump · search · panel control"),
                ("Sources", "plugin status cards"),
            ],
            "notes": [
                "Lanes collapse and reorder; the centre one can take the whole usable width.",
                "Whichever lane the pointer is in owns the keys — input belongs to it immediately.",
                "Every card picks its own size class, so narrow and full-width slots both fit.",
            ],
        },
        "binding": {
            "title": "Operation bindings: input → action",
            "desc": (
                "Seven input classes on the left map to contextual bindings in the middle, which point at stable "
                "action ids in the registry on the right. Three rules underneath: conflicts block saving, bundles "
                "export and import, lower contexts can be isolated."
            ),
            "col_input": "INPUT",
            "inputs": ["Keyboard", "Mouse", "Side buttons", "Wheel", "Gamepad", "Touch", "Region gestures"],
            "col_binding": "BINDING",
            "bindings": [
                ("Space · wheel↓", "Reader", "reader.next-page"),
                ("Arrows ←→", "Reader", "reader.page-turn"),
                ("Side X1", "Global", "shelf.open-selected"),
                ("Long press", "Reader", "reader.loupe"),
            ],
            "col_action": "ACTION",
            "actions": [
                ("reader.next-page", "next page"),
                ("reader.page-turn", "turn by direction"),
                ("reader.loupe", "page magnifier"),
                ("shelf.open-selected", "open selection"),
            ],
            "rules": [
                "Two bindings on one input in the same context block saving — not a warning.",
                "A bundle is JSON (format + format_version) for moving machines and sharing.",
                "Contexts have priority, and lower ones can be isolated under higher ones.",
            ],
            "footnote": "Actions must be declared in a registry (id + label + category + context), never as private controller methods.",
        },
        "reading": {
            "title": "Six ways to read, one set of gestures",
            "desc": (
                "Six cells: right to left, left to right, webtoon top to bottom, seamless double page, split "
                "landscape pages, auto read. A bottom strip adds the magnifier, manual page order, slideshow, "
                "chapter read marks and the radial menu."
            ),
            "modes": [
                ("Right to left", "Japanese order, unmirrored", "rtl"),
                ("Left to right", "domestic and translated editions", "ltr"),
                ("Webtoon", "scroll down, tap to turn too", "scroll"),
                ("Double page", "halves joined, no gutter gap", "double"),
                ("Split landscape", "wide spreads split in two", "split"),
                ("Auto read", "interval and distance tunable", "auto"),
            ],
            "extras_label": "ALSO IN THE READER",
            "extras": ["Magnifier", "Manual page order", "Slideshow", "Chapter read marks", "Radial menu"],
            "footnote": "Each of these can apply to the current comic only; desktop bindings for keys, mouse, wheel, gamepad and touch are all editable.",
        },
        "display": {
            "title": "Non-destructive display pipeline",
            "desc": (
                "Seven stages left to right: decode, trim, denoise, colour adjust, upscale, translate, present. "
                "The bracket explains that every stage produces an invalidatable derivative and the source image "
                "stays the only truth."
            ),
            "stages": [
                ("Decode", "downscale at exit"),
                ("Trim", "auto white borders"),
                ("Denoise", "JPEG / AI"),
                ("Colour", "tone correction"),
                ("Upscale", "on demand · prefetch"),
                ("Translate", "finished page"),
                ("Present", "GPU texture"),
            ],
            "source_tag": "Decode",
            "stage_no": "%02d",
            "bracket": "none of these rewrite the file — each emits a derivative bitmap",
            "notes": [
                ("The source is the truth", ["A missing derivative silently", "falls back; pages never stall."]),
                ("Cache keys include everything", ["Language, model, scale, font,", "parameter version — all of it."]),
                ("Changing a parameter recomputes", ["A new model or scale recomputes", "instead of showing the old page."]),
            ],
            "compare": "Compare original",
            "compare_note": "Hold to see the source, release to return to the processed page.",
            "footnote": "PageSource keeps its shape: a page is still one image, only where that image comes from can be replaced.",
        },
        "sr": {
            "title": "Four super-resolution routes",
            "desc": (
                "On the left a smeared screentone patch next to clean dots; on the right the four routes with a "
                "platform matrix where a tick means the route really runs on that platform."
            ),
            "before": "Screentone",
            "before_sub": "smeared by compression",
            "after": "Upscaled",
            "after_sub": "dots separated",
            "routes_label": "ROUTES",
            "routes": [
                ("Rossi native CoreML", "ANE / GPU", "iOS · macOS"),
                ("mImage ONNX", "DirectML · CoreML EP · CPU", "iOS · Windows · macOS · Linux"),
                ("Desktop NCNN", "waifu2x · Real-CUGAN", "Windows · Linux"),
                ("Bundled waifu2x CLI", "no engine choice", "Android"),
            ],
            "matrix_label": "PLATFORM MATRIX",
            "platforms": ["Android", "iOS", "Windows", "macOS", "Linux"],
            "matrix": [
                ("Rossi native CoreML", [False, True, False, True, False]),
                ("mImage ONNX", [False, True, True, True, True]),
                ("Desktop NCNN", [False, False, True, False, True]),
                ("Bundled waifu2x CLI", [True, False, False, False, False]),
            ],
            "footnote": "Only runs below the resolution you set, prefetching pages on both sides; weights download on first use.",
        },
        "ocr": {
            "title": "Manga translation: a finished page you can read",
            "desc": (
                "Six stages: detect boxes, recognise text, erase it, translate, re-typeset, finished page; below "
                "that the three translation engines and the desktop-only limits."
            ),
            "steps": [
                ("01", "Detect", "PP-OCRv4 det"),
                ("02", "Recognise", "manga-ocr"),
                ("03", "Erase", "LaMa"),
                ("04", "Translate", "three engines"),
                ("05", "Typeset", "LXGW WenKai"),
                ("06", "Finished", "toggle per page"),
            ],
            "engines_label": "TRANSLATION ENGINES",
            "engines": [
                ("API endpoint", "cloud, or local Ollama / Foundry Local"),
                ("Hunyuan Hy-MT2", "local llama-server"),
                ("Apple translation", "on-device, offline, no glossary"),
            ],
            "limits": [
                "Windows / Linux / macOS only: mobile is excluded on purpose, not pending.",
                "About 660 MB of weights, downloaded from settings on first use.",
                "An unreachable endpoint degrades to erase + source text instead of stalling.",
            ],
            "footnote": "All six stages write one log line per page, so the settings page can tell you which one failed.",
        },
        "expressive": {
            "title": "One Material 3 Expressive language",
            "desc": (
                "Five tiles showing the design language: asymmetric radii, cookie-shaped icon seats, spring-driven "
                "numbers, container layering instead of borders, and pill status; used across workspace, settings, "
                "the radial menu and toasts."
            ),
            "tiles": [
                ("Asymmetric radii", "22 / 22 / 6 / 22", "squircle"),
                ("Cookie icon seat", "icon sits in a notch", "cookie"),
                ("Spring values", "spatial spring, no fixed ms", "spring"),
                ("Container layering", "no borders, no shadows", "layers"),
                ("Status pills", "one dot, one word", "pill"),
            ],
            "pill_sample": "ready",
            "footnote": "Springs land instantly on e-ink and with reduced motion; unmeasured numbers render as — , never 0.",
        },
        "data": {
            "title": "How data moves on and off the machine",
            "desc": (
                "Three columns: the download queue (priority, retry, read-while-downloading, export), cloud sync "
                "(block-level LWW, WebDAV / S3) and local backup; export formats and storage stats below."
            ),
            "columns": [
                (
                    "Download queue",
                    [
                        "Priority and batch actions",
                        "Incremental retry",
                        "Read while downloading",
                        "Chapter gate and storage stats",
                        "Export ZIP / gallery / folder",
                    ],
                    "our own queue, not the system downloader",
                ),
                (
                    "Cloud sync",
                    [
                        "Block-level LWW",
                        "WebDAV (path-style toggle)",
                        "S3 and compatible stores",
                        "Preferences only, not machine facts",
                        "Manual upload and download",
                    ],
                    "the workspace block reads the on-disk layout",
                ),
                (
                    "Local backup",
                    [
                        "Backup codec and controls",
                        "Whole-library import and export",
                        "Move to a new machine",
                        "Binding bundles exported separately",
                        "Caches cleared on their own",
                    ],
                    "exported files survive an uninstall",
                ),
            ],
            "axis_label": "EXPORT",
            "axis": ["ZIP", "Gallery", "Folder", "Binding JSON", "Backup file"],
            "footnote": "Sync moves user preferences, never this machine's facts or this second's screen.",
        },
    },
}


DIAGRAMS = {
    "hero": hero,
    "plugin-architecture": plugin_architecture,
    "workbench": workbench,
    "operation-binding": operation_binding,
    "reading-experience": reading_experience,
    "display-pipeline": display_pipeline,
    "super-resolution": super_resolution,
    "ocr-translate": ocr_translate,
    "expressive-design": expressive,
    "data-flow": data_flow,
}


def main(argv: list[str]) -> int:
    check = "--check" in argv
    OUT.mkdir(parents=True, exist_ok=True)
    written = 0
    for lang, suffix in (("zh", ""), ("en", ".en")):
        for name, fn in DIAGRAMS.items():
            path = OUT / f"{name}{suffix}.svg"
            data = fn(lang)
            if check:
                if not path.exists() or path.read_text(encoding="utf-8") != data:
                    print(f"[stale] {path.relative_to(ROOT)}", file=sys.stderr)
                    return 1
                continue
            path.write_text(data, encoding="utf-8")
            written += 1
    if check:
        print("readme svgs: up to date")
    else:
        print(f"readme svgs: wrote {written} files into {OUT.relative_to(ROOT)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
