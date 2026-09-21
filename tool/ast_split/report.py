#!/usr/bin/env python3
"""拆分工作的最终对账表。

对每个目标文件给出：上游行数 / 开工时行数 / 现在行数 / 是否达标 /
对上游的偏差 `+/−`（拆前 vs 现在）—— 这一列是「有没有动上游代码」的证据：
`−` 保持拆前水平才说明只搬了自己的东西。
"""

import os
import subprocess
import sys
from pathlib import Path

R = Path(__file__).resolve().parents[2]
REF = os.environ.get("VERIFY_REF", "35a6be81")
UP = os.environ.get("UPSTREAM_REF", "upstream/main")

B_FILES = [
    "lib/config/global/global_setting.dart",
    "lib/page/comic_read/widgets/settings/reader_settings_read_tab.dart",
    "lib/network/sync/sync_service.dart",
    "lib/page/setting/real_sr/service/real_sr_super_resolution.dart",
    "lib/page/comic_info/view/comic_info.dart",
    "lib/main.dart",
    "lib/page/comic_info/models/collect_comic.dart",
    "lib/page/comic_read/cubit/reader_seamless_cubit.dart",
]

C_FILES = [
    "lib/workspace/widgets/cards/file_manager_card.dart",
    "rust/local_core/src/file_manager.rs",
    "rust/local_core/src/catalog.rs",
    "rust/local_core/src/folder_tree.rs",
    "rust/local_core/src/file_ops/execute.rs",
    "rust/local_core/src/folder_pane.rs",
    "rust/local_core/src/operation_binding/radial.rs",
    "rust/local_core/src/page_load_scheduler.rs",
    "rust/gpu_present/src/presenter.rs",
    "rust/gpu_present/src/mac_presenter.rs",
    "rust/gpu_present/src/lib.rs",
    "rust/gpu_present/src/wgpu_resampler.rs",
    "rust/src/api/file_manager.rs",
    "lib/debug/local_source_debug_page.dart",
    "lib/reader/gpu_present_controller.dart",
    "lib/video/view/video_control_overlay.dart",
    "lib/page/setting/global/workspace_layout_setting_page.dart",
    "lib/page/setting/real_sr/widgets/upscale_conditions_card.dart",
    "web/rossi_webgpu/rossi_gpu_present.js",
    "windows/runner/gpu_present_bridge.cpp",
    "test/workspace/file_manager_card_test.dart",
    "test/video/video_playback_logic_test.dart",
    "test/video/mpv_property_probe_test.dart",
]


def git(*a: str) -> str:
    return subprocess.run(["git", *a], cwd=R, capture_output=True, text=True).stdout


def lines_at(ref: str, path: str) -> int:
    """ref 处该文件的行数；不存在则 -1。"""
    rc = subprocess.run(["git", "cat-file", "-e", f"{ref}:{path}"], cwd=R,
                        capture_output=True).returncode
    if rc != 0:
        return -1
    return len(git("show", f"{ref}:{path}").split("\n"))


def lines_now(path: str) -> int:
    p = R / path
    if p.exists():
        return len(p.read_text(encoding="utf-8").split("\n"))
    # 可能被改成了 <stem>/mod.rs
    alt = p.with_suffix("") / "mod.rs"
    if alt.exists():
        return len(alt.read_text(encoding="utf-8").split("\n"))
    return -1


def numstat(a: str, b: str, path: str) -> tuple[int, int]:
    """b 传空串表示与**工作区**比。"""
    args = ["diff", "--numstat", a] + ([b] if b else []) + ["--", path]
    out = git(*args)
    for line in out.splitlines():
        f = line.split("\t")
        if len(f) >= 2:
            try:
                return int(f[0]), int(f[1])
            except ValueError:
                return 0, 0
    return 0, 0


def report(title: str, files: list[str], against_upstream: bool) -> None:
    print(f"\n=== {title} ===")
    hdr = (f"{'文件':<56}{'上游':>6}{'开工':>6}{'现在':>6}"
           f"{'达标':>5}  {'对上游 +/− 开工→现在':<24}")
    print(hdr)
    print("-" * len(hdr))
    not_done = []
    for f in files:
        u = lines_at(UP, f) if against_upstream else -1
        r = lines_at(REF, f)
        n = lines_now(f)
        ok = n > 0 and n <= 1000
        if not ok:
            not_done.append(f)
        a1, d1 = numstat(UP, REF, f) if against_upstream else (0, 0)
        a2, d2 = numstat(UP, "HEAD", f) if against_upstream else (0, 0)
        # 工作区未提交部分也要算进来
        a3, d3 = numstat(UP, "", f) if against_upstream else (0, 0)
        mark = "✓" if ok else "✗"
        span = f"+{a1}/−{d1} → +{a3}/−{d3}" if against_upstream else "（本仓新增）"
        print(f"{f:<56}{u:>6}{r:>6}{n:>6}{mark:>5}  {span:<24}")
    print(f"\n未达标 {len(not_done)} 个：")
    for f in not_done:
        print(f"  {f}  现在 {lines_now(f)} 行")


def main() -> int:
    report("B 类：上游已有、本仓在文件内加长（只许搬本仓自己的行）", B_FILES, True)
    report("C 类：本仓全新文件（整体模块化）", C_FILES, False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
