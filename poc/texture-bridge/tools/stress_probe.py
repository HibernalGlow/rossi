"""Gate A 稳定性压测：尺寸抖动 + 持续运行，检查重建/退役是否收敛、内存是否泄漏。

为什么必须单独测：
    GPU surface texture 的生命周期是最容易埋雷的地方。窗口尺寸一变，
    SurfaceCallback 就要销毁旧的 shared texture、建新的、换 handle。
    如果创建/销毁不成对，表现是「跑几分钟后显存爆掉」或者「resize 几十次后
    画面变黑」—— 这类问题单帧截图完全看不出来，必须跑量。

判据：
    1. recreates 增长应当跟随尺寸变化次数，且每次变化只重建一次。
    2. retired 应当有界（约等于 recreates 的历史总数），不能出现
       「retired 远小于 recreates」这种旧资源没被释放的情况。
    3. 进程存活，frames 持续增长（画面没卡死）。
    4. 工作集内存在抖动结束后不回落到合理水平，就说明有泄漏。

用法：
    python stress_probe.py [抖动轮数=3] [每轮尺寸变化次数=40] [收尾静置秒数=5]
"""

import ctypes
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
EXE_NAME = "texture_bridge.exe"
DEBUG_DIR = os.path.abspath(
    os.path.join(HERE, "..", "build", "windows", "x64", "runner", "Debug")
)
WGOU_STATS = os.path.join(DEBUG_DIR, "poc-wgpu-stats.json")

user32 = ctypes.WinDLL("user32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)
user32.FindWindowW.restype = wintypes.HWND
user32.SetWindowPos.argtypes = [
    wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
    ctypes.c_int, ctypes.c_int, wintypes.UINT,
]
psapi.GetProcessMemoryInfo.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD
]


class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD),
        ("PageFaultCount", wintypes.DWORD),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
    ]


def run(args):
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


def working_set(pid):
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    PROCESS_VM_READ = 0x0010
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.OpenProcess.restype = wintypes.HANDLE
    handle = k32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, False, pid
    )
    if not handle:
        return None
    try:
        counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters),
                                          counters.cb):
            return None
        return counters.WorkingSetSize
    finally:
        k32.CloseHandle(handle)


def read_stats():
    for _ in range(20):
        try:
            with open(WGOU_STATS, "r", encoding="utf-8") as handle:
                return json.load(handle)
        except (IOError, OSError, ValueError):
            time.sleep(0.2)
    return None


def probe_of(data):
    raw = data.get("stats", {}).get("probe") if data else None
    if isinstance(raw, str) and raw:
        try:
            return json.loads(raw)
        except ValueError:
            return {}
    return {}


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    settle = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0

    try:
        user32.SetProcessDPIAware()
    except Exception:
        pass

    if not kill_all():
        print("FAIL 无法清理残留实例")
        return 2
    if os.path.exists(WGOU_STATS):
        os.remove(WGOU_STATS)

    exe = os.path.join(DEBUG_DIR, EXE_NAME)
    log = open(os.path.join(HERE, "..", "stress-run.log"), "wb")
    proc = subprocess.Popen([exe], cwd=DEBUG_DIR, stdout=log, stderr=log)
    time.sleep(6.0)

    hwnd = user32.FindWindowW(None, "texture_bridge")
    if not hwnd:
        print("FAIL 未找到窗口")
        kill_all()
        return 2

    base = read_stats()
    base_probe = probe_of(base)
    base_ws = working_set(proc.pid)
    print("基线: 帧=%s 重建=%s 惰性队列=%s 累计释放=%s 工作集=%.1f MB"
          % (base_probe.get("frames"), base_probe.get("recreates"),
             base_probe.get("retired"), base_probe.get("releasedTotal"),
             (base_ws or 0) / 1048576.0))

    SWP_NOMOVE, SWP_NOZORDER, SWP_NOACTIVATE = 0x0002, 0x0004, 0x0010
    flags = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
    sizes = []
    per_round = 0

    for r in range(rounds):
        for i in range(steps):
            # 尺寸刻意取非 16 对齐值，逼出 stride/对齐相关的边界问题。
            w = 700 + ((i * 137 + r * 61) % 900)
            h = 450 + ((i * 89 + r * 43) % 500)
            user32.SetWindowPos(hwnd, None, 0, 0, w, h, flags)
            time.sleep(0.10)
            sizes.append((w, h))
        per_round += steps
        mid = read_stats()
        mid_probe = probe_of(mid)
        print("  第 %d 轮结束: 帧=%s 重建=%s 累计释放=%s"
              % (r + 1, mid_probe.get("frames"), mid_probe.get("recreates"),
                 mid_probe.get("releasedTotal")))

    print("抖动完成，共 %d 次尺寸变化，静置 %.1fs 观察回落" % (len(sizes), settle))
    time.sleep(settle)

    end = read_stats()
    end_probe = probe_of(end)
    end_ws = working_set(proc.pid)
    alive = [ln for ln in instances() if str(proc.pid) in ln]

    frames_ok = (end_probe.get("frames") or 0) > (base_probe.get("frames") or 0)
    recreates = end_probe.get("recreates") or 0
    queue = end_probe.get("retired") or 0
    released = end_probe.get("releasedTotal")
    if released is None:
        released = end_probe.get("retired") or 0

    print("")
    print("=== 结果 ===")
    print("进程存活            : %s" % ("是" if alive else "否"))
    print("帧数                : %s -> %s"
          % (base_probe.get("frames"), end_probe.get("frames")))
    print("重建次数            : %s -> %s（尺寸变化 %d 次）"
          % (base_probe.get("recreates"), recreates, len(sizes)))
    print("惰性释放队列深度    : %s（设计上限 2）" % queue)
    print("累计释放旧资源      : %s" % released)
    print("工作集              : %.1f MB -> %.1f MB"
          % ((base_ws or 0) / 1048576.0, (end_ws or 0) / 1048576.0))
    if end_probe.get("error"):
        print("探针 error          : %s" % end_probe.get("error"))

    verdicts = []
    if not alive:
        verdicts.append("FAIL 进程已退出（崩溃）")
    if not frames_ok:
        verdicts.append("FAIL 帧数没有增长（渲染卡死）")
    if recreates == 0:
        verdicts.append("FAIL 尺寸变化但一次都没重建（回调没被触发）")
    # 每次尺寸变化最多一次重建；允许首帧额外一次。
    if recreates > len(sizes) + 2:
        verdicts.append("WARN 重建次数(%d) 明显多于尺寸变化次数(%d)，有重复重建"
                        % (recreates, len(sizes)))
    # 判据用的是「累计释放」，不是「队列深度」：队列深度恒在 2 以内，
    # 拿它跟 recreates 比会得出永远成立的假泄漏结论。
    expected_released = max(0, recreates - 2)
    if released < expected_released - 1:
        verdicts.append("FAIL 累计释放(%s) 少于重建数(%d) - 2，旧 shared texture 在泄漏"
                        % (released, recreates))
    if queue > 2:
        verdicts.append("FAIL 惰性释放队列深度 %s 超过设计上限 2" % queue)
    if (end_ws or 0) > (base_ws or 0) + 80 * 1048576:
        verdicts.append("WARN 工作集增长超 80 MB，需要进一步确认是否泄漏")

    if verdicts:
        for v in verdicts:
            print(v)
    else:
        print("PASS 尺寸抖动下重建/退役成对，渲染持续，内存未见异常增长")

    kill_all()
    log.close()
    return 1 if any(v.startswith("FAIL") for v in verdicts) else 0


if __name__ == "__main__":
    sys.exit(main())
