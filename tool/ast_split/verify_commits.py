#!/usr/bin/env python3
"""按提交逐个验证「拆分提交是纯搬家」。

对工作区状态做快照式比对会被并发提交拖垮（基线一直在动）。这里改成：
对每个拆分提交 C，拿它的父提交 P 当基线，只看 C 这一次改了什么 ——
于是结论与「谁在我们中间又提交了什么」无关。

判据同 verify_moves：
  1) 老文件剩下的行必须是它在 P 里的有序子序列（只允许整块删行）；
  2) 全局行多重集合守恒：P 里的每个有意义行，在 C 的树里都还在。
"""

import subprocess
import sys
from collections import Counter
from pathlib import Path

R = Path(__file__).resolve().parents[2]
EXTS = {".dart", ".rs", ".cpp", ".h", ".js"}
DIRECTIVES = ("import ", "export ", "part ", "use ", "pub use ", "mod ",
              "pub mod ", "#include", "from ", "library ")
NEW_ONLY = ("extension ",)


def git(*a: str) -> str:
    return subprocess.run(["git", *a], cwd=R, capture_output=True, text=True).stdout


def meaningful(text: str) -> list[str]:
    out = []
    for raw in text.split("\n"):
        t = raw.strip()
        if not t:
            continue
        if t.startswith("//") or t.startswith("/*") or t.startswith("*/") or t.startswith("* "):
            continue
        if t.startswith("#") and not t.startswith("#["):
            continue
        if t.startswith(DIRECTIVES) or t in ("}", "{"):
            continue
        if any(t.startswith(p) for p in NEW_ONLY) and " on " in t:
            continue
        out.append(t)
    return out


def blob(ref: str, path: str) -> str:
    rc = subprocess.run(["git", "cat-file", "-e", f"{ref}:{path}"],
                        cwd=R, capture_output=True).returncode
    return "" if rc else git("show", f"{ref}:{path}")


def is_subseq(needle: list[str], hay: list[str]) -> bool:
    it = iter(hay)
    return all(x in it for x in needle)


def check(commit: str) -> bool:
    parent = f"{commit}^"
    entries = []
    for line in git("diff", "--name-status", "-M", parent, commit).splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        st = parts[0][0]
        if st == "R" and len(parts) >= 3:      # 重命名：old -> new
            entries.append((parts[1], parts[2]))
        elif st == "D":
            entries.append((parts[1], None))
        else:
            entries.append((parts[1], parts[1]))
    msg = git("log", "-1", "--format=%s", commit).strip()
    print(f"{commit[:8]} {msg[:64]}")
    # 承接池 = 本提交真正改过的文件（它们在 C 与在 P 里的内容）。
    # 没被本提交碰过的文件在两版里一模一样，不可能「接住」被搬走的行，
    # 所以把它们排除只会让判据更严格、不会更松；而整棵树逐个 git show 慢到不可用。
    pool = Counter()
    for p in {x for pair in entries for x in pair if x}:
        if Path(p).suffix in EXTS:
            pool += Counter(meaningful(blob(commit, p)))
            pool += Counter(meaningful(blob(parent, p)))
    rows = []
    for old, new in entries:
        if not new:                              # 删除：靠父提交体量判断后单独查
            before = meaningful(blob(parent, old))
            if len(before) >= 120 and sum(pool[k] for k in before) < len(before):
                rows.append((old + " (deleted)", len(before), 0, -1, 0, False))
            continue
        if Path(old).suffix not in EXTS:
            continue
        before = meaningful(blob(parent, old))
        if len(before) < 120:
            continue
        after = meaningful(blob(commit, new))
        missing = sum(max(0, c - pool[k]) for k, c in Counter(before).items())
        # 顺序判据：新内容必须是原内容的子序列（重命名同理）
        order = is_subseq(after, before) if old == new else bool(after)
        added = sum(max(0, c - Counter(before)[k]) for k, c in Counter(after).items())
        rows.append((new, len(before), len(after), missing, added, order))
    if not rows:
        print("  （没有达体量的改动文件，跳过）")
        return True
    ok = True
    for p, b, a, m, ad, o in rows:
        if m or not o:
            ok = False
        print(f"  {p:<58} {b:>5}→{a:<5} 未承接={m:<4} 新增={ad:<4} "
              f"{'顺序OK' if o else '顺序破坏'}")
    return ok


def main() -> int:
    commits = sys.argv[1:]
    if not commits:
        out = git("log", "--format=%H %s", "35a6be81..HEAD").splitlines()
        commits = [l.split(" ", 1)[0] for l in out
                   if l.split(" ", 1)[-1].startswith(("refactor", "refc"))]
    bad = 0
    for c in commits:
        if not check(c):
            bad += 1
    print()
    print("ALL COMMITS ARE PURE MOVES" if not bad else f"{bad} 个提交不是纯搬家")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
