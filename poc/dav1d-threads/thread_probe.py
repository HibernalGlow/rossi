#!/usr/bin/env python3
"""量 dav1d 在不同「可用核预算」下解一页要多久 —— 以及两个解码并发时各要多久。

为什么需要它
------------
`docs/v0.1-local-core.md` §12.4 只量了 1 / 2 / 16 核（结论：1→16 核只有 2.25×，
这条流几乎没有 tile 级并行）。§12.6 从这条结论推出下一步杠杆是
**「按优先级给翻页和预取分配核」**（翻页全核、预取少核），
但「预取给几个核」在只有 1/2/16 三个点的情况下是拍脑袋 —— 缺 4 核和 8 核。

怎么做的
--------
dav1d 的线程数是 auto：`image` 的 avif 后端**不暴露** `dav1d::Settings`
（`image-0.25.10/src/codecs/avif/decoder.rs:82` 直接 `dav1d::Decoder::new()`），
所以**改不了线程数，但可以限制进程能用哪些核**。亲和性掩码会被子进程继承，
于是「N 个核可用」≈「dav1d 只有 N 个核可跑」。

⚠ **已知坑（§12.4 踩过，这里每次回读复核）**：`GetCurrentProcess()` 不设
`restype = c_void_p` 会被截断成 32 位，`SetProcessAffinityMask` **静默返回 FALSE**、
掩码其实没生效 —— 那一轮的数字全是噪声。所以本脚本每次设完都回读
`GetProcessAffinityMask`，复核不一致就直接报错退出，不产出可疑数据。

口径
----
`scale_probe --rounds 1` 每轮**只解一次 dav1d**（解码结果被所有档位复用，
见 `scale_probe.rs:97-100`），所以一次运行 = 一个干净的「解这一页要多久」样本，
成本约 250 ms，不必跑满 rounds。读的是表格里 `全尺寸` 那行的「解码ms」列。

用法
----
    # 单进程扫描：可用核数 = 1 / 2 / 4 / 8 / 16
    python poc/dav1d-threads/thread_probe.py --archive <归档> [--index 0]

    # 并发对照：两个解码同时跑，各分到 8 个核（模拟「翻页 + 预取」）
    python poc/dav1d-threads/thread_probe.py --archive <归档> --concurrent 8 8

退出码：0 = 正常产出；2 = 参数/环境问题；3 = 亲和性掩码没生效（数据不可信）。
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
PROBE = REPO / "rust" / "target" / "release" / "scale_probe.exe"

# dav1d.dll 不在系统目录里，构建/运行期都靠 vcpkg 的那份（见 docs/windows-build/README.md）。
VCPKG_BIN = Path("D:/scoop/persist/vcpkg/installed/x64-windows/bin")

# `全尺寸（基线）` 行里的「解码ms」列。表格是 `{:>22}  {:>9}  ...`，所以按空白切最省事。
# 行名实际是 `全尺寸（基线）`，全角括号别想当然。
DECODE_ROW = re.compile(r"全尺寸[^\n\d]*([\d.]+)\s")


def child_env() -> dict[str, str]:
    env = dict(os.environ)
    if VCPKG_BIN.exists():
        env["PATH"] = f"{VCPKG_BIN}{os.pathsep}{env.get('PATH', '')}"
    return env


# ── 亲和性 ────────────────────────────────────────────────────────────────────
#
# 两个函数只在这里用，写死 Windows 语义。子进程会**继承**父进程的掩码，
# 所以做法是「让一个中间进程把自己钉住，再由它去起 scale_probe」。


def set_and_verify_affinity(mask: int) -> int:
    """把自己钉到 `mask` 上，回读复核，返回实际生效的掩码。

    复核不是可选的：`SetProcessAffinityMask` 失败时**只返回 FALSE 不抛异常**
    （§12.4 因此得到过一轮噪声数据）。
    """
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    # 关键：不设 restype 会被截断成 32 位指针 —— 这正是 §12.4 那个坑。
    kernel32.GetCurrentProcess.restype = ctypes.c_void_p
    handle = kernel32.GetCurrentProcess()

    if not kernel32.SetProcessAffinityMask(ctypes.c_void_p(handle), ctypes.c_size_t(mask)):
        raise OSError(f"SetProcessAffinityMask({mask:#x}) 失败：{ctypes.get_last_error()}")

    proc_mask = ctypes.c_size_t()
    sys_mask = ctypes.c_size_t()
    if not kernel32.GetProcessAffinityMask(
        ctypes.c_void_p(handle),
        ctypes.byref(proc_mask),
        ctypes.byref(sys_mask),
    ):
        raise OSError(f"GetProcessAffinityMask 失败：{ctypes.get_last_error()}")
    return proc_mask.value


def logical_cpus() -> int:
    return os.cpu_count() or 1


def mask_for(cores: list[int]) -> int:
    m = 0
    for c in cores:
        m |= 1 << c
    return m


# ── 运行 ──────────────────────────────────────────────────────────────────────


def run_probe(archive: Path, index: int, mask: int) -> dict:
    """在 `mask` 约束下跑一次 scale_probe，返回解析出的数字。

    `--set-mask` 是给中间进程用的：它自己设掩码，再起真正的探针（子进程继承掩码）。
    """
    if sys.argv[1:2] == ["--set-mask"]:
        # 这个分支只在中间进程里走到（见 main）。
        raise RuntimeError("不该在这里执行")

    cmd = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--set-mask",
        hex(mask),
        "--",
        str(PROBE),
        str(archive),
        str(index),
        "--rounds",
        "1",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, env=child_env())
    if proc.returncode != 0:
        raise RuntimeError(
            f"探针失败（mask={mask:#x}, rc={proc.returncode}）：\n"
            f"{proc.stdout[-2000:]}\n{proc.stderr[-2000:]}"
        )
    return parse(proc.stdout, mask)


def parse(stdout: str, mask: int) -> dict:
    m = DECODE_ROW.search(stdout)
    if not m:
        raise RuntimeError(f"解析不出「全尺寸（基线）」行（mask={mask:#x}）：\n{stdout[-1500:]}")
    actual = None
    for line in stdout.splitlines():
        if line.startswith("__AFFINITY__"):
            actual = int(line.split("=", 1)[1], 0)
    size = re.search(r"尺寸\s*:\s*(\d+)x(\d+)", stdout)
    return {
        "mask": mask,
        "mask_actual": actual,
        "decode_ms": float(m.group(1)),
        "size": f"{size.group(1)}x{size.group(2)}" if size else None,
    }


def spawn_probe(archive: Path, index: int, mask: int) -> subprocess.Popen:
    """非阻塞版：两个并发对照要同时起来。"""
    cmd = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--set-mask",
        hex(mask),
        "--",
        str(PROBE),
        str(archive),
        str(index),
        "--rounds",
        "1",
    ]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=child_env())


# ── 入口 ──────────────────────────────────────────────────────────────────────


def main() -> int:
    argv = sys.argv[1:]

    # 中间进程：设自己的掩码，然后把剩下的参数当命令跑掉。
    if argv[:1] == ["--set-mask"]:
        mask = int(argv[1], 0)
        actual = set_and_verify_affinity(mask)
        print(f"__AFFINITY__={hex(actual)}", flush=True)
        if actual != mask:
            # 掩码被系统裁剪（可用核不够等）：说出来并退出，别产出可疑数字。
            print(f"掩码没生效：要 {mask:#x}，实际 {actual:#x}", file=sys.stderr)
            return 3
        rest = argv[argv.index("--") + 1 :]
        return subprocess.run(rest, env=child_env()).returncode

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--archive", required=True, type=Path)
    ap.add_argument("--index", type=int, default=0)
    ap.add_argument("--sweep", default="1,2,4,8,16", help="单进程扫描的核数列表")
    ap.add_argument(
        "--concurrent",
        nargs="+",
        type=int,
        metavar="N",
        help="并发对照：每个数是一路分到的核数，如 `--concurrent 8 8`",
    )
    ap.add_argument("--json", type=Path, help="把结果写成 JSON")
    args = ap.parse_args()

    if not PROBE.exists():
        print(f"找不到探针：{PROBE}\n先构建：cargo build --release -p rossi_local_core --bin scale_probe", file=sys.stderr)
        return 2
    if not args.archive.exists():
        print(f"找不到归档：{args.archive}", file=sys.stderr)
        return 2

    total = logical_cpus()
    out: dict = {"archive": str(args.archive), "index": args.index, "logical_cpus": total}

    # ── 单进程扫描 ──
    if args.sweep:
        print(f"逻辑核数 {total}；单进程扫描：{args.sweep}")
        print(f"{'可用核':>6}  {'解码 ms':>9}   实际掩码")
        print("-" * 34)
        sweep = []
        for n in (int(x) for x in args.sweep.split(",") if x.strip()):
            if n > total:
                continue
            mask = mask_for(list(range(n)))
            row = run_probe(args.archive, args.index, mask)
            sweep.append(row | {"cores": n})
            flag = "" if row["mask_actual"] == mask else f"  !! 实际 {row['mask_actual']:#x}"
            print(f"{n:>6}  {row['decode_ms']:>9.1f}   {mask:#06x}{flag}")
        out["sweep"] = sweep

    # ── 并发对照 ──
    if args.concurrent:
        plan, cursor = [], 0
        for n in args.concurrent:
            if cursor + n > total:
                print(f"核不够分：还剩 {total - cursor} 个，要 {n} 个", file=sys.stderr)
                return 2
            plan.append((n, mask_for(list(range(cursor, cursor + n)))))
            cursor += n
        print(f"\n并发对照：{args.concurrent}（各占 {[hex(m) for _, m in plan]}）")
        procs = [spawn_probe(args.archive, args.index, m) for _, m in plan]
        concurrent = []
        for (n, mask), p in zip(plan, procs):
            stdout, stderr = p.communicate()
            if p.returncode != 0:
                print(f"  一路失败（{n} 核，rc={p.returncode}）：{stderr[-400:]}", file=sys.stderr)
                return 2
            row = parse(stdout, mask) | {"cores": n}
            concurrent.append(row)
            print(f"  {n:>2} 核（{mask:#06x}）解码 {row['decode_ms']:>7.1f} ms")
        out["concurrent"] = concurrent

    if args.json:
        args.json.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n已写入 {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
