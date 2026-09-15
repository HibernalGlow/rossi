#!/usr/bin/env python
# Phase 0 vendor spike 第 1 项：Rossi 的「薄适配层」到底能有多薄？
#
# ADR-0005 把「薄」当设计目标而不是事实，并要求先量一次。这里量三件事：
#   1. mImageViewer 主 crate `src/` 里，有多少模块碰了 egui；
#   2. 碰 egui 的模块是不是都能被名字识别出来（`ui_*` / `app*`）——即「核心 vs UI」边界是否真的存在；
#   3. 从 Rossi v0.1 真正要复用的那批模块（归档 / 解码 / 缓存 / 尺寸 / 缩放）出发，
#      按 `crate::` 引用做传递闭包，看这个闭包里有多少模块沾了 egui。
#
# 用法：
#   C:/Users/30902/.workbuddy/binaries/python/versions/3.13.12/python.exe \
#       poc/mimageviewer-adapter-thickness/measure.py [vendor/mimageviewer]

import re
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else "vendor/mimageviewer")
SRC = REPO / "src"

EGUI_PAT = re.compile(r"\begui\b")


def module_files(root: Path):
    """返回 {模块路径: 文件} ，模块路径形如 foo / ai::model_manager。"""
    out = {}
    for p in sorted(root.rglob("*.rs")):
        rel = p.relative_to(root)
        parts = list(rel.parts)
        if parts[-1] in ("mod.rs", "lib.rs", "main.rs"):
            parts = parts[:-1]
        else:
            parts[-1] = parts[-1][:-3]
        if parts:
            out["::".join(parts)] = p
    return out


def egui_hits(text: str):
    """区分「真的用 egui 类型」和「只是注释/文档里提到」——两者代价完全不同。"""
    real, comment = 0, 0
    for line in text.splitlines():
        if not EGUI_PAT.search(line):
            continue
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///") or stripped.startswith("//!"):
            comment += 1
        else:
            real += 1
    return real, comment


def crate_refs(text: str):
    """粗提 `crate::a::b` 形式的引用，返回可能的模块路径候选。"""
    refs = set()
    for m in re.finditer(r"\bcrate::([a-z_][a-z_0-9]*(?:::[a-z_][a-z_0-9]*)?)", text):
        refs.add(m.group(1))
    return refs


def classify(name: str) -> str:
    head = name.split("::")[0]
    if head.startswith("ui_") or head == "ui" or head.startswith("app"):
        return "UI（名字就能认出来）"
    return "非 UI 命名"


def main():
    mods = module_files(SRC)
    texts = {name: p.read_text(encoding="utf-8", errors="replace") for name, p in mods.items()}

    print("=" * 78)
    print(f"目标仓库: {REPO}")
    print(f"主 crate src/ 下 .rs 文件: {len(mods)}")
    print("=" * 78)

    # ---- 1. 谁碰了 egui ----
    real_hits, comment_only = {}, {}
    for name, text in texts.items():
        real, comment = egui_hits(text)
        if real:
            real_hits[name] = real
        elif comment:
            comment_only[name] = comment

    print(f"\n[1] 真正引用 egui（非注释）的模块: {len(real_hits)} / {len(mods)}")
    print(f"    只在注释里提到 egui 的模块: {len(comment_only)}")
    for name in sorted(real_hits):
        print(f"      - {name}  ({classify(name)})")

    # ---- 2. 「核心 vs UI」边界是否能用名字识别 ----
    ui = [n for n in real_hits if classify(n) != "非 UI 命名"]
    core = [n for n in real_hits if classify(n) == "非 UI 命名"]
    print(f"\n[2] 碰 egui 的模块里：")
    print(f"    名字像 UI 的: {len(ui)}")
    print(f"    **名字不像 UI 但依然碰 egui 的: {len(core)}**  <- 这些就是「边界不存在」的证据")
    for name in sorted(core):
        print(f"      ! {name}  ({real_hits[name]} 行)")

    # ---- 3. 从 v0.1 要复用的模块出发求闭包 ----
    seeds = [
        "archive_cache", "rar_loader", "zip_loader", "zip_tree", "wic_decoder",
        "thumb_loader", "page_dims", "fast_resize", "canonical_image_loader",
        "page_split", "path_key",
    ]
    seeds = [s for s in seeds if s in mods]
    closure, queue = set(seeds), list(seeds)
    while queue:
        cur = queue.pop()
        text = texts.get(cur, "")
        for ref in crate_refs(text):
            for cand in (ref, ref.split("::")[0]):
                if cand in mods and cand not in closure:
                    closure.add(cand)
                    queue.append(cand)

    print(f"\n[3] 复用种子模块: {len(seeds)} 个 -> {seeds}")
    print(f"    `crate::` 传递闭包: {len(closure)} 个模块")
    dirty = sorted(n for n in closure if n in real_hits)
    print(f"    闭包里碰 egui 的: {len(dirty)}")
    for name in dirty:
        print(f"      ! {name}  ({real_hits[name]} 行)")
    if not dirty:
        print("      （干净：种子及其依赖都不碰 egui，适配层可以只搬运这批文件）")

    # ---- 4. 工作区里其他 crate 的情况 ----
    crates_dir = REPO / "crates"
    if crates_dir.is_dir():
        print(f"\n[4] 工作区 crates/ 下各 crate 的 egui 情况:")
        for c in sorted(p for p in crates_dir.iterdir() if p.is_dir()):
            rs = list(c.rglob("*.rs"))
            hit = sum(1 for f in rs if EGUI_PAT.search(f.read_text(encoding="utf-8", errors="replace")))
            print(f"      {c.name:24} {len(rs):4} 个 .rs，{hit:4} 个提到 egui")

    print("\n" + "=" * 78)
    print("口径说明：`use crate::` 闭包是**粗估**——它按模块名匹配，不走语法分析；")
    print("跨 crate 的引用（`crate::` 之外）与 `super::` 未纳入。数字用来看量级，不当精确值。")
    print("=" * 78)


if __name__ == "__main__":
    main()
