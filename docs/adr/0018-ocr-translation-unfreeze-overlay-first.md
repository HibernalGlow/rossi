# OCR 翻译解冻（草案：**尚未生效**）

> **状态：草案 —— 未批准。** ADR-0008 的冻结线**仍然有效**，`docs/ROADMAP.md` 的冻结表未改，
> `CONTEXT.md` 的「OCR 翻译」条仍写着「不在 v0.1」。
> 本文件在批准前不产生任何代码许可：**批准的动作就是 §「批准后要改的三处」**。
> 流程与 ADR-0016（视频解冻）相同 —— 那条也是先出 ADR、再回头改 ADR-0008 与 ROADMAP。

## 为什么要重新评估

ADR-0008 把 OCR 翻译留在冻结线外，给的理由有两条：它是**最贵的一项**（检测 + 识别 + 翻译 + 排版回填），
以及**许可约束使它不能直接抄参考实现**。当时对第二条的认知基础是：

> 能力参考 `Venera-SSR` —— 而它是 GPL-3.0，因此默认路线是「读它的问题定义 + 自行重写 + 使用公开模型」。

2026-09-25 的核实（全表见 `docs/REFERENCE_RESEARCH.md` §8.1）**推翻了这条前提**：

- 存在许可干净的整链路源码 —— `ArbenApura/xianscan-rust` 是 **MIT**，且它的推理栈与本仓**同一个库**
  （`ort` + `ndarray` + `imageproc`，ML 层不绑 GUI）。
- 之前被记成「最完整可抄 pipeline」的 Koharu **已改为 MIT OR Apache-2.0**（2026-08-14），
  但它跑在 **LibTorch** 上（`Cargo.lock` 里没有 `ort`）→ 不能当依赖，仍是架构参考。
- 「自行重写」这条默认路线的成本没有理由付：**它省的是许可证，而现在许可证已经不是障碍**。

同时核实出一个**新的、真正的**障碍，它不在代码许可证上：文本检测的公共来源
`dmMaze/comic-text-detector` 是 **GPL-3.0 且 2023-08 停更**，几乎所有 fork 的检测件都溯源自它；
以及**模型权重的再分发条款无法核实**（HF 在本机网络不可达，见 §未决）。

## 决定（待批准）

1. **只允许 `MIT / Apache-2.0 / BSD / ISC` 源码进入仓库**，作为代码来源的正面清单只有三个：
   `xianscan-rust`（MIT）、`manga-ocr-rs`（MIT）、`manga-ocr`（Apache-2.0，Python → 只作跨语言参考）。
   **显式排除**为代码来源：`comic-text-detector`、`manga-image-translator`、Yakuyomi（app 与 engine）、
   Mekuru 与 `mekuru-ocr`（AGPL）、Frank Yomik（AGPL/GPL）、Chimahon（GPL + 逆向 Google Lens 私有 blob）、
   mokuro、yomitan、`sieugene/yomikomi`（**无 LICENSE 文件** = 默认保留所有权利）。
   Koharu 与 Kototoro / Yomihon 是 **Apache-2.0 / MIT**，法律上可搬，但排除理由不同：见 §Considered Options。
   → **这与 ADR-0008 的「任何 GPL 源码不得进入本仓库」不是放松，而是把它精确化**：
   许可搁置（不预先决定改 GPL）保持不变。

2. **代码落点是新的 workspace 成员 `rust/ocr_core`，由 `windcore` 依赖；`local_core` 依赖树不变。**
   沿用 ADR-0016 的 B4 口径：`local_core` 只管归档 / 解码 / 缓存，不因为 OCR 多一个成员。
   从 XianScan 抽取时必须处理这三件事，它们的失败模式都是**静默或延迟**的：
   - `ort 2.0.0-rc.9 → rc.12`、`ndarray 0.16 → 0.17`（本仓已在 rc.12 / 0.17）；
   - `ort` 的 feature 集必须与本仓 `rust/Cargo.toml` 里那**三段互斥 cfg 精确相等**
     （Apple `coreml` / Windows `directml` / 其余留空）。不匹配时 build script 只打一行 debug 就返回，
     症状推迟到链接期 `LNK2019: unresolved external symbol OrtGetApiBase`；
   - XianScan 的 `panic = "abort"` profile **不得带入**本仓：windcore 与 Flutter 的 panic 边界由 FRB 处理，
     abort 会把插件运行时的可恢复错误变成进程退出。
   取上游用**直接 git 依赖钉 `rev`**（像本仓对 `rquickjs-sys` 那样），不用 `cargo add`、也不新增
   `[patch.crates-io]`：Phase 0 spike 实测 `[patch]` **只在它所在的 workspace 根生效、作 path 依赖时不传递，
   且症状静默**（父 workspace 解析到 crates.io 最新版而不报错，见 `docs/phase0-vendor-spike.md` §2）。
   而 crates.io 上 `manga-ocr 0.5.1` / `lama 0.5.1` / `comic-text-detector 0.5.1` 是 Koharu
   **改许可之前**发布的，`license-file` 指向一份 GPL-3 文本。

