#!/usr/bin/env python3
"""检查 rust/local_core 里「搬进来」的 mImageViewer 模块与上游的偏离。

为什么需要这个脚本
------------------
`rust/local_core` 里有六个模块是从 `vendor/mimageviewer` **逐字搬来**的，
而不是 path 依赖 —— 因为上游把它们放在私有 `mod app;` / 私有
`mod fs_page_load_scheduler;` 之下、通体 `pub(crate)`，跨 crate 根本 use 不到：

    rust/local_core/src/page_load_scheduler.rs   <-  src/fs_page_load_scheduler.rs
    rust/local_core/src/prefetch_policy.rs       <-  src/app/prefetch_policy.rs
    rust/local_core/src/folder_tree.rs           <-  src/folder_tree.rs
    rust/local_core/src/fs_entry.rs              <-  src/fs_entry.rs
    rust/local_core/src/filename_sort.rs         <-  src/filename_sort.rs
    rust/local_core/src/auto_aspect.rs           <-  src/auto_aspect.rs


搬运时刻意保住了上游的**函数名 / 类型名 / 常量名 / 测试名**，只做少量必要偏离
（清单见下面的 `PORTS`，理由见 `docs/local-core-vendored-modules.md`）。
保住名字就是为了今天：上游更新时，这份代码还能跟。

本脚本回答一个问题：**上游动了，我这份要不要跟着改？**

用法
----
    python script/sync_vendored_modules.py            # 出报告
    python script/sync_vendored_modules.py --diff     # 附上游原始 diff
    python script/sync_vendored_modules.py --bump <rev>   # 同步成功后更新 pin

退出码：0 = 无需处理；1 = 上游有变更或发现未记录的偏离（需要人看）。
"""

from __future__ import annotations

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VENDOR = REPO / "vendor" / "mimageviewer"

