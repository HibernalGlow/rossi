"""一键跑 Gate A texture PoC：清理 -> 启动 -> 截屏校验 -> 读落盘数据 -> 收尾。

存在的理由：
    直接在 shell 里串 ./texture_bridge.exe + taskkill 有两个坑，都会污染结论：
      1. MSYS/Git-Bash 会把 `//F` 这类参数做路径转换，taskkill 静默失败，
         上一个实例没被杀掉，多个实例同时往同名 poc-*-stats.json 写，
         于是「两条路径都有帧数」，看起来像两条链路同时在跑 —— 纯属假象。
      2. taskkill / tasklist 的输出是 GBK，Python 默认按 UTF-8 解码会抛
         UnicodeDecodeError，导致读取脚本自身崩掉而不是报告真实状态。

    所以这里统一：用 subprocess 列表参数（绕开 shell 转换）、
    显式 list[str] + GBK 容错解码、并在启动前后各校验一次实例数。

用法：
    python run_probe.py [等待秒数=12] [输出png=poc-capture.png]
"""

import ctypes
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import capture_probe  # noqa: E402  （同目录工具，复用截屏与像素判定）

EXE_NAME = "texture_bridge.exe"
DEBUG_DIR = os.path.abspath(
    os.path.join(HERE, "..", "build", "windows", "x64", "runner", "Debug")
)
STATS_FILES = ("poc-native-stats.json", "poc-wgpu-stats.json")


def run(args):
    """跑外部命令，输出按 GBK 容错解码（Windows 工具在中文环境下是 GBK）。"""
    proc = subprocess.run(args, capture_output=True)
    out = (proc.stdout or b"") + (proc.stderr or b"")
    return out.decode("gbk", errors="replace")


def instances():
    out = run(["tasklist", "/FI", "IMAGENAME eq %s" % EXE_NAME, "/FO", "CSV"])
    return [ln for ln in out.splitlines() if EXE_NAME.lower() in ln.lower()]


def kill_all():
    for _ in range(4):
        run(["taskkill", "/F", "/IM", EXE_NAME])
        if not instances():
            return True
        time.sleep(0.4)
    return not instances()


def main():
    wait_s = float(sys.argv[1]) if len(sys.argv) > 1 else 12.0
    out_png = sys.argv[2] if len(sys.argv) > 2 else "poc-capture.png"

    if not kill_all():
        print("FAIL 无法清理残留实例，先手工处理再重试")
        return 2
    print("[1/5] 残留实例已清理：0")

    for name in STATS_FILES:
        path = os.path.join(DEBUG_DIR, name)
        if os.path.exists(path):
            os.remove(path)

    exe = os.path.join(DEBUG_DIR, EXE_NAME)
    if not os.path.exists(exe):
        print("FAIL 未找到 %s，先构建" % exe)
        return 2

    log = open(os.path.join(HERE, "..", "probe-run.log"), "wb")
    proc = subprocess.Popen([exe], cwd=DEBUG_DIR, stdout=log, stderr=log)
    print("[2/5] 已启动 pid=%d，等待 %.1fs" % (proc.pid, wait_s))
    time.sleep(wait_s)

    alive = [ln for ln in instances() if str(proc.pid) in ln]
    print("[3/5] 进程存活：%s" % ("是" if alive else "否（可能已崩溃）"))

    rc = capture_probe.main_argv("texture_bridge", out_png)
    print("[4/5] 像素校验返回码 = %d" % rc)

    print("[5/5] 落盘数据：")
    report = {}
    for name in STATS_FILES:
        path = os.path.join(DEBUG_DIR, name)
        if not os.path.exists(path):
            print("  --- %s: 未生成 ---" % name)
            continue
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        report[name] = data
        stats = data.get("stats", {})
        active = data.get("measuredFps") is not None
        print("  --- %s%s ---"
              % (name, "  [当前驱动]" if active else "  [空闲]"))
        print("      verdict=%s  ok=%s  尺寸=%sx%s  帧=%s  handleOpened=%s  "
              "重建=%s  Dart实测=%s"
              % (data.get("verdict"), stats.get("ok"), stats.get("width"),
                 stats.get("height"), stats.get("frames"),
                 stats.get("handleOpened"), stats.get("recreates"),
                 data.get("measuredFps")))
        probe_raw = stats.get("probe")
        if isinstance(probe_raw, str) and probe_raw:
            try:
                probe = json.loads(probe_raw)
            except ValueError:
                probe = None
            if probe:
                print("      [探针] 后端=%s  adapter=%s  命中=%s"
                      % (probe.get("backend"), probe.get("adapter"),
                         probe.get("adapterMatched")))
                print("      [探针] 直接共享 wgpu texture = %s"
                      % probe.get("directShareOfWgpuTexture"))
                print("      [探针] 替代路径=%s  拷贝次数=%s  初始化=%sms"
                      % (probe.get("copyPath"), probe.get("copies"),
                         probe.get("initMs")))
                if probe.get("error"):
                    print("      [探针] error=%s" % probe.get("error"))

    kill_all()
    log.close()
    print("已收尾，实例数：%d" % len(instances()))
    return rc


if __name__ == "__main__":
    sys.exit(main())