3. **运行时形态是 overlay-first：译文是页面上的叠加层，不回写像素。**
   理由不是省事，而是**保护 v0.1 唯一的硬指标**：判据 C 测的是「翻页 + 静态图渲染」的 `p95 / p99`。
   把 OCR 做成 ADR-0008 占位② 的那个「页后处理」像素变换位，等于让一条 GPU 推理链插进渲染路径 ——
   解冻 OCR 就会顺手破坏冻结线的验收。因此：
   - OCR 是**页外异步任务**，产出「块 + 文本 + 框」的页侧记录（schema 参照 Mekuru 的 `mokuro_models.dart`：
     `box` / `vertical` / `font_size` / `lines_coords` / `lines`）；
   - 显示走叠加层：默认「按住窥视」（跟随指针的圆形放大区显示译文渲染，页角一个点表示本页状态
     进行中/就绪/失败，译文未到时按住在放大区里给出**空环** —— 见 `REFERENCE_RESEARCH.md` §8.5），
     以及一个**逐页**的整页叠加开关；
   - **擦字（LaMa inpaint）与排版回填不在本 ADR 范围内**，它需要自己的一版 ADR ——
     因为「回填要先把原字擦干净」会引入像素改写，那才是真正接进「页后处理」位的时刻。

4. **模型一律首次使用时下载，不随包分发**，沿用仓库既有口径（RealSR / waifu2x：首下后解压到
   `getFilePath()/super_resolution/`，见 `lib/page/setting/real_sr/service/real_sr_super_resolution.dart:71`；
   OCR 用同级新目录 `manga_ocr/`，**不复用** `super_resolution/` —— 那里的「整目录删除」清理逻辑会连带废掉另一条引擎）。
   这条同时是本 ADR 对「权重条款未核实」的处置：
   不分发权重 → 不分发其再分发义务。XianScan/manga-ocr-rs 的**编译期拉模型**（`build.rs` curl ~441 MB）
   是必须去掉的反模式：它会打断离线与交叉编译 CI。

5. **平台：Windows + macOS 同期（ADR-0006），Linux 顺带；Android / iOS 明确不做端侧 OCR。**
   排除的理由要说清，它不是「以后补」：本仓 `ort` 的 linux/android 那段**没有任何加速器 EP**
   （`std` + `ndarray` + `download-binaries` + `tls-rustls`，特性集必须与预编译发行包精确相等，
   见 `rust/Cargo.toml` 里那段注释）= **CPU only**；
   而 manga-ocr 是 fp32 ViT + BERT（~441 MB），移动端要可用得先做 int8 / QDQ 重导出
   （Yakuyomi 为了在 ORT 上跑把识别压到 48 px CTC int8，是另一条工程量）。
   这与「移动端只做最低适配、不参与任何验收」一致。

6. **翻译本身不进 Rust**：走已有的 `reqwest`（Dart 侧 `WindHttp`）到 OpenAI-compatible 端点或本地 Ollama。
   Rossi 不内置 NMT 模型 —— 那是「检测/识别/擦字/回填」之外的第五个模型族，且端侧翻译质量对漫画
   这种短文本+口语的场景没有竞争力。

## Considered Options

- **搬 Koharu 的 crate**（`koharu-ml` / `-pipeline` 已切成干净的 workspace 成员，许可也是 MIT OR Apache-2.0）：
  否决。它需要 **LibTorch**（safetensors + libloading FFI）与 llama.cpp GGUF，等于在已经跑通的
  `ort` + CoreML/DirectML 旁边再养一个体积与交叉编译成本都更高的推理栈；且 iOS 上 libtorch 基本无法分发。
  它的价值在**分层与竖排排版回填**，那部分照 §8.4 读。
- **只读 Venera-SSR 自行重写**（ADR-0008 的默认路线）：否决。核实后存在 MIT + 同栈的现成整链路，
  「自行重写」省的是许可证而不是时间，而许可证已经不是障碍。
