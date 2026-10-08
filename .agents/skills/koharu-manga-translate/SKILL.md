---
name: koharu-manga-translate
description: 用 koharu 的无头 CLI 把整本漫画 / doujin（zip 或页目录）翻成中文，跑在远端 Windows 的 NVIDIA 机器上（CUDA），翻译走本机 llama-server（Murasaki）或任意 OpenAI 兼容 API（DeepSeek）。Use when 用户丢一个漫画压缩包说「翻译这本」、要求用 koharu 翻图、指定 Murasaki / 千问 / DeepSeek 当翻译模型、要续跑漏掉的页、或要比较几个翻译模型在漫画上的速度与质量。
---

# 漫画整本翻译（koharu headless + 远端 GPU）

## 一句话流程

zip → scp 到 Windows `D:\book\src` → 起 `llama-server`（CUDA，`-ngl 99`，挂 Murasaki）→ 逐页
`run.exe --provider openai-compatible --base-url http://127.0.0.1:8080/v1 --llm murasaki --response-format json-schema`
→ 拉回成品 → 放回导出目录并命名成 `原名[koharu-translate].zip`。

实测节奏：**约 8–13 s/页**（2560×3628 的页，4060 Laptop），40 页整本约 6–8 分钟。

## 前置状态（先核对，缺哪块补哪块）