# ── 移植清单 ────────────────────────────────────────────────────────────────
#
# `pinned_at`：本地这份是从上游哪个 commit 搬的。**同步成功后要更新它**。
#
# `upstream_normalize` / `local_strip` / `upstream_strip` / `drop_lines`：把两侧源码
#   归一化成「可比形态」用的替换。**每加一条本地偏离，就要在这里加一条**，否则脚本
#   会把已知偏离误报成「上游改了」。字段含义：
#     upstream_normalize  上游 → 本地形态（本地对上游做的等价改写）
#     local_strip         本地独有的整段（上游没有）
#     upstream_strip      上游独有、本地刻意未搬的整段
#     drop_lines          两侧都要丢掉的行（本地新增的 import）
PORTS = [
    {
        "upstream": "src/folder_tree.rs",
        "local": "rust/local_core/src/folder_tree.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            (r"\bpub\(crate\)", "pub"),
            # Unix 的反斜杠/大小写不能使用 Catalog 的 Windows 风格归一化键。
            (r"crate::path_key::normalize_keep_drive", "crate::fs_entry::directory_visit_key"),
            (
                r"a\.to_string_lossy\(\)\.to_lowercase\(\) == b\.to_string_lossy\(\)\.to_lowercase\(\)",
                "#[cfg(windows)] { crate::path_key::eq_keep_drive(a, b) }\n"
                "#[cfg(not(windows))] { a == b }",
            ),
            (r"#\[test\]\n(\s*)fn path_eq_case_insensitive", r"#[cfg(windows)]\n#[test]\n\1fn path_eq_case_insensitive"),
            (r'\.join\("testdata/archives/rar-multipart-filename-regression"\)',
             '.join("../../vendor/mimageviewer/testdata/archives/rar-multipart-filename-regression")'),
        ],
        "local_strip": [
            # 新增 Unix 平台回归测试；上游 Windows 测试仍参与比较。
            (r"\n\s*#\[cfg\(not\(windows\)\)\]\n\s*#\[test\]\n\s*fn unix_paths_preserve_case_and_backslashes\(\) \{[^}]*\}", ""),
            # 既有移植：没有 checkout 测试数据时跳过上游 RAR 样本用例。
            (r'\s*if !fixture\.is_dir\(\) \{\s*eprintln!\(\s*"skip: upstream RAR fixture is not checked out: \{\}"\s*,\s*fixture\.display\(\)\s*\);\s*return;\s*\}', ""),
        ],
        "upstream_strip": [],
        "drop_lines": [],
    },
    {
        "upstream": "src/fs_entry.rs",
        "local": "rust/local_core/src/fs_entry.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            (r"\bpub\(crate\)", "pub"),
            (
                r"fn classify_special_dir_entry\(_entry: &DirEntry, _file_type: &FileType\) -> DirEntryKind \{\s*DirEntryKind::Other\s*\}",
                """fn classify_special_dir_entry(entry: &DirEntry, file_type: &FileType) -> DirEntryKind {
                    if file_type.is_symlink() {
                        if let Ok(metadata) = std::fs::metadata(entry.path()) {
                            if metadata.is_dir() { return DirEntryKind::ReparseDirectory; }
                            if metadata.is_file() { return DirEntryKind::File; }
                        }
                    }
                    DirEntryKind::Other
                }""",
            ),
            (
                r"crate::path_key::normalize_keep_drive\(&resolved\)",
                "#[cfg(windows)] { crate::path_key::normalize_keep_drive(&resolved) }\n"
                "#[cfg(not(windows))] { resolved.to_string_lossy().into_owned() }",
            ),
        ],
        "local_strip": [],
        "upstream_strip": [],
        "drop_lines": [],
    },
    {
        "upstream": "src/filename_sort.rs",
        "local": "rust/local_core/src/filename_sort.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [(r"\bpub\(crate\)", "pub")],
        "local_strip": [],
        "upstream_strip": [],
        "drop_lines": [],
    },
    {
        "upstream": "src/fs_page_load_scheduler.rs",
        "local": "rust/local_core/src/page_load_scheduler.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            # 偏离 1：跨 crate 必须 pub。上游一律 pub(crate)。
            (r"\bpub\(crate\)", "pub"),
            # 偏离 2：上游走 serde_json 的 perf，本地走轻量 perf_sink。
            (r"crate::perf::is_enabled\b", "crate::perf_sink::is_enabled"),
            (r"crate::perf::event\b", "crate::perf_sink::event"),
            (r"serde_json::Value::from", "PerfValue::from"),
            # 偏离 3：stats() 从 #[cfg(test)] 提升为 pub（FRB 层要在调试页显示在跑几个解码）。
            (r"#\[cfg\(test\)\]\n[ \t]*pub fn stats\(", "pub fn stats("),
        ],
        "local_strip": [
            # 偏离 4：本地补的 Default（clippy 的 new_without_default）。
            (r"impl Default for FsPageLoadScheduler \{\n[\s\S]*?\n\}\n\n", ""),
        ],
        "upstream_strip": [],
        "drop_lines": [
            "use crate::perf_sink::PerfValue;",
        ],
    },
    {
        "upstream": "src/app/prefetch_policy.rs",
        "local": "rust/local_core/src/prefetch_policy.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            (r"\bpub\(crate\)", "pub"),
        ],
        "local_strip": [
            # 本地新增：本模块的纯函数测试（搬自上游 src/app/tests.rs，
            # 上游把这个文件自己的测试混在 App 的测试里，本文件本身无测试）。
            (r"\n#\[cfg\(test\)\]\nmod tests \{[\s\S]*$", "\n"),
        ],
        # 上游该文件末尾是 UI 指示器数据模型（给 egui 画点用 + 日文 tooltip），
        # 刻意没搬 —— 我们的 UI 在 Flutter 侧、由 Dart 自己画。比对时从上游侧删掉。
        "upstream_strip": [
            (r"/// フルスクリーンの AI 先読み表示で使うページ単位の状態。[\s\S]*$", ""),
        ],
        "drop_lines": [],
        # 未搬段的起点，用于抽取「上游在这段里新增/删掉了哪些函数」——
        # 那可能是新长出来的纯策略能力，值得搬。
        "unported_section_start": "/// フルスクリーンの AI 先読み表示で使うページ単位の状態。",
    },
    {
        "upstream": "src/auto_aspect.rs",
        "local": "rust/local_core/src/auto_aspect.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            (r"\bpub\(crate\)", "pub"),
        ],
        "local_strip": [],
        "upstream_strip": [],
        "drop_lines": [],
    },
    {
        "upstream": "src/page_split.rs",
        "local": "rust/local_core/src/page_split.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            # 偏离 1: B3 几何解耦，替换 eframe::egui 为本地无依赖纯几何类型与别名
            (r"use eframe::egui;", "use egui_compat as egui;"),
            # 偏离 2: Rotation 重定向到本地 rotation 模块
            (r"crate::rotation_db::Rotation", "crate::rotation::Rotation"),
            # 偏离 3: inverse_uv 重定向到本地 rotation 模块
            (r"crate::displayed_image_transform::inverse_uv", "crate::rotation::inverse_uv"),
        ],
        "local_strip": [
            # 本地 B3 纯几何结构体与兼容别名定义
            (r"// ── B3 几何类型剥离 ──[\s\S]*?use egui_compat as egui;\n\n// ── 上游核心逻辑 ──\n", "use egui_compat as egui;\n"),
        ],
        "upstream_strip": [],
        "drop_lines": [],
    },
    {
        "upstream": "src/folder_pane.rs",
        "local": "rust/local_core/src/folder_pane.rs",
        "pinned_at": "1fd6f863",
        "upstream_normalize": [
            # 偏离 1：跨 crate 必须 pub。上游一律 pub(crate)。
            (r"\bpub\(crate\)", "pub"),
            # 偏离 2：驱动器枚举委托给本地 file_tree::get_available_roots()
            (r"crate::known_folders::available_drives\(\)", "available_drives()"),
            # 偏离 3：上游走 serde_json 的 perf，本地走轻量 perf_sink。
            (r"crate::perf::is_enabled\b", "crate::perf_sink::is_enabled"),
            (r"crate::perf::event\b", "crate::perf_sink::event"),
            (r"serde_json::Value::from", "PerfValue::from"),
            # 偏离 4：上游硬编码 Windows 路径的单测在非 Windows 下标记为 #[cfg(windows)]
            (r"#\[test\]\n(\s*)fn active_virtual_folder_maps_to_parent", r"#[cfg(windows)]\n#[test]\n\1fn active_virtual_folder_maps_to_parent"),
            (r"#\[test\]\n(\s*)fn sync_to_active_expands_minimum_ancestor_chain", r"#[cfg(windows)]\n#[test]\n\1fn sync_to_active_expands_minimum_ancestor_chain"),
            (r"#\[test\]\n(\s*)fn auto_branch_is_replaced_but_user_expansion_persists", r"#[cfg(windows)]\n#[test]\n\1fn auto_branch_is_replaced_but_user_expansion_persists"),
            (r"#\[test\]\n(\s*)fn cursor_nav_target_only_when_cursor_moved_off_active", r"#[cfg(windows)]\n#[test]\n\1fn cursor_nav_target_only_when_cursor_moved_off_active"),
            (r"#\[test\]\n(\s*)fn sort_change_resets_expansion_and_scrolls_to_active", r"#[cfg(windows)]\n#[test]\n\1fn sort_change_resets_expansion_and_scrolls_to_active"),
            (r"#\[test\]\n(\s*)fn collapse_auto_expanded_branch_hides_it_until_active_changes", r"#[cfg(windows)]\n#[test]\n\1fn collapse_auto_expanded_branch_hides_it_until_active_changes"),
            (r"#\[test\]\n(\s*)fn hidden_visibility_change_rebuilds_tree_cache", r"#[cfg(windows)]\n#[test]\n\1fn hidden_visibility_change_rebuilds_tree_cache"),
            (r"#\[test\]\n(\s*)fn keyboard_moves_visible_rows_and_enter_opens_cursor", r"#[cfg(windows)]\n#[test]\n\1fn keyboard_moves_visible_rows_and_enter_opens_cursor"),
        ],
        "local_strip": [
            # 本地新增的 available_drives 跨平台根路径适配函数
            (r"fn available_drives\(\) -> Vec<PathBuf> \{\n[\s\S]*?\n\}\n\n", ""),
            # 本地新增的 Unix 路径回归测试
            (r"\n\s*#\[cfg\(not\(windows\)\)\]\n\s*#\[test\]\n\s*fn unix_[\s\S]*?(?=\n\s*(?:#\[|$))", ""),
        ],
        "upstream_strip": [],
        "drop_lines": [
            "use crate::perf_sink::PerfValue;",
        ],
    },
]



