#!/usr/bin/env python3
"""本地翻译模型对表：同一批真页台词，逐系统跑一遍，记下译文 / 延迟 / 吞吐。

为什么用 llama-server 而不是 llama-cli：
1. 一次加载模型跑完整批，延迟数才是「阅读器里每块一次的代价」，不然每条都含加载时间；
2. **它本身就是 OpenAI-compatible 端点** —— 测出来的东西直接就是 app 里能用的形态
   （把 baseUrl 指过来就行），不会测完发现要另写一套集成。

公平性：每个系统用**它自己文档推荐的**提示词与采样参数（照抄模型卡，不自己发挥），
并固定 seed。同一模型的「带术语块 / 不带」是唯一的受控对 —— 那才是术语表这一档的净效应。
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
# 权重**不放仓库里**（一个 1.3 GB 的 gguf 进了工作树，随时会被谁的一次 `add -A` 连带提交进去）。
# 默认落在应用自己下载模型的那个目录（见 _app_model_dir），跟 OCR 权重、超分权重同一个去处；
# 要指到别处就 `MT_MODELS=/你的目录 python3 docs/mt-bench/mt_bench.py ...`。
def _app_model_dir() -> Path:
    """应用自己下载模型会落到的地方 —— 与 `getFilePath()/manga_ocr/`、`super_resolution/` 同级。

    以前这里默认 `docs/mt-bench/models/`，那份权重得单独复制一次；
    结果就是「跑基准前要先记一个仓外路径」，重装机器后没人知道去哪儿找回它。
    """
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "com.zephyr.breeze" / "files"
    elif sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", "")) / "com.zephyr.breeze" / "files"
    else:
        base = Path.home() / ".local" / "share" / "com.zephyr.breeze" / "files"
    return base / "mt_bench_models"


MODELS = Path(os.environ.get("MT_MODELS") or _app_model_dir())
CORPUS = json.loads((HERE / "corpus.json").read_text())

MANGA_INSTRUCTION = (
    "Translate the following text from Japanese into Simplified Chinese as natural, "
    "concise manga dialogue. Preserve specific nouns, exact meaning, speaker intent, "
    "tone, punctuation, and sound effects. Output only the translated result without "
    "any explanation:\n\n"
)
# 模型卡里给的术语块示例格式：`<原文>对应“<译文>”`，中文写，指令保持英文。
MANGA_GLOSSARY = (
    "Reference the following manga translations:\n"
    "危機契約对应“危机契约”\n"
    "ナナ对应“娜娜”\n"
    "リーリィ对应“莉莉”\n"
    "ノラボス对应“野良波”\n\n"
)
BASE_INSTRUCTION = "将以下文本翻译为 `简体中文`，注意只需要输出翻译后的结果，不要额外解释：\n\n"

# 思考块的两端（官方客户端 `strip_think` 用的是同一对）。
THINK_OPEN = "<" + "think>"
THINK_CLOSE = "<" + "/think>"

# Index-Translate 的**官方 canonical 提示**（照 `inference/llm/translate.py::trans_prompt`
# 逐字抄，不自己发挥）：无约束时是「请将以下{源}文本翻译为{目标}，直接输出翻译结果，
# 不要进行任何解释」；带约束时换成【源文】/【约束要求】那套 instTrans 训练格式，
# 术语表落成 `专名/术语对照: A→B、C→D` 一条硬性要求。
INDEX_PLAIN = (
    "请将以下日语文本翻译为简体中文，直接输出翻译结果，不要进行任何解释。\n\n"
)
INDEX_CONSTRAINT = (
    "请将以下日语文本翻译成简体中文，并且严格遵循所有约束要求。\n\n"
    "【源文】\n{text}\n\n"
    "【约束要求】\n1. 【硬性要求】专名/术语对照: "
    "危機契約→危机契约、ナナ→娜娜、リーリィ→莉莉、ノラボス→野良波\n\n"
    "只输出译文，不要有任何额外说明。"
)

SYSTEMS = {
    "hymt2-1.8b-base": {
        "file": "hymt2-1.8b-base.gguf",
        "instruction": BASE_INSTRUCTION,
        "sampling": ["--temp", "0", "--seed", "1"],
    },
    "hymt2-1.8b-manga": {
        "file": "hymt2-1.8b-manga-zh.gguf",
        "instruction": MANGA_INSTRUCTION,
        "sampling": ["--temp", "0.15", "--top-k", "20", "--top-p", "0.6",
                      "--min-p", "0.0", "--repeat-penalty", "1.05", "--seed", "1"],
    },
    "hymt2-1.8b-manga+术语": {
        "file": "hymt2-1.8b-manga-zh.gguf",
        "instruction": MANGA_GLOSSARY + MANGA_INSTRUCTION,
        "sampling": ["--temp", "0.15", "--top-k", "20", "--top-p", "0.6",
                      "--min-p", "0.0", "--repeat-penalty", "1.05", "--seed", "1"],
    },
    "hymt2-7b": {
        "file": "hymt2-7b-q4.gguf",
        "instruction": BASE_INSTRUCTION,
        "sampling": ["--temp", "0", "--seed", "1"],
    },
    "sakura-7b": {
        "file": "sakura-7b-q4.gguf",
        # 留空 = 用 GGUF 内嵌的 chat template 原样发（Sakura 的提示词仓库里没写，
        # 自己编一个会把它测成另一个模型）。
        "instruction": None,
        "sampling": ["--temp", "0", "--seed", "1"],
    },
    # B站 Index-Translate-2B（apache-2.0，Qwen3.5 底座）。两档是同一份权重的受控对：
    # 差别只在「有没有按它自己的 instTrans 格式挂术语表」，与 Hy-MT2 那三行同口径。
    "index-2b": {
        "file": "Index-Translate-2B.Q4_K_M.gguf",
        "instruction": INDEX_PLAIN,
        "sampling": ["--temp", "0", "--seed", "1"],
        # 模型卡：Q4_K_M 走 `--jinja` + 显式关思考（enable_thinking=false）。
        "server": ["--jinja", "--chat-template-kwargs", '{"enable_thinking":false}'],
    },
    "index-2b+术语": {
        "file": "Index-Translate-2B.Q4_K_M.gguf",
        # instruction=None 只为了顺手把请求侧 temperature 也钉到 0（贪心可复现）；
        # 真正决定提示内容的是下面的 template。
        "instruction": None,
        "template": INDEX_CONSTRAINT,
        "sampling": ["--temp", "0", "--seed", "1"],
        "server": ["--jinja", "--chat-template-kwargs", '{"enable_thinking":false}'],
    },
}


def post(port, payload):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())


def wait_health(port, proc, budget=180):
    started = time.time()
    while time.time() - started < budget:
        if proc.poll() is not None:
            raise RuntimeError(f"llama-server 提前退出 rc={proc.returncode}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=3) as r:
                if r.status == 200:
                    return time.time() - started
        except Exception:
            time.sleep(0.6)
    raise RuntimeError("llama-server 健康检查超时")


def run_system(name, cfg, port, out_path):
    model = MODELS / cfg["file"]
    if not model.is_file():
        print(f"[跳过] {name}：没有 {model.name}")
        return
    cmd = ["llama-server", "-m", str(model), "--port", str(port), "--host", "127.0.0.1",
           # ⚠️ `--device MTL0` 是**必需**的，不是优化项：这台机器上 llama.cpp 同时列出
           # BLAS(Accelerate) 与 MTL0，不点名就走 CPU（实测 1.8B 只有 8.9 tok/s，延迟数会低一个数量级）。
           # 名字要写 MTL0 —— 写 "metal" 会 `invalid device` 直接退出。
           "--device", "MTL0", "-ngl", "99", "-c", "4096", "--no-webui",
           *cfg.get("server", []), *cfg["sampling"]]
    log = open(f"/tmp/ocr-lab/llama-{name}.log", "w")
    proc = subprocess.Popen(cmd, stdout=log, stderr=log)
    try:
        load_s = wait_health(port, proc)
        print(f"[{name}] 加载 {load_s:.1f}s，跑 {len(CORPUS)} 条…")
        rows = []
        for item in CORPUS:
            text = item["ja"]
            if cfg.get("template"):
                prompt = cfg["template"].format(text=text)
            else:
                prompt = (
                    text if cfg["instruction"] is None else cfg["instruction"] + text
                )
            t0 = time.time()
            body = {
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 220,
            }
            if cfg["instruction"] is None:
                # Sakura 的提示词没公开写在自己的仓库里 → 不自己编，改用贪心解码，
                # 至少结果是可复现的（这条要在结论里注明是「按其模板原样发」）。
                body["temperature"] = 0.0
            r = post(port, body)
            ms = int((time.time() - t0) * 1000)
            u = r.get("usage") or {}
            raw = (r["choices"][0]["message"]["content"] or "").strip()
            # 与官方客户端 `strip_think` 同一个安全网：模型自己吐思考块就剥掉。
            # 「有没有真出现思考块」单独记一格 —— 否则「enable_thinking=false 生效了」
            # 这句话在这台机器上就没有证据。
            thought = THINK_CLOSE in raw
            if thought:
                raw = raw.split(THINK_CLOSE, 1)[1].strip()
            rows.append({
                "system": name, "id": item["id"], "kind": item["kind"], "ja": text,
                "out": raw,
                "thought_block": thought,
                "ms": ms,
                "completion_tokens": u.get("completion_tokens"),
                "load_s": round(load_s, 1),
            })
            print(f"   #{item['id']:>2} {ms:>5}ms  {rows[-1]['out'][:56]}")
        with out_path.open("a", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        tot = sum(r["ms"] for r in rows)
        tok = sum(r["completion_tokens"] or 0 for r in rows)
        print(f"[{name}] 整批 {tot} ms（均值 {tot // len(rows)} ms/条），"
              f"{tok} tokens → {tok / (tot / 1000):.1f} tok/s")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        log.close()


def main():
    # 不加这个，后台跑的时候日志会整块 buffered，看不到进度（也看不出它是不是卡住了）。
    sys.stdout.reconfigure(line_buffering=True)
    which = sys.argv[1:] or list(SYSTEMS)
    out_path = HERE / "results.jsonl"
    port = 18710
    for name in which:
        if name not in SYSTEMS:
            print(f"未知系统 {name}，可选：{list(SYSTEMS)}")
            continue
        run_system(name, SYSTEMS[name], port, out_path)
        port += 1


if __name__ == "__main__":
    main()
