# -*- coding: utf-8 -*-
"""三格式全页扫描：scale_probe 对归档每一页跑全尺寸解码，汇总成对照表。

用法：
  python format_sweep.py --probe <scale_probe.exe> --dir D:/1Dev/tmp \
      --base "G44不会受伤 八奈见杏菜（泳装）"

对四种组合各扫一遍归档全部页：
  jpeg / avif / jxl(oxide) / jxl(libjxl)
每页取 --rounds 2 的最小「全尺寸解码ms」，输出逐页表 + 汇总，并写 JSON。
"""
import argparse
import json
import re
import subprocess
import sys
import time

FULL_ROW = re.compile(r"全尺寸（基线）\s+([\d.]+)\s+([\d.]+)")


def probe_decode_ms(probe, archive, index, backend, rounds=2):
    cmd = [probe, archive, str(index), "--rounds", str(rounds)]
    if backend:
        cmd += ["--jxl-backend", backend]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=120)
    m = FULL_ROW.search(r.stdout)
    if not m:
        raise RuntimeError(f"no full row: idx={index} backend={backend}\n{r.stdout[-800:]}\n{r.stderr[-400:]}")
    return float(m.group(1)), float(m.group(2))  # 解码ms, 装箱ms


def sweep(probe, archive, backend, rounds, page_count=None):
    # 先跑一次拿页数
    out = subprocess.run([probe, archive, "0", "--rounds", "1"], capture_output=True,
                         text=True, encoding="utf-8", errors="replace", timeout=120)
    if page_count is None:
        m = re.search(r"页数\s*:\s*(\d+)", out.stdout)
        page_count = int(m.group(1))
    rows = []
    for i in range(page_count):
        t0 = time.perf_counter()
        try:
            dec, pack = probe_decode_ms(probe, archive, i, backend, rounds)
            rows.append({"index": i, "decode_ms": dec, "pack_ms": pack})
            print(f"  idx={i:2d}  {dec:8.1f} ms  (wall {time.perf_counter()-t0:.1f}s)", flush=True)
        except Exception as e:
            rows.append({"index": i, "error": str(e)[:200]})
            print(f"  idx={i:2d}  ERROR {e}", flush=True)
    return rows


def summarize(name, rows):
    ok = [r["decode_ms"] for r in rows if "decode_ms" in r]
    return {"name": name, "pages": len(rows),
            "sum_ms": round(sum(ok), 1), "mean_ms": round(sum(ok) / len(ok), 1) if ok else None,
            "max_ms": round(max(ok), 1) if ok else None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--json", default=None)
    a = ap.parse_args()

    combos = [
        ("jpeg", f"{a.dir}/{a.base}.cbz", None),
        ("avif", f"{a.dir}/{a.base}avif.cbz", None),
        ("jxl-oxide", f"{a.dir}/{a.base}jxl.cbz", "oxide"),
        ("jxl-libjxl", f"{a.dir}/{a.base}jxl.cbz", "libjxl"),
    ]

    result = {}
    for name, archive, backend in combos:
        print(f"===== {name} =====", flush=True)
        rows = sweep(a.probe, archive, backend, a.rounds)
        result[name] = {"archive": archive, "rows": rows, "summary": summarize(name, rows)}
        s = result[name]["summary"]
        print(f"  >> {s['pages']} pages  sum={s['sum_ms']} ms  mean={s['mean_ms']} ms  max={s['max_ms']} ms", flush=True)

    print("\n===== 逐页对照（全尺寸解码 ms）=====")
    hdr = f"{'idx':>4} {'jpeg':>9} {'avif':>9} {'oxide':>9} {'libjxl':>9}  libjxl/avif"
    print(hdr)
    jrows = result["jpeg"]["rows"]; arows = result["avif"]["rows"]
    orows = result["jxl-oxide"]["rows"]; lrows = result["jxl-libjxl"]["rows"]
    for i in range(len(jrows)):
        def d(rs): return f"{rs[i]['decode_ms']:9.1f}" if "decode_ms" in rs[i] else "    ERR "
        if "decode_ms" in arows[i] and "decode_ms" in lrows[i]:
            ratio = f"{lrows[i]['decode_ms']/arows[i]['decode_ms']:.2f}x"
        else:
            ratio = "  -"
        print(f"{i:4d} {d(jrows)} {d(arows)} {d(orows)} {d(lrows)}  {ratio:>10}")

    print("\n===== 汇总 =====")
    for name, _ in combos:
        print(result[name]["summary"])

    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=1)
        print(f"\nJSON -> {a.json}")


if __name__ == "__main__":
    main()