def git(*args: str, text: bool = True):
    """在 vendor 检出里跑 git。"""
    result = subprocess.run(
        ["git", "-C", str(VENDOR), *args],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} 失败：{result.stderr.decode('utf-8', 'replace').strip()}"
        )
    if text:
        return result.stdout.decode("utf-8", "replace")
    return result.stdout


def show_at(rev: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(VENDOR), "show", f"{rev}:{path}"],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8", "replace")


def normalize(text: str, port: dict, side: str) -> str:
    """把一侧的源码归一化成「可比形态」。

    side="upstream"：套 upstream_normalize，再套 upstream_strip（删掉刻意未搬的段）。
    side="local"：套 local_strip（删掉本地独有的段）。
    两侧都先丢掉 `drop_lines`（本地为可用性新增的 import 之类）。
    """
    kept = [line for line in text.splitlines() if line.strip() not in port["drop_lines"]]
    text = "\n".join(kept)
    if side == "upstream":
        rules = port["upstream_normalize"] + port["upstream_strip"]
    else:
        rules = port["local_strip"]
    for pattern, repl in rules:
        text = re.sub(pattern, repl, text, flags=re.S)
    return text


def split_code_and_notes(text: str) -> tuple[list[str], list[str]]:
    """拆成「代码行」与「注释行」，各自比。

    分两份是因为两类差异的处理方式不同：代码差必须跟，注释差只提示
    （上游的日文注释常写清语义/理由，值得看一眼，但不是编译级信号）。
    行首缩进被 strip —— 缩进差异是噪声。
    """
    code, notes = [], []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("//"):
            notes.append(stripped)
        else:
            code.append(stripped)
    return code, notes


