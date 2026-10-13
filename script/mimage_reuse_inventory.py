"""Rust 复用台账与上游变更门禁；改写模块只报复核，不假装逐行等价。"""
from __future__ import annotations

import json
import re
from pathlib import Path

KINDS = {"direct_dependency", "direct_source", "source_port", "source_slice",
         "compatibility_rewrite", "independent", "adapter", "not_implemented", "generated"}


def check_inventory(repo: Path, ports: list[dict], head: str, git) -> bool:
    try:
        inventory = json.loads((repo / "docs/mimageviewer-reuse-inventory.json").read_text(encoding="utf-8"))
        return audit_inventory(repo, inventory, ports, head, git)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"[!!] 复用台账不可用：{error}")
        return True


def audit_inventory(repo: Path, inventory: dict, ports: list[dict], head: str, git) -> bool:
    dirty = False
    covered: set[str] = set()
    ids: set[str] = set()
    fields = {"id", "classification", "local", "upstream", "repository", "reviewed_at",
              "reason", "owner", "tests", "parity_gaps", "parity", "action"}
    print("\n── Rust 能力台账：覆盖检查 + 改写/缺失模块的上游复核提醒 ──")
    roots = inventory.get("rust_roots", [])
    expected_roots = {"rust/local_core/src", "rust/gpu_present/src", "rust/ocr_core/src", "rust/src"}
    if set(roots) != expected_roots:
        print("[!!] rust_roots 必须覆盖四个 Rust 源码根目录")
        dirty = True
    entries = inventory.get("entries", [])
    for entry in entries:
        identity = entry.get("id", "<missing>")
        if fields - entry.keys() or identity in ids or entry.get("classification") not in KINDS:
            print(f"[!!] {identity}：字段、分类或唯一 ID 不合法")
            dirty = True
            continue
        ids.add(identity)
        for path in entry["local"]:
            local = repo / path
            if not local.exists() or local.resolve().is_relative_to(repo.resolve()) is False:
                print(f"[!!] {identity}：本地路径不存在或越界：{path}")
                dirty = True
                continue
            files = local.rglob("*.rs") if local.is_dir() else [local]
            covered.update(str(p.relative_to(repo)) for p in files if p.suffix == ".rs")
        if entry["repository"] != "mimageviewer":
            continue
        try:
            pin = entry["reviewed_at"]
            if not isinstance(pin, str) or not re.fullmatch(r"[0-9a-f]{40}", pin):
                raise ValueError("reviewed_at 必须为完整 commit SHA")
            git("cat-file", "-e", f"{pin}^{{commit}}")
            git("merge-base", "--is-ancestor", pin, head)
            if not entry["upstream"]:
                raise ValueError("缺少上游映射")
            for path in entry["upstream"]:
                if Path(path).is_absolute() or ".." in Path(path).parts:
                    raise ValueError(f"上游路径越界：{path}")
                git("cat-file", "-e", f"{pin}:{path}")
                git("cat-file", "-e", f"{head}:{path}")
            changed = git("diff", "--name-only", f"{pin}..{head}", "--", *entry["upstream"]).strip()
            if changed:
                print(f"[!!] {identity}：上游有变更，负责人 {entry['owner']}；{entry['classification']}")
                print(f"     {changed.replace(chr(10), ', ')}")
                print(f"     差异：{entry['reason']}；待验证：{'; '.join(entry['parity_gaps'])}")
                dirty = True
            local_changes = git("diff", "--name-only", head, "--", *entry["upstream"]).strip()
            if local_changes:
                print(f"[!!] {identity}：vendor 工作树与子模块 HEAD 不同：{local_changes.replace(chr(10), ', ')}")
                dirty = True
        except (RuntimeError, ValueError) as error:
            print(f"[!!] {identity}：上游路径或复核基线无效：{error}")
            dirty = True
    source_files = {str(p.relative_to(repo)) for root in expected_roots for p in (repo / root).rglob("*.rs")}
    missing = source_files - covered
    for path in sorted(missing):
        print(f"[!!] 新增/遗漏 Rust 源码尚未登记：{path}")
    dirty |= bool(missing)
    for port in ports:
        if port["local"] not in covered:
            print(f"[!!] PORTS 条目没有能力台账：{port['local']}")
            dirty = True
        elif not any(entry.get("repository") == "mimageviewer"
                     and port["upstream"] in entry.get("upstream", [])
                     and any(port["local"] == p or port["local"].startswith(p.rstrip('/') + '/')
                             for p in entry.get("local", [])) for entry in entries):
            print(f"[!!] PORTS 与能力台账上游映射不一致：{port['local']} <- {port['upstream']}")
            dirty = True
    if not dirty:
        print(f"[OK] {len(source_files)} 个 Rust 源文件已登记，{len(entries)} 项能力的上游基线有效。")
    return dirty