- **搬 Kototoro / Yomihon**（两者 Apache-2.0，法律上可搬）：否决为代码来源 —— 它们是 Kotlin/Android，
  到 Rossi 是 Flutter/Dart + Rust，搬运=重写；保留为 **overlay 与逐页状态机**的结构参考（§8.5）。
- **Mekuru 式自托管 OCR 服务**（AGPL 的 Python FastAPI）：否决。给一个「个人自用、离线可读本地漫画」的
  应用加一个必须另起的 server，与产品形态相反；AGPL 的网络条款也覆盖这条路线。
- **现在就决定把 Rossi 改为 GPL-3.0** 以换回源码自由度：否决，维持 ADR-0008 的「许可搁置」。
  值得记一笔的是：这个开关**至今仍未被 OCR 拨动过** —— 解冻靠的是 MIT 来源，不是靠换许可证。
- **把 OCR 直接做成像素级页后处理**（一步到位出「擦字+回填」的成品页）：否决，见 §决定 3。

## 批准后要改的三处

1. `docs/ROADMAP.md` 冻结表第 16 行：「参考实现是 GPL，只能读不能抄」→ 改为「代码来源 MIT 白名单，
   见 ADR-0018；overlay-first，擦字回填另开 ADR」。
2. `docs/adr/0008-v0-1-scope-freeze-and-placeholders.md` 的 §许可搁置：追加 ADR-0018 例外（照 ADR-0016 那段写法），
   并保留「任何 GPL 源码不得进入本仓库」。
3. `CONTEXT.md`：「OCR 翻译」条把能力参考从单指 `Venera-SSR` 改为 `xianscan-rust`（代码）+
   Yomihon/Kototoro（overlay UI）+ Frank Yomik（交互）；**许可边界节**的「只能读不能抄」清单补上
   `comic-text-detector` / `manga-image-translator` / Mekuru / Frank Yomik / Chimahon / mokuro / yomitan。

## Consequences

- **「最贵的一项」仍然最贵。** 本 ADR 只解决「能不能抄」，不解决工作量：检测 + 识别 + 翻译 + 叠加渲染
  四段，加上模型管理，再加上**叠加层与缩放/平移的坐标对齐** —— 最后一项是新增的一致性要求，
  不是实现细节（大幅面页分块解码时叠加层会跑位，Chimahon 为此专门写了 subsampling 视图与坐标映射器）。
- **判据 A–E 不变**，但新增一条要进验收的约束：**开 OCR 时翻页帧时间不得劣化**
  （叠加层的命中测试与每帧 clip 成本）。若做不到，退化方案是「OCR 只在静态停手时渲染」。
- **不进入本 ADR 的东西要写明**，否则范围会顺溢：擦字（inpaint）、排版回填、上色、
  词取字典（Yomihon 那种 tap-lookup）、移动端端侧 OCR、以及任何随包分发的权重。
- **占位②（页后处理位）仍然不实现**：overlay 是叠加层不是像素变换，因此本 ADR **不**把那个位固化进公开接口 ——
  这正是 ADR-0008 原本想要的效果（先别定型），现在它仍然成立。

## 未决（批准本 ADR 前需要先定的）

1. **权重再分发条款核实不了**：`huggingface.co` 与 `hf-mirror.com` 在本机网络不可达。
   未核：`konojonatatan/manga-ocr-base`、`mayocream/lama-manga`、`ogkalu/lama-manga-onnx-dynamic`、
   RF-DETR 的 Manga109 衍生条款。已知风险：manga-ocr 自述训练集含 **Manga109-s（学术条款、限制再分发）**。
   §决定 4（不随包分发）是**处置**，不是答案。
2. **manga-ocr 的 ONNX 导出能否在 CoreML EP 上跑**无任何证据（manga-ocr-rs 未测过非 CPU EP；
   它自报 ~1.8–2.0 s/裁剪块，CPU）。Apple 侧要验的是 encoder/decoder 的算子回退表，不是性能数字。
3. **检测件选哪个**：RF-DETR Seg（XianScan/Koharu 同源，上游 Apache 但权重含 Manga109）
   vs PP-OCR det（Apache-2.0，但为文档页训练，漫画气泡召回未知）vs Apple Vision（免模型、非跨平台）。
4. 「个人自用」是否继续作为唯一分发形态（ADR-0006）—— 若哪天要分发，权重这一项会立刻从「未决」变成「阻塞」。
