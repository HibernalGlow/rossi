#!/usr/bin/env python3
"""独立验收：证明「拆分只搬家、没改内容」。

不依赖 agent 自己跑的审计，直接从 git HEAD 取原始文本，与工作区里
「该文件本身 + 本次新增的兄弟文件」的文本做比对：

1. 顺序守恒：现在这个文件里的每一行，必须按原有相对顺序出现（只允许删行）。
2. 内容守恒：原文的每一个「有意义行」都必须在工作区里还在（多重集合意义下）。
   搬出去的块允许换个文件待着，但一行都不许蒸发或被改写。

有意义行 = 去掉空行、纯注释行、以及 import/export/part/use/mod 等指令行。
"""

import subprocess
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
REF = __import__("os").environ.get("VERIFY_REF", "HEAD")  # 可钉住开工时的提交
EXTS = {".dart", ".rs", ".cpp", ".h", ".js"}
DIRECTIVE_PREFIXES = (
    "import ", "export ", "part ", "use ", "pub use ", "mod ", "pub mod ",
    "include ", "#include", "library ", "from ", "apply ",
)


def meaningful(text: str) -> list[str]:
    out = []
    for raw in text.split("\n"):
        l = raw.strip()
        if not l:
            continue
        if l.startswith("//") or l.startswith("/*") or l.startswith("*/"):
            continue
        if l.startswith("*") and not l.startswith("*="):
            continue
        if l.startswith("#") and not l.startswith("#["):
            continue
        if l.startswith(DIRECTIVE_PREFIXES):
            continue
        out.append(l)
    return out


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=False
    ).stdout


def untracked_and_new() -> list[Path]:
    """未跟踪项可能是**目录**（例如新建的 parts/），必须展开。"""
    out: list[Path] = []
    for line in git("status", "--porcelain").splitlines():
        if not line.startswith("??"):
            continue
        p = REPO / line[2:].strip()
        if p.is_dir():
            out += [f for f in p.rglob("*") if f.is_file() and f.suffix in EXTS]
        elif p.is_file() and p.suffix in EXTS:
            out.append(p)
    # 开工后新增、但已被用户并发提交进 HEAD 的文件也算「本次搬出去的承接方」
    for line in git("diff", "--name-only", f"{REF}..HEAD").splitlines():
        p = REPO / line
        if p.is_file() and p.suffix in EXTS and git("log", "--oneline", f"{REF}..HEAD", "--", line).strip():
            if p not in out:
                out.append(p)
    return out


def is_subsequence(needle: list[str], hay: list[str]) -> bool:
    it = iter(hay)
    return all(x in it for x in needle)


def resolve_current(path: Path) -> Path | None:
    """HEAD 里的路径现在可能变成 <stem>/mod.rs。"""
    if path.exists():
        return path
    alt = path.with_suffix("") / "mod.rs"
    if alt.exists():
        return alt
    alt2 = path.with_suffix("") / (path.name + ".rs")
    return alt2 if alt2.exists() else None


def main() -> int:
    args = sys.argv[1:]
    targets = [Path(a) for a in args] if args else []
    if not targets:
        # 缺省：本次工作区里所有被修改的、HEAD 时就 >400 行的源文件
        targets = []
        for line in git("status", "--porcelain").splitlines():
            tag, path = line[:2], line[3:].strip()
            if tag.startswith("??"):
                continue
            p = REPO / path
            if p.suffix not in EXTS:
                continue
            old = git("show", f"{REF}:{path}")
            if old and len(meaningful(old)) > 400:
                targets.append(p)

    news = untracked_and_new()
    print(f"待验收 {len(targets)} 个文件；工作区新增源文件 {len(news)} 个\n")
    header = (
        f"{'文件':<58}{'原文':>6}{'现存':>6}{'搬出':>6}"
        f"{'丢失':>6}{'改写':>6}  顺序"
    )
    print(header)
    print("-" * len(header))
    failures = 0
    for t in targets:
        rel = t.relative_to(REPO) if t.is_absolute() else t
        old_lines = meaningful(git("show", f"{REF}:{rel}"))
        cur = resolve_current(REPO / rel)
        if cur is None:
            print(f"{str(rel):<58} 整个文件已被删除/改名，需人工确认")
            failures += 1
            continue
        cur_lines = meaningful(cur.read_text(encoding="utf-8"))

        # 该文件的同伴新文件：与它同目录（含子目录）且同语言后缀
        stem = rel.suffix
        parent = (REPO / rel).parent
        # 只有「行确实取自本文件原文」的新文件才算承接方，否则同目录下
        # 别人新建的文件会让多重集合虚胖、把丢失行掩盖掉。
        companions = []
        for n in news:
            if n.suffix != stem or n == cur or parent not in n.parents:
                continue
            if str(n.relative_to(REPO)) == str(rel):
                continue
            nl = [
                l for l in meaningful(n.read_text(encoding="utf-8"))
                if not l.startswith("extension ") and l != "}"
            ]
            if nl and is_subsequence(nl, old_lines):
                companions.append(n)
        comp_lines: list[str] = []
        for n in companions:
            comp_lines += meaningful(n.read_text(encoding="utf-8"))

        pool = Counter(cur_lines) + Counter(comp_lines)
        missing = sum(
            max(0, c - pool[k]) for k, c in Counter(old_lines).items()
        )
        # 「改写」= 原行没丢，但现存文件里出现了原文没有的行
        old_pool = Counter(old_lines)
        invented = sum(
            max(0, c - old_pool[k]) for k, c in Counter(cur_lines).items()
        )
        order_ok = is_subsequence(cur_lines, old_lines)
        moved_out = len(old_lines) - len(cur_lines)
        if missing or not order_ok or invented:
            failures += 1
        print(
            f"{str(rel):<58}{len(old_lines):>6}{len(cur_lines):>6}"
            f"{moved_out:>6}{missing:>6}{invented:>6}"
            f"  {'OK' if order_ok else '破坏'}"
            f"   (+{len(companions)} 个新文件承接 {len(comp_lines)} 行)"
        )
    print()
    if failures:
        print(f"VERIFY FAIL：{failures} 个文件存在问题")
        return 1
    print("VERIFY PASS：所有原始行都按序或整体搬移，无一丢失或改写")
    return 0


if __name__ == "__main__":
    sys.exit(main())
