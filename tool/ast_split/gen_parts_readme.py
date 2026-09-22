#!/usr/bin/env python3
"""为 parts/ 目录生成索引 README.md（项目惯例：每个 parts 目录配一份维护笔记）。

不手写：手写会在下一次搬家后失真。这里直接从代码里取
「文件 → 它注册的宿主 + 顶层声明 + 每个声明的首行文档注释」。

用法：
    python3 tool/ast_split/gen_parts_readme.py                 # 只补缺失的
    python3 tool/ast_split/gen_parts_readme.py --force         # 全部重生成
    python3 tool/ast_split/gen_parts_readme.py lib/parts ...   # 指定目录
"""

import argparse
import pathlib
import re
import sys

R = pathlib.Path(__file__).resolve().parents[2]
DECL = re.compile(
    r"^(?:abstract\s+|final\s+|base\s+|interface\s+|sealed\s+)*"
    r"(class|mixin|enum|extension)\s+([A-Za-z_]\w*)"
    r"|^(?:const\s+|late\s+)?(?:[A-Za-z_][\w<>,?\s]*?\s+)?([A-Za-z_]\w*)\s*\("
    r"|^(?:const\s+|final\s+|late\s+)?[A-Za-z_][\w<>,?]*\s+([A-Za-z_]\w*)\s*=",
    re.M,
)
PARTOF = re.compile(r"^part of\s+'([^']+)'", re.M)
LIBDIR_NOTE = (
    "<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->"
)


def first_doc(text: str, at: int) -> str:
    """取声明上方最后一组 /// 注释的首行。"""
    head = text[:at].rstrip("\n").split("\n")
    for i in range(len(head) - 1, max(-1, len(head) - 26), -1):
        t = head[i].strip()
        if t.startswith("///"):
            s = t.lstrip("/").strip()
            if s:
                return s
        if t and not t.startswith("//"):
            break
    return ""


def describe(path: pathlib.Path) -> tuple[str, list[tuple[str, str, str]]]:
    text = path.read_text(encoding="utf-8")
    host = ""
    m = PARTOF.search(text)
    if m:
        host = f"part of `{m.group(1)}`"
    items: list[tuple[str, str, str]] = []
    seen = set()
    for m in DECL.finditer(text):
        kind, names = m.group(1), m.groups()[1:]
        n = next((x for x in names if x), None)
        if not n or n in seen or n in {"if", "for", "while", "switch", "return",
                                      "catch", "throw", "await", "yield"}:
            continue
        seen.add(n)
        items.append((n, kind or "顶层符号", first_doc(text, m.start())))
    return host, items


def render(d: pathlib.Path) -> str:
    files = sorted(p for p in d.glob("*.dart"))
    lines = [f"# {d.name} 目录索引", ""]
    owner = files[0] if files else None
    host = ""
    if owner:
        host, _ = describe(owner)
    if host:
        lines += [f"本目录的 part 全部属于同一个库（{host}）。", ""]
    lines += ["| 文件 | 行数 | 内容 |", "|---|---|---|"]
    for p in files:
        _, items = describe(p)
        n = len(p.read_text(encoding="utf-8").split("\n"))
        names = "、".join(f"`{x[0]}`" for x in items[:6])
        more = f" 等 {len(items)} 项" if len(items) > 6 else ""
        lines.append(f"| `{p.name}` | {n} | {names}{more or '—'} |")
    lines += ["", "## 各文件管什么", ""]
    for p in files:
        _, items = describe(p)
        if not items:
            continue
        lines.append(f"- `{p.name}`")
        for name, kind, doc in items[:12]:
            tail = f" — {doc}" if doc else f" *({kind})*"
            lines.append(f"  - `{name}`{tail}")
        if len(items) > 12:
            lines.append(f"  - …另有 {len(items) - 12} 项，见文件")
    lines += [
        "",
        "## 搬家约定",
        "",
        "- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`",
        "  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。",
        "- 上游已有的文件只允许搬本仓自己的行，判据是",
        "  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。",
        "- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝",
        "  上游已存在的同名成员。",
        "",
        LIBDIR_NOTE,
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="*")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    targets = (
        [R / d for d in a.dirs]
        if a.dirs
        else sorted(
            {p.parent
             for pat in ("lib/**/parts/*.dart", "test/**/parts/*.dart")
             for p in R.glob(pat)}
        )
    )
    made = 0
    for d in targets:
        readme = d / "README.md"
        if readme.exists() and not a.force:
            continue
        readme.write_text(render(d), encoding="utf-8")
        made += 1
        print(f"  写入 {readme.relative_to(R)}")
    print(f"共生成 {made} 份索引")
    return 0


if __name__ == "__main__":
    sys.exit(main())