def squeeze(text: str) -> str:
    """压成「排版无关形态」。用来判定「两份代码只差排版」——
    那是噪声，不是语义偏离，不该报成「有偏离没登记」。

    压两样东西：

    1. **全部空白**。rustfmt 按可用宽度决定折不折行，本机与本 pin 的 rustfmt
       风格不总是同一版，同一个调用会被折成两种形状。
    2. **收尾逗号**。`f(x,)` 与 `f(x)` 在 Rust 里是同一份代码，但 rustfmt 只在
       「已折行」时保留它 —— 所以只压空白会残留 `,),` vs `)),` 这种假差异。
       （实测踩过：`stats()` 里 `("total_limit", PerfValue::from(..))` 一条
       被报成未登记偏离，其实是纯排版。）
    """
    return re.sub(r",(?=[)\]}])", "", re.sub(r"\s+", "", text))


def unified(a: list[str], b: list[str], a_label: str, b_label: str) -> list[str]:
    return [
        line
        for line in difflib.unified_diff(a, b, a_label, b_label, lineterm="", n=1)
        if not line.startswith(("---", "+++"))
    ]


def report_port(port: dict, show_raw_diff: bool, head: str) -> bool:
    """返回 True 表示「有需要人处理的东西」。"""
    upstream_path = port["upstream"]
    local_path = REPO / port["local"]
    pin = port["pinned_at"]
    dirty = False

    print(f"\n{'=' * 76}")
    print(f"上游 {upstream_path}")
    print(f"本地 {port['local']}")
    print(f"pin  {pin}  →  HEAD {head[:12]}")
    print("=" * 76)

    if not local_path.exists():
        print(f"  !! 本地文件不存在：{local_path}")
        return True

    # 1) 上游在这个文件上有没有新提交
    log = git("log", "--oneline", f"{pin}..{head}", "--", upstream_path).strip()
    if not log:
        print(f"  [OK] pin..HEAD 之间上游没有动过这个文件。")
    else:
        dirty = True
        print(f"  [!!] 上游动过这个文件，{len(log.splitlines())} 个提交：")
        for line in log.splitlines():
            print(f"       {line}")

    # 2) 上游 pin 版归一化后 vs 本地：用来发现「本地有未记录的偏离」
    pinned_src = show_at(pin, upstream_path)
    head_src = show_at(head, upstream_path)
    local_src = local_path.read_text(encoding="utf-8")

    if pinned_src is None or head_src is None:
        print(f"  !! 取不到上游内容（路径变了吗？）")
        return True

    base = normalize(pinned_src, port, "upstream")
    mine = normalize(local_src, port, "local")

    base_code, base_notes = split_code_and_notes(base)
    mine_code, mine_notes = split_code_and_notes(mine)

    code_delta = unified(base_code, mine_code, f"上游@{pin[:8]}(归一化)", "本地")
    if not code_delta:
        print(f"  [OK] pin 版归一化后与本地代码完全一致 —— 已知偏离清单是完整的。")
    elif squeeze("\n".join(base_code)) == squeeze("\n".join(mine_code)):
        # 只差 rustfmt 的折行与收尾逗号：压掉空白后是同一份代码。别报成「有偏离没登记」。
        print(
            f"  [OK] 与 pin 版只差 rustfmt 的排版（{len(code_delta)} 行），压掉空白与收尾逗号后完全一致。"
        )
    else:
        dirty = True
        print(f"  [!!] pin 版归一化后与本地仍有代码差异 —— 说明存在**未记录**的偏离，")
        print(f"       要么补进 PORTS.upstream_normalize，要么把它记进文档：")
        for line in code_delta[:40]:
            print(f"       {line}")
        if len(code_delta) > 40:
            print(f"       ...（还有 {len(code_delta) - 40} 行）")

    note_delta = unified(base_notes, mine_notes, "上游注释", "本地注释")
    if note_delta:
        print(f"  [--] 注释差异 {len(note_delta)} 行（本地溯源段属预期；若上游改了注释值得看一眼）：")
        for line in note_delta[:20]:
            print(f"       {line}")
        if len(note_delta) > 20:
            print(f"       ...（还有 {len(note_delta) - 20} 行）")

    # 3) 上游 pin → HEAD 到底改了什么（真正的升级材料）
    if log:
        head_norm = normalize(head_src, port, "upstream")
        up_code, _ = split_code_and_notes(head_norm)
        upstream_delta = unified(base_code, up_code, f"上游@{pin[:8]}", f"上游@{head[:8]}")
        if upstream_delta:
            print(f"\n  ── 上游这段时间对**代码**的改动（这就是要 apply 的东西）──")
            for line in upstream_delta:
                print(f"       {line}")
        else:
            print(f"\n  [OK] 上游只改了注释/文档，代码未变。")

        if show_raw_diff:
            print(f"\n  ── 上游原始 diff（--diff）──")
            raw = git("diff", f"{pin}..{head}", "--", upstream_path)
            for line in raw.splitlines():
                print(f"       {line}")

    # 4) 未搬走的那一段，上游有没有长出/删掉函数 —— 那可能是该搬的纯策略能力
    start = port.get("unported_section_start")
    if start and log:
        def fn_names(text: str) -> set[str]:
            section = text[text.find(start):] if start in text else ""
            return set(re.findall(r"\bfn\s+(\w+)", section))

        before, after = fn_names(pinned_src), fn_names(head_src)
        added, removed = sorted(after - before), sorted(before - after)
        if added or removed:
            print(f"\n  ── 本地**刻意未搬**的那一段，上游变了 ──")
            if added:
                print(f"       新增函数：{', '.join(added)}")
                print(f"       → 若是纯策略（不含 UI/egui 类型），考虑一并搬进本地")
            if removed:
                print(f"       移除函数：{', '.join(removed)}")
        else:
            print(f"\n  [OK] 未搬的那一段函数集合未变。")

    return dirty


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diff", action="store_true", help="附上游原始 diff")
    parser.add_argument("--bump", metavar="REV", help="把 PORTS 里的 pinned_at 全部改成 REV")
    args = parser.parse_args()

    if not VENDOR.exists():
        print(f"找不到 vendor 检出：{VENDOR}", file=sys.stderr)
        print("（新机 clone 需要 --recursive；见 docs/adr/0007）", file=sys.stderr)
        return 2

    if args.bump:
        target = Path(__file__).resolve()
        text = target.read_text(encoding="utf-8")
        text = re.sub(
            r'("pinned_at":\s*")[0-9a-f]{7,40}(")',
            rf"\g<1>{args.bump}\g<2>",
            text,
        )
        target.write_text(text, encoding="utf-8", newline="\n")
        print(f"已把 pinned_at 更新为 {args.bump}（记得同时更新 docs/local-core-vendored-modules.md）")
        return 0

    head = git("rev-parse", "HEAD").strip()
    dirty = False
    for port in PORTS:
        dirty |= report_port(port, args.diff, head)

    print(f"\n{'=' * 76}")
    if dirty:
        print("结论：有东西需要人看（上游变了 / 或本地偏离没记全）。")
        print("处理完之后：python script/sync_vendored_modules.py --bump <新的上游 commit>")
        return 1
    print("结论：本地与 pin 版一致，上游也没动过这些文件。无需处理。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
