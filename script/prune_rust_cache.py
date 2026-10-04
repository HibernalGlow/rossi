#!/usr/bin/env python3
"""回收 cargo 的 incremental 死账（默认只报告，不加 --apply 不删任何东西）。

为什么需要它：rustc 每换一个 unit 元数据（feature/profile/rustflags/包版本/环境）
就会新开一个 `<crate>-<hash>` incremental 目录，而**旧目录永远不会被回收** —— cargo
只在自己的 fingerprint 里记当前那一份。本仓实测：`rust/target/debug/incremental`
里 18 个 crate 攒了 258 个目录、15.1 GB，绝大多数是再也读不到的旧 session。

判据：`--older-than-days` 内没被写过的 session 目录一律视为可回收。incremental 目录
只在该 unit 重新编译时才会被读写，所以「很久没动」＝「很久没重编」。删错的后果是
那一个 crate 下次非增量重编一次，**不影响构建正确性**，也不会碰 `deps/`：
`deps/` 里的产物构建后只读不写，mtime 完全不说明它还有没有在被复用，按时间删它是假尺
（本仓实测：按 fingerprint 在册关系判，`debug/deps` 的无主产物是 0 个，全是热缓存）。

用法::

    python3 script/prune_rust_cache.py                  # 看要删什么
    python3 script/prune_rust_cache.py --apply          # 真删
    python3 script/prune_rust_cache.py --older-than-days 14 --apply
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# hook 的稳定目录（见 hook/cargo_target_dir.dart）也在 rust/target 下面，一起扫。
TARGET_ROOTS = [
    os.path.join(REPO_ROOT, "rust", "target"),
    os.path.join(REPO_ROOT, "rust", "gpu_present", "target"),
]
PROFILE_NAMES = ("debug", "release")
# 这些子目录里没有 profile 结构，进去只是白扫上万个文件
PRUNE_DESCENT = frozenset(
    {"deps", "build", "incremental", "examples", ".fingerprint", "tmp", "doc"}
)
GB = 1024**3


def profile_dirs(root: str) -> list[str]:
    """root 下所有 cargo profile 目录，含 `<triple>/debug` 和 hook 的深层树。"""
    found: list[str] = []
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except OSError:
            continue
        for entry in entries:
            if not entry.is_dir(follow_symlinks=False):
                continue
            name = entry.name
            if name in PROFILE_NAMES:
                found.append(entry.path)
            if name in PRUNE_DESCENT or name.startswith("."):
                continue
            stack.append(entry.path)
    return sorted(found)


def tree_size(path: str) -> int:
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for name in filenames:
            try:
                total += os.stat(os.path.join(dirpath, name)).st_size
            except OSError:
                pass
    return total


def dead_sessions(profile: str, cutoff: float) -> list[tuple[str, int]]:
    incremental = os.path.join(profile, "incremental")
    if not os.path.isdir(incremental):
        return []
    dead: list[tuple[str, int]] = []
    for entry in os.scandir(incremental):
        if not entry.is_dir():
            continue
        if entry.stat().st_mtime >= cutoff:
            continue
        dead.append((entry.path, tree_size(entry.path)))
    return dead


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="真正删除（默认只报告）")
    parser.add_argument(
        "--older-than-days",
        type=float,
        default=7.0,
        help="超过这个天数没被写过的 session 目录视为可回收（默认 7）",
    )
    args = parser.parse_args()

    cutoff = time.time() - args.older_than_days * 86400
    profiles = 0
    reclaimed = 0
    deleted = 0
    for root in TARGET_ROOTS:
        if not os.path.isdir(root):
            continue
        for profile in profile_dirs(root):
            profiles += 1
            for path, size in dead_sessions(profile, cutoff):
                if args.apply:
                    shutil.rmtree(path, ignore_errors=True)
                reclaimed += size
                deleted += 1
                print(
                    f"  {'已删' if args.apply else '可删'} "
                    f"{os.path.relpath(path, REPO_ROOT)}  ({size / GB:.2f} GB)"
                )

    print(
        f"\n扫了 {profiles} 个 profile 目录；"
        f"{'已回收' if args.apply else '可回收'} {deleted} 个旧 session，"
        f"共 {reclaimed / GB:.2f} GB"
        + ("" if args.apply else "（dry-run，未删除任何东西）")
    )
    if not args.apply and deleted:
        print("加 --apply 才动手。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
