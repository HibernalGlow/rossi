"""Gate A 长时间浸泡：只跑不折腾，检查有没有随时间累积的泄漏或性能衰减。

和 stress_probe.py 的区别：
    stress_probe 用密集 resize 逼出「资源创建/销毁不成对」的问题；
    soak 什么都不做，只让渲染持续跑，看是否有缓慢累积 —— 这类泄漏在
    短暂测试里完全看不出来，往往要几分钟后才表现为显存耗尽或掉帧。

判据：
    1. 工作集在工作前 20 秒定型后，不应再单调爬升。
    2. 帧速率（每采样区间的增量 / 区间秒数）不应持续下降。
    3. releasedTotal 与 recreates 应保持配对，惰性队列深度应恒 <= 2。

用法：
    python soak_probe.py [总秒数=90] [采样间隔秒=10]
"""

import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import stress_probe as sp  # noqa: E402  复用清理/内存/统计读取


def main():
    total = float(sys.argv[1]) if len(sys.argv) > 1 else 90.0
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0

    if not sp.kill_all():
        print("FAIL 无法清理残留实例")
        return 2
    if os.path.exists(sp.WGOU_STATS):
        os.remove(sp.WGOU_STATS)

    exe = os.path.join(sp.DEBUG_DIR, sp.EXE_NAME)
    log = open(os.path.join(HERE, "..", "soak-run.log"), "wb")
    proc = subprocess.Popen([exe], cwd=sp.DEBUG_DIR, stdout=log, stderr=log)

    samples = []
    start = time.time()
    time.sleep(6.0)  # 让 tex/init 全部完成，避免把初始化开销算进趋势

    while time.time() - start < total:
        data = sp.read_stats()
        probe = sp.probe_of(data)
        ws = sp.working_set(proc.pid)
        t = time.time() - start
        row = {
            "t": t,
            "frames": probe.get("frames") or 0,
            "recreates": probe.get("recreates") or 0,
            "queue": probe.get("retired") or 0,
            "released": probe.get("releasedTotal") or 0,
            "ws": (ws or 0) / 1048576.0,
            "size": "%sx%s" % (probe.get("width"), probe.get("height")),
        }
        samples.append(row)
        rate = ""
        if len(samples) >= 2:
            dt = row["t"] - samples[-2]["t"]
            df = row["frames"] - samples[-2]["frames"]
            dr = row["recreates"] - samples[-2]["recreates"]
            rate = "  帧速率=%.0f fps  重建增量=%d" % (
                df / dt if dt > 0 else 0, dr)
        print("t=%5.1fs  帧=%-6s 尺寸=%-10s 重建=%-4s 队列=%s 累计释放=%-4s "
              "工作集=%.1f MB%s"
              % (row["t"], row["frames"], row["size"], row["recreates"],
                 row["queue"], row["released"], row["ws"], rate))
        time.sleep(interval)

    alive = [ln for ln in sp.instances() if str(proc.pid) in ln]
    sp.kill_all()
    log.close()

    verdicts = []
    if not alive:
        verdicts.append("FAIL 进程已退出（崩溃）")

    # 内存：取后半段的最小/最大值，爬升超过 15% 才算可疑。
    tail = [s["ws"] for s in samples[len(samples) // 2:]]
    if len(tail) >= 2 and min(tail) > 0:
        growth = (max(tail) - min(tail)) / min(tail)
        if growth > 0.15:
            verdicts.append("WARN 后半段工作集波动 %.1f%%，疑似缓慢累积"
                            % (growth * 100))

    # 帧速率：比较前半段与后半段的平均速率，掉一半以上算衰减。
    rates = []
    for i in range(1, len(samples)):
        dt = samples[i]["t"] - samples[i - 1]["t"]
        df = samples[i]["frames"] - samples[i - 1]["frames"]
        if dt > 0:
            rates.append(df / dt)
    if len(rates) >= 4:
        head = sum(rates[:len(rates) // 2]) / (len(rates) // 2)
        tailr = sum(rates[len(rates) // 2:]) / (len(rates) - len(rates) // 2)
        print("")
        print("前半段平均帧速率 %.0f fps -> 后半段 %.0f fps" % (head, tailr))
        if head > 0 and tailr < head * 0.5:
            verdicts.append("FAIL 帧速率衰减超过一半（%.0f -> %.0f）"
                            % (head, tailr))

    last = samples[-1] if samples else {}
    if last.get("queue", 0) > 2:
        verdicts.append("FAIL 惰性释放队列深度 %s 超过上限 2" % last.get("queue"))
    if last.get("released", 0) < max(0, last.get("recreates", 0) - 2) - 1:
        verdicts.append("FAIL 累计释放(%s) 少于重建数(%s)-2，存在泄漏"
                        % (last.get("released"), last.get("recreates")))

    print("")
    print("=== 结果 ===")
    distinct = sorted({s["size"] for s in samples})
    print("观测到的 texture 尺寸: %s" % ", ".join(distinct))
    bursts = []
    for i in range(1, len(samples)):
        dr = samples[i]["recreates"] - samples[i - 1]["recreates"]
        if dr > 2:
            bursts.append((samples[i - 1]["t"], samples[i]["t"], dr,
                           samples[i - 1]["size"], samples[i]["size"]))
    if bursts:
        print("检测到无外部 resize 的自动化重建突发：")
        for a, b, dr, sa, sb in bursts:
            print("  t=%.0f~%.0fs 重建 +%d 次（尺寸 %s -> %s）"
                  % (a, b, dr, sa, sb))
    if verdicts:
        for v in verdicts:
            print(v)
    else:
        print("PASS 长时间运行下帧速率稳定、内存无累积、资源释放配对")
    return 1 if any(v.startswith("FAIL") for v in verdicts) else 0


if __name__ == "__main__":
    sys.exit(main())
