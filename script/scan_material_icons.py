#!/usr/bin/env python3
"""扫描 lib/ 内残留的 Material Icons 用法，产出替换盘点报告。

用法:
    python3 script/scan_material_icons.py [--out PATH]

输出:
    - 按图标名聚合（出现次数、涉及文件数）
    - 按文件聚合（次数）
    - 全部逐条明细（文件:行号 + 行内容）
"""
from __future__ import annotations

import argparse
import collections
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCAN_ROOT = REPO / "lib"

# Icons.xxx / Icons.xxx_xxx（含尖括号泛型场景不受影响；排除 Icons. 前缀误匹配如 SomeIcons.）
ICON_RE = re.compile(r"(?<![A-Za-z0-9_])Icons\.([A-Za-z0-9_]+)")
# 引用图标本体但不含 "Icons." 字面量的形态：以 IconData 别名承接后再传给 Icon()
# 这里只统计字面量用法；别名间接引用由 dart analyze 层面另行覆盖。

SKIP_DIRS = {".dart_tool", "build", ".git", "generated"}


def scan() -> list[tuple[Path, int, str, str]]:
    hits: list[tuple[Path, int, str, str]] = []
    for path in SCAN_ROOT.rglob("*.dart"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for m in ICON_RE.finditer(line):
                hits.append((path, lineno, m.group(1), line.strip()))
    return hits


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=None, help="报告输出路径（默认打印到 stdout）")
    args = parser.parse_args()

    hits = scan()

    by_name: dict[str, list] = collections.defaultdict(list)
    by_file: dict[str, list] = collections.defaultdict(list)
    for path, lineno, name, line in hits:
        rel = path.relative_to(REPO).as_posix()
        by_name[name].append((rel, lineno, line))
        by_file[rel].append((name, lineno, line))

    lines: list[str] = []
    lines.append("# Material Icons 残留盘点（lib/）\n")
    lines.append(f"- 用法总数：**{len(hits)}**")
    lines.append(f"- 去重图标名：**{len(by_name)}** 个")
    lines.append(f"- 涉及文件：**{len(by_file)}** 个\n")

    lines.append("## 一、按图标名聚合（按次数降序）\n")
    lines.append("| 图标 | 次数 | 文件数 |")
    lines.append("| --- | ---: | ---: |")
    for name, occ in sorted(by_name.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        files = {o[0] for o in occ}
        lines.append(f"| `Icons.{name}` | {len(occ)} | {len(files)} |")
    lines.append("")

    lines.append("## 二、按文件聚合（按次数降序）\n")
    lines.append("| 文件 | 次数 | 涉及图标 |")
    lines.append("| --- | ---: | --- |")
    for rel, occ in sorted(by_file.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        names = sorted({o[0] for o in occ})
        lines.append(f"| `{rel}` | {len(occ)} | {', '.join('`' + n + '`' for n in names)} |")
    lines.append("")

    lines.append("## 三、逐条明细\n")
    cur_file = None
    for path, lineno, name, line in sorted(hits, key=lambda h: (h[0].as_posix(), h[1])):
        rel = path.relative_to(REPO).as_posix()
        if rel != cur_file:
            cur_file = rel
            lines.append(f"\n### {rel}\n")
        lines.append(f"- L{lineno} `Icons.{name}` — `{line}`")

    report = "\n".join(lines) + "\n"
    if args.out:
        args.out.write_text(report, encoding="utf-8")
        print(f"report written: {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