| 东西 | 落点 | 来路 |
|---|---|---|
| Windows 机 | `ssh 30902@100.122.176.77`（Tailscale；连不上先让用户开 Tailscale） | — |
| `run.exe`（koharu 无头 CLI） | `D:\koharu-run\run.exe` | fork `HibernalGlow/koharu` 分支 `ci/koharu-cli` 的三平台 CI 产物 |
| `llama-server.exe`（CUDA） | `D:\llama\llama-server.exe` | llama.cpp `bNNNN-bin-win-cuda-12.4-x64.zip` + `cudart-…-cuda-12.4-x64.zip` |
| 翻译模型 | `D:\murasaki.gguf`（Murasaki-4B-v0.3 Q4_K_M）、`D:\qwen.gguf` | 从 Mac 送过去（局域网 HTTP） |
| koharu 自己的模型 | `D:\koharu-cache\Koharu\packages\hugging-face\models\…` | 从 Mac 的 `~/Library/Caches/Koharu/packages` 同结构搬 |
| 运行时包 | `…\packages\{llama,diffusion,torch}\<release>\<variant>\` | `github.com/koharu-rs/{llama,torch,diffusion}` 的 releases |

store 根是 `dirs::cache_dir()/koharu/packages`，Windows 上走 KnownFolder、**不读 `LOCALAPPDATA`**；
C 盘小就用 junction 挪走：`mklink /J C:\Users\30902\AppData\Local\koharu D:\koharu-cache\Koharu`。

## 步骤

1. **传书**：`scp '<本地 zip>' '30902@…:D:/book/book.zip'`（目标**必须正斜杠**；反斜杠会 rc=0 但文件不在）。
   Windows 侧解开：`ssh … "mkdir D:\book\src & tar -xf D:/book/book.zip -C D:/book/src"`。
2. **挑对比页/确认页类型**：先在 Mac 上出全本缩略图 `magick montage $(ls *.webp | sort -V) -tile 8x -geometry 190x+3+3 out.png`，
   **很多页是纯插图没有文字**，拿那种页做质量对比会得出错误结论。有台词的一般是中段。
3. **起服务（一次，整本共用）**：`llama-server -m D:\murasaki.gguf -ngl 99 -c 8192 --host 127.0.0.1 --port 8080 --alias murasaki`，
   轮询 `/health` 到 200 再开跑。
4. **逐页跑**：用 `references/book-runner.ps1`（可续跑：输出存在就 SKIP）。
5. **拉回**：逐文件 `scp`（单文件几 MB，稳）；别指望一次传几百 MB。
6. **命名放回**：原名不改，只在扩展名前追加标签 —— `(C108)_[…]_ザリンちゃんは清楚なんですから[koharu-translate].zip`。

## 必踩的坑（全部实测过，别重新发现）

- **`--response-format json-schema` 是刚需**，不是可选：`json-object` 下模型会自己编键名
  （Murasaki 写 `translation`，koharu 解析要 `text` ⇒ `missing field 'text'`）。llama.cpp 把 schema 编成
  GBNF 强制形状，加上立刻 rc=0。
- **`KOHARU_SECRET_OPENAI_COMPATIBLE` 必须设成任意非空值**：SSH 会话在 Windows **session 0**，
  读凭据管理器报 `ERROR_NO_SUCH_LOGON_SESSION`，不设这个变量整条链起不来（本地端点也要设）。
- **千问 3.5-4B-uncensored 在这条路上不可用**：它自问自答烧满上下文（7822 tokens，`truncated=1`），
  最后吐空 ⇒ `EOF while parsing a value`。要救得加大 `-c` 或压掉 thinking。
- **大文件别用 scp**：`python3 -m http.server`（Mac 侧绑 Tailscale IP）+ 远端 `curl -C - --retry 5`，实测 15+ MB/s。
  但**每个文件必须给不同的本地文件名** —— 同名 + `-C -` 会让后一个接着前一个续传，拼出一个
  「能解包但内容是错的」归档。
- **GitHub 在 Windows 侧时好时坏**（scoop / curl 都撞过 TLS 握手失败）：能用的代理是它本机的
  `127.0.0.1:7890`（通 GitHub、不通 huggingface.co）。HF 上的权重一律从 Mac 搬。
- **PS 5.1 三连**：脚本必须 **ASCII-only**（含中文注释会整脚本不执行）；数组字面量**末尾不能有逗号**；
  `start /b` / `Start-Process -WindowStyle Hidden` 在 SSH 会话里**留不下进程**，长任务要**把 SSH 会话挂着**跑
  （`-o ServerAliveInterval=30`）。
- **退出期崩溃很常见**：日志里 `rc=-1073741819`（0xC0000005）但**图已经正常写出**；真缺页重跑那一页即可
  （脚本可续跑，SKIP 已存在的）。
- 拉回后**逐项验收**：页数对不对、尺寸与原页是否一致、挑一张有台词的页用眼睛过一遍
  （气泡内文字、竖排方向、有没有出框、拟声词是否按设计不翻）。

## 参数速查

```
--target-language zh-Hans                     目标语言
--ocr  paddleocr-vl-1.6 | manga-ocr | …       识别档（默认 paddleocr-vl-1.6）
--inpainting lama | aot-inpainting | …        擦字档（默认 lama）
--provider local | openai-compatible          翻译后端
--base-url https://api.deepseek.com/v1        端点（在线示例；本机是 http://127.0.0.1:8080/v1）
--llm murasaki | deepseek-flash               端点上的模型名
--response-format json-schema|json-object|none  本地模型一律 json-schema
```

在线 API（DeepSeek）走 `KOHARU_SECRET_OPENAI_COMPATIBLE=<key>`；DeepSeek 只认 `json-object`。
速度对照：Mac+DeepSeek 约 108 s/页，Win4060+Murasaki 约 19 s/页 ⇒ 本地优先。

## 参考

- `references/book-runner.ps1` —— 整本循环（起服务、逐页、可续跑）的成品脚本。
- fork 上的补丁说明见 `references/fork-patch.md`（改了什么、为什么、怎么和上游同步）。

## 三个「字太小」的旋钮（2026-10-08 实测）

1. **先砍译文长度**（零重建、立竿见影）：加 `--translation-instructions "只输出译文本身。不要添加任何注释、解说、括注、读音说明、译者注或原文；不要保留日文假名；不要解释词义。"`
   —— 模型爱在译文里塞 `（注：イッてる意为做爱）` 这种括注，一条台词能撑长一倍，排版只能缩字号。
   实测同一格：去掉注释后字号肉眼可见地大了一档。
    ⚠️ Windows 上这条中文指令**不能直接写进 `.ps1`**（PS 5.1 按 ANSI 读、会整脚本不解析）：把指令存成 UTF-8 的 `D:\book\instr.txt`，脚本里 `$instr = (Get-Content ... -Raw -Encoding UTF8).Trim()` 再传给参数。
2. **再抬可读性下限**：`%USERPROFILE%\.koharu\config.toml` 写
   ```toml
   [typesetting]
   min_font_size = 32
   ```
   排版逻辑是「在 `[min_font_size, 自动上限]` 里找能放下的最大字号，放不下就掉到下限」，默认 9.0。
   这个字段是 fork 加的（`crates/koharu-renderer/src/config.rs` + `renderer.rs`，默认值与上游等价），
   读的是 `config.toml`、带热重载，**不用改命令行**。实测 32 在全页尺度上仍不出框。
   调参顺序：先 24 → 看是否越框 → 不够再加；越小越贴框、越大越可能压到画面。
3. **框外小字（旁白/拟声/裸字）要「保证字号」就设强制字号**：同一段 `[typesetting]` 里写 `font_size = 64` ——
   设了就**关掉自动适配**，按这个字号渲染，放不下也照放（栅格化那层**不裁切文字**，溢出是看得见的）。
   - **为什么非要这一档**：`text_renderer.rs` 的 `automatic_maximum()` 对**非气泡文字**硬编码返回 `24.0`，
     而 `minimum = min_font_size.min(maximum)` —— 所以那类字的下限被上限掐死，`min_font_size` 抬到 56/200 都**没有任何效果**（27 页实测两轮，1:1 裁切像素完全一致）。只有 `font_size` 能救。
   - **为什么不能对气泡也强制**：21 页实测 `font_size = 64` 会把气泡里的字撑到画面上。
     气泡的自动上限本来就是气泡高度，强制它只会溢出 —— 所以 fork 按 `is_bubble` 分流：
     **旁白/裸字吃 `font_size`，气泡保留上游的自动适配**（提交 `c615631`）。
   - 2560 px 宽的页面上 64 ≈ 页宽的 2.5%，是「能读」的量级；上游那个 24 只有 0.9%。
   - `min_font_size` 与 `font_size` 的分工：前者是「仍尽量在框内、只是不许缩到看不清以下」（最坏才溢出）；
     后者是「不管框，保证字号」（出框是常态）。

## 换字体（比如霞鹜文楷屏幕阅读版）

`[typesetting] font_families = ["<家族名>"]` 本身是热重载的，但**能不能命中是另一回事**，两条都会踩：

1. **per-user 装的字体 koharu 永远看不见。** Windows 上 koharu 走 `fontique` 0.11.1，
   其 `src/backend/dwrite.rs:54` 是 `DWriteSystemFonts::new(false)`，这个 `false` 就是
   `IDWriteFactory::GetSystemFontCollection` 的 `includeCustomCollections` 参数 ——
   **写死排除自定义/按用户集合**。所以丢进 `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + 写 `HKCU\...\Fonts` 一律无效，
   而且失败是**静默回退**到兜底黑体（不是 sans 就是没命中，1:1 裁切看笔画对比即可判定）。
   能生效的落点是**机器级字体表**，文件不必放 `C:\Windows\Fonts`，指哪都行：
   ```
   reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" /v "LXGW WenKai GB Screen (TrueType)" /t REG_SZ /d "D:\fonts\LXGWWenKaiGBScreen.ttf" /f
   ```
   回退：`reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" /v "LXGW WenKai GB Screen (TrueType)" /f`。
   改完要**新进程**才读得到（字体集合按进程建立）；SSH 进来的会话在这里是完整管理员令牌，`HKLM` 写得进去。
2. **别照文件名猜家族名。** 用 GDI 读一次内嵌名再决定配置里写什么：
   `PrivateFontCollection.AddFontFile(...)` → `Families[0].Name`。
   `LXGWWenKaiGBScreen.ttf` 的 name ID 1 其实是中文「霞鹜文楷 GB 屏幕阅读版」；
   fontique 会把 `GetFamilyNames()` 的**全部本地化名**注册成别名（`dwrite.rs:56-64`），
   所以中英文名都能命中。控制台是 GBK，中文家族名打出来是乱码，别被误导。
3. **别指望它自带。** koharu 的字体档是运行时从 HF dataset `mayocream/fonts` 拉的 `index.json`
   （本机在 `%LOCALAPPDATA%\koharu` 的 junction 目标下），实测 640 个家族里**没有 LXGW / 霞鹜文楷**，
   楷体系只有 Adobe 楷体 Std、方正楷体_GBK、華康正顏楷體 这些。要走它自己的下载链路就得换个家族名。

