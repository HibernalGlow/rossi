# OCR 翻译解冻：成品页形态（**已批准** 2026-09-25）

> **状态：已批准。** 本 ADR 走的是 ADR-0016（视频解冻）同一条流程：先出 ADR，再回头改 ADR-0008 与 ROADMAP。
> 那两处**已随批准改完**（见 §「批准后要改的四处」的执行记录）。
> 解冻靠的是 **MIT/Apache 代码来源白名单**，**不是**改本仓库的许可证 ——
> ADR-0008 的「任何 GPL 源码不得进入本仓库」保持原样，**上色与 Anime4K 继续冻结**。
>
> **本文就地替代 00948185 那一稿的 overlay-first 形态**（0018 只有一份）：
> 目标形态定为**成品页**（擦除原文 + 译文回填后的整页图），叠加层不作为一期交付物。

## 为什么要重新评估

ADR-0008 把 OCR 翻译留在冻结线外，理由有两条：它是**最贵的一项**（检测 + 识别 + 翻译 + 排版回填），
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

## 决定

### 1. 代码来源白名单（精确化 ADR-0008 的「许可搁置」，不是放松）

可作为**代码来源**的只有三个：`xianscan-rust`（MIT）、`manga-ocr-rs`（MIT）、
`manga-ocr`（Apache-2.0，Python → 只作跨语言的预处理/解码参考）。

**显式排除**为代码来源：`comic-text-detector`、`manga-image-translator`、Yakuyomi（app 与 engine）、
Mekuru 与 `mekuru-ocr`（AGPL）、Frank Yomik（AGPL/GPL）、Chimahon（GPL + 逆向 Google Lens 私有 blob）、
mokuro、yomitan、`sieugene/yomikomi`（**无 LICENSE 文件** = 默认保留所有权利）。
Koharu / Kototoro / Yomihon 法律上可搬，但另有排除理由，见 §Considered Options。

### 2. 代码落点：新 workspace 成员 `rust/ocr_core`，`local_core` 依赖树不变

沿用 ADR-0016 的 B4 口径：`local_core` 只管归档 / 解码 / 缓存，不因为 OCR 多一个成员。
从 XianScan 抽取时必须处理这三件事，**它们的失败模式都是静默或延迟的**：

- `ort 2.0.0-rc.9 → rc.12`、`ndarray 0.16 → 0.17`（本仓 Cargo.lock 实际锁在 `ort 2.0.0-rc.13` / ndarray 0.17）；
- `ort` 的 feature 集必须与本仓 `rust/Cargo.toml` 里那**三段互斥 cfg 精确相等**
  （Apple `coreml` / Windows `directml` / 其余留 accelerator EP）。不匹配时 build script 只打一行
  debug 就返回，症状推迟到链接期 `LNK2019: unresolved external symbol OrtGetApiBase`；
- XianScan 的 `panic = "abort"` profile **不得带入**本仓：windcore 与 Flutter 的 panic 边界由 FRB 处理，
  abort 会把可恢复错误变成进程退出。

取上游用**直接 git 依赖钉 `rev`**（像本仓对 `rquickjs-sys` 那样），不用 `cargo add`、也不新增
`[patch.crates-io]`：Phase 0 spike 实测 `[patch]` **只在它所在的 workspace 根生效、作 path 依赖时不传递，
且症状静默**（见 `docs/phase0-vendor-spike.md` §2）。而 crates.io 上 `manga-ocr 0.5.1` / `lama 0.5.1` /
`comic-text-detector 0.5.1` 是 Koharu **改许可之前**发布的，`license-file` 指向一份 GPL-3 文本。

### 3. 交付形态：成品页，且**成品页是缓存产物而不是渲染路径的产物**

链路 = 检测 → 识别 → 翻译 → **擦字（inpaint）** → **译文回填** → 输出一张替代位图。
分工按「谁能便宜地把事做对」切：

```text
Rust（ocr_core）                     Dart（Reader）
  检测 · 识别 · 擦字 · 几何框   →     文字排版与绘制（复用 Flutter 的 shaping / Skia）
                                      ↓ Picture.toImageSync 光栅成整页
                                      ↓ 交回 Rust 编码 + 落盘
```

文字**不在 Rust 侧画**：CJK shaping 要在 Rust 里自己接 harfbuzz/swash，成本高于收益，
而 Flutter 已经带完整的中日韩整形与字体栈。Rust 侧只交「框 + 识别文本 + 译文 + 干净底图」。

**这条是保护 v0.1 唯一硬指标的关键**：判据 C 测的是「翻页 + 静态图渲染」的 `p95 ≤ 16.7 ms`。
成品页**必须落盘缓存**、渲染路径**只读缓存**，**绝不允许在翻页时同步推理**。因此：

- 产物目录：`getFilePath()/manga_translated/<key>/p<idx>.webp`（与 `super_resolution/` 同级但**独立**，
  不共用清理逻辑 —— `real_sr_super_resolution.dart:71` 那套是「整目录删」语义）；
  ⚠️ **实现落地的是 `p<idx>.png`，本条未达成，登记为后续项**（2026-09-26 复核）。三个理由，都不是「懒得改」：
  ① `dart:ui` 没有 WebP 编码器（`ImageByteFormat` 只有 png / raw*），要在 Dart 侧出 webp 只能引第三方编码器；
  ② 走本 ADR 图上那条「交回 Rust 编码」也不行到一半 —— `image` 0.25 的 WebP 编码器**只有无损**
  （`WebPEncoder::new_lossless`，没有 lossy 入口），实测同一张 827×1170 成品页
  PNG 1 200 482 B / **无损** WebP 707 680 B（省 41%，不是 lossy 那种量级）；
  ③ 真正的拦路石：呈现器 `gpu_present` 的 `image` 只开了 `["png"]` 特性
  （`rust/gpu_present/Cargo.toml:69`），换成 webp 产物后 `set_enhanced_image` 会解不开、注入被拒。
  所以要落地得同时动：依赖特性 + 一个新的过桥转码 API + 缓存文件名与 `isUsable` 的签名判据
  + **Windows 侧解码验证**（那台机器现在连不上，验不了）。省的是每页 0.49 MB 缓存，
  风险跨两个平台的解码路径 —— 按收益/风险排到后续，不在这一期硬做。
  同样的道理，图上那句「交回 Rust 编码 + 落盘」实现成了「Dart 编码 + 落盘」（`File.rename` 原子写）：
  既然不转 webp，跨语言搬 3.9 MB RGBA 只为了写文件没有收益。
- `<key>` **必须把影响产物的每一项都编进去**：译文语言、翻译端点/模型标识、术语表版本、
  检测/识别/擦字模型版本、**字体版本**、回填排版参数版本。缺任何一项都会造成
  「换了模型但页面还是旧的」这种**静默**错误（本仓在章节 key 上已经吃过同型的亏）；
- **页级回退（已实现，2026-09-26）**：`TranslatedPageCache.isUsable` 查 PNG 签名 + 结尾 `IEND` +
  体积下限，坏文件一律当「没有」→ 重算；注入前发现产物又消失了则静默回到原图（不弹错）。
  两条都有测试，且各自做过证伪（把判据换回 `exists()` 立刻红）。
- **页级回退**：原始解码图永远是真相，成品页是可失效的派生物。必须存在「本页回到原图」的开关，
  且 Reader 在产物缺失/损坏时**静默回落**到原图而不是报错。

### 3.1 擦字件按实测选：LaMa 一期，AOT-GAN 二期，EP 按**段**指定（2026-09-26 从「按模型」升级）

数据见 `REFERENCE_RESEARCH.md` §8.6（本机合成页 + 有真值，512×512）。结论与名气无关，**两个模型各赢一类区域、
且赢的地方相反**：

| 区域 | LaMa(manga) | AOT-GAN |
|---|---|---|
| 气泡内的字（底是纯白） | 干净白底 | **留下每个字格的淡彩方格残影** |
| 拟声词压在网点/速度线上 | **白垩色斑块 + 残点**，网点被抹平成糊 | 网点自然续上，几乎看不出擦过 |

- **掩膜外扩救不了 LaMa**：0 / 4 / 8 / 16 / 24 px 扫下来，原字区墨量 31.4 → 34.4 → 33.3 → 33.6 → 44.0
  （真值 28.6），**越扩越糟** → 那是模型行为，不是预处理能修的。
- **一期用 LaMa**：`lama-manga-onnx` 是 **apache-2.0**、动态尺寸（单页一把过）、且**掩膜外逐字节不变**
  （PSNR 99.00 / MAE 0.00）—— 最后这条与 §决定 3 的「原图是真相」同向。
- **AOT-GAN 记为「难区域」的二期补路，但现在不能直接用**：能跑的那份导出
  （`cwxue/aotgan-onnx-float`）**无 license 字段** → 只能评测；要随包必须自己从
  `mayocream/aot-inpainting`（**MIT** 权重）+ `researchmm/AOT-GAN-for-Inpainting`（**Apache-2.0** 实现）
  导一次 ONNX，而且它**固定 512×512** → 真实页要自己分块与拼接。
- **EP 不能按平台一刀切**：稳态中位数 LaMa = CPU **1 656 ms** / CoreML 3 825 ms（**更慢**），
  AOT = CPU 5 916 ms / CoreML **295 ms**。所以 §决定 2 里「Apple 走 coreml 段」这条默认
  **对 LaMa 不成立** → `ocr_core` 的 EP 选择必须**按模型指定**，不是全局一个档。
  ⚠️ 该表出自 Python `onnxruntime 1.30`，本仓 Rust 侧是 `ort 2.0.0-rc.13`（内嵌 ONNX Runtime **1.28.0**），
  **EP 行为不能直接搬**；这张表只回答「谁明显不该走哪个 EP」，不是可写进验收的数字。

### 3.2 识别半边：CoreML EP 同样不该用，且这份导出没有 KV cache

同一套探针（随机张量，只问「EP 接不接受 + 谁更快」，不问识别质量），Apple Silicon：

| 件 | CPU 稳态 | CoreML 稳态 | CoreML 建会话+首跑 |
|---|---|---|---|
| `encoder_model.onnx` 328 MB（ViT 基座） | **38.5 ms** | 131.2 ms | **3 367 ms** |
| `decoder_model.onnx` 112 MB | **2.2 ms**/步 | 7.4 ms/步 | 548 ms |

- **两个 EP 都能跑完，没有算子硬失败**（日志里只有 `attention_fusion` 的 V 级提示），
  但 **CoreML 在两边都更慢**，还要多付 0.5–3.4 s 的建会话成本 → §决定 3.1 那条
  「EP 按模型指定、不许一刀切」现在有独立第二次证据，不再是单点观察。
- ⚠️ **成本口径要说白**：解码器我喂的是 `decoder_sequence_length = 1`，那是**下限**。
  这份导出的输入只有 `input_ids` + `encoder_hidden_states`，**没有 `past_key_values`**
  → 自回归每多出一个 token 就把整个前缀重跑一遍，单格成本按 **O(n²)** 长，
  一句 20 token 的台词不是 20×2.2 ms。
- 这条直接解释了一个之前想不通的事实：**Yakuyomi 为什么不用 manga-ocr 而换成 48 px CTC int8**
  —— CTC 是单次前向，没有自回归循环。所以「识别件选谁」不是模型名气问题，是**推理形态**问题：
  `manga-ocr`（自回归、无 KV cache）适合逐格短文本；长台词与整页多格要重新估预算。
  **一期仍按 manga-ocr 走**（Apache-2.0、同栈、有现成导出），但 §决定 3.1 的产物体积/耗时预算
  要按「每格 = 一次 encoder + O(n²) 的 decoder」估，不能按单 token 报。

### 3.3 检测件：一期用 PP-OCRv4 det，并把它漏的东西登记为已知缺口

8 张真实页（mokuro 测试数据 6 + manga-ocr 示例 1 + comic-text-detector 文档页 1）实测，见
`REFERENCE_RESEARCH.md` §8.6.5：

| 件 | 许可 / 体积 | 单页 | 结论 |
|---|---|---|---|
| **PP-OCRv4 mobile det** | **apache-2.0** / **4.7 MB** | **~70 ms** | 框紧贴竖排列、误报极少；**漏手写拟声词** |
| comic-text-detector ONNX | 声明 apache-2.0 但权重源自 GPL-3 项目 → 灰色 | ~450 ms | 召回更高，但假框压在美术上（**部分是我用 `det` 通道 + 通用 DB 后处理的锅，未按其 `blk` 头官方解码重测**） |
| Apple Vision | 系统 API、零模型 | ~200 ms | **漫画竖排上基本不工作**（Manga109 页 0 框；同 API 在别页出 35 框 → 不是接口坏） |

1. **一期检测件 = PP-OCRv4 det**：唯一同时满足「许可干净 + 体积小 + 当场可用 + 框质量最好」。
   顺带**收回**上一轮的判断 —— 曾把「Mekuru 用 Apple Vision 替掉 GPL 检测器」当作可照搬的先例，
   实测否决，`REFERENCE_RESEARCH.md` §8.1 / §8.3 已改。
2. **拟声词漏检登记为已知缺口，不当 bug 处理**：三家都漏（PP-OCR 全漏、CTD 只捞回一部分），
   这是「漫画检测」与「文档检测」的真实分界。一期表现 = **气泡与旁白被翻译，手写拟声词保持原样**；
   要补它只有一条干净路：**自己标数据训一个**（成本另计，另开 ADR）。
   **已落地（2026-09-25）**：新 workspace 成员 `rust/ocr_core` 实现了检测件 + DB 后处理，
   6 条单测通过，8 张真实页对照见 `REFERENCE_RESEARCH.md` §8.6.5；EP 由 `Ep` 显式指定、
   **不静默退回 CPU**。识别（manga-ocr）与擦字（LaMa）是下一批；文字绘制仍归 Dart 侧。
3. 若将来要用 comic-text-detector 的召回，**先按它官方的 `blk` 头解码重测**再谈选型，
   且**许可按「源自 GPL 项目」对待**，不因 HF 上标了 apache-2.0 就放行。

   **识别件已落地（2026-09-25）**：`rust/ocr_core::recognize` —— manga-ocr 的 ONNX 导出，
   贪心 + `no_repeat_ngram=3`、预处理 224 压扁 + 0.5/0.5 归一化、字符级词表解码；
   28 框整页实测无截断无乱码，两个调参结论（裁剪外扩 6 px、检测框会切断长竖排列）见
   `REFERENCE_RESEARCH.md` §8.6.6。**下一段是「按列邻接把框聚成块」**，否则翻译拿到的是半句。

   **聚块已落地（2026-09-25）**：`rust/ocr_core::group` —— 邻接 + 投影重叠两条门槛、
   块内列优先读序，实测 28 框聚成 15 块且块文本可读。**已知硬限制**：相邻且间隙极小的
   两只气泡会被并成一簇（本页实测间隙 6 px < 气泡内列距），要分开需要气泡轮廓分割，
   而那份权重是 GPL → 归入未决 6 的「自标数据训检测器」。细节见 `REFERENCE_RESEARCH.md` §8.6.7。

   **擦字已落地（2026-09-25）**：`rust/ocr_core::inpaint` —— 掩膜取块框外扩 3 px，
   页与掩膜降到 `max_side = 1024`（对齐 8）推理后**只在掩膜内**合成回原尺寸。
   实测 debug 下 36/6 725/72 ms（前/推/合）@720×1024、掩膜占页 9%，整页 ~14.5 s；
   原尺寸直跑要按 6 倍面积算。质量：文字抹净、气泡描边保留、美术未动；
   拟声词区（网点/速度线上）**明确不处理**（检测漏 + LaMa 糊，两处缺口同区叠加）。

   **桥接已通（2026-09-25）**：`rust/src/api/ocr.rs::ocr_analyze_page` 经 FRB 暴露给 Dart
   （检测 → 识别 → 聚块 → 可选擦字，返回每块的 quad + 原文 + 擦干净底图路径）；
   翻译与译文绘制仍在 Dart 侧（§决定 3 / §决定 7）。**顺带修掉一个潜伏故障**：
   Rust 侧 `file_manager` 拆子模块后没有重跑 codegen，Dart 侧旧 `file_manager.dart` 期望的
   wire 名（`crateApiFileManagerFileManagerCreate`）与 Rust 新生成的（`…BrowseFileManagerCreate`）
   已不一致 —— 文件管理器在运行时必炸。已重跑 codegen、删除旧文件、改 8 处导入，
   并把 `file_manager` 的 FRB 子模块改成 `pub mod`（生成代码按新路径引用，私有会编译不过）。
   **过桥验真（同日）**：`test/ocr/ocr_analyze_page_probe_test.dart` 在测试 VM 里真实调用 ——
   块数、竖排两列聚成一块、相邻气泡不串簇、四角点在页内、擦字写出 827×1170 底图，全部通过。
   踩到的坑记在测试注释里：**Rust `u64` 过桥是 Dart `BigInt`**，不是 `int`（`greaterThan(0)` 会炸）。

### 3.4 接入形态（实现期补的三条，2026-09-26）

接进阅读器时冒出三件写 ADR 时想不到的事，定下来记在这：

1. **开关是「每一页」的，不是全局的。** 一张成品页要 ~14 s（检测 0.2 s + 识别 3.7 s/28 框 +
   擦字 6.7 s + 一次翻译请求 + 排版），全局开关等于「往后每页都得等」；而实际需求常常是
   「这一格到底说了啥」。所以顶栏那颗芯片只作用于当前页，翻过去状态自然回到「译」。
2. **成品页走呈现器的增强图轨，因此与 AI 超分互斥。** 桌面端页面由 native 上屏，
   Flutter 侧再盖一层 `Image.file` 会绕开旋转 / 双页 / 页宽适配（画出来是「另一张没转的图」）。
   增强图轨（`GpuPresentController.setEnhancedImage`，超分用的就是它）**一页只有一份像素**，
   所以规则是：这一页被译文占用时超分调度跳过它；关掉译文时把**原图**当增强图注回去
   —— 呈现器没有「清除增强图」这个入口，而用户要的就是回到原图，注一张原图效果等价。
3. **「注入了」不等于「画面上换了」，状态只认呈现器的回答。** 注入后重画一次，再问
   `usedEnhanced`；它答 `false` 就判失败并显示原因，答不上来就报「不知道」。
   这条纪律是从超分那边抄来的 —— 那边曾经「日志说成功、画面还是原图」。
4. **窄高框改走「一字一行」的竖堆**（框高 ≥ 宽 × 1.6 且超过 3 字）。
   §决定 3 原本写「一期只做水平排版」，端到端那张真页证明这不成立：漫画气泡多是窄高框，
   横排换行会排成 3–4 字一行的「假竖排」，读起来是竖着断句的一串。
   竖堆不是真竖排 —— 没有标点旋转、没有列读序，只是把可用宽度收到约一个字让引擎每行放一字；
   真竖排仍按本文 Consequences 的砍单顺序排在后面（判据与前后对比见 `REFERENCE_RESEARCH.md` §8.6.9）。

### 4. 占位②（页后处理位）从此定型

ADR-0008 的「页面渲染层留一个页后处理位，v0.1 不实现也不固化进公开接口」在本 ADR 批准后**结束留白**：
接口的最小形状定为「**一页 = 一张图**，但这张图的**来源可被替换**」——
后处理产出的是「替代位图 + 其派生自哪一页/哪一版参数」的指纹，不改变 `PageSource` 的形状，
也不引入「一页 = 图层集合」（那会顺溢进渲染模型）。
**上色仍然不做**：这个位是为它留的，但本 ADR **不代为解冻**，冻结线对它继续有效。

### 5. 模型与字体：字体随包，权重首下

- **权重一律首次使用时下载，不随包分发**，沿用既有口径（RealSR / waifu2x：解压到
  `getFilePath()/super_resolution/`，见 `lib/page/setting/real_sr/service/real_sr_super_resolution.dart:71`；
  OCR 用同级新目录）。理由有两条：一是体积（识别 460 MB + 擦字 206 MB 不可能进包），
  二是**部分权重的再分发条款是灰色的**（RF-DETR 那份 `license: other` + Manga109 衍生、
  CTD 那份声明 Apache 但权重源自 GPL 项目 —— 全表见 `REFERENCE_RESEARCH.md` §8.6.1）。
  已核为 apache-2.0 / MIT 的那几份（manga-ocr、lama-manga、aot-inpainting、PP-OCRv4 det）随包合法，
  但仍走首下，**不要出现两套模型分发口径**。
  manga-ocr-rs 的**编译期拉模型**（`build.rs` curl ~441 MB）是必须去掉的反模式：会打断离线与交叉编译 CI。
- **回填字体 = 霞鹜文楷轻便版 `LXGWWenKaiLite-Regular.ttf`**（`lxgw/LxgwWenKai-Lite`，
  **OFL-1.1**，v1.522，单字重 13.2 MB），**随包分发**。
  ⚠️ 注册方式在实现时被实测推翻了一次：原写「进 `pubspec.yaml` 的 `fonts:` 段」，但
  **`flutter test` 不加载 FontManifest 里的自定义字体**（`iiii` 与 `WWWW` 等宽 = 全是 `.notdef`），
  于是像素断言只能证明「有墨」、证明不了「不是豆腐块」—— 而豆腐块恰好也是有墨的。
  现改为：字体当**普通 asset** 进包，首次回填时用 `FontLoader(别名)..addFont(rootBundle.load(...))`
  显式注册（`TranslatedPageRenderer.ensureFontLoaded`，幂等），生产与测试走同一条路径。
  另一个实测结论：`FontLoader` 的**别名才是注册名**，字体内部名 `LXGW WenKai Lite` 注册后仍是豆腐块，
  所以 `TextStyle.fontFamily` 必须用别名，改哪边都要同步。
  OFL 明确允许「嵌入软件或 APP、与任何软件捆绑再分发」，但**再分发时必须附带 `OFL.txt` 全文** →
  要进 `asset/`（与字体同目录），不能只在 README 提一句。
- ⚠️ **不许我们自己子集化这个字体。** 它的 `OFL.txt` 首行给保留名（霞鹜 / 落霞孤鹜 / LXGW）的
  书面特例只覆盖两类：未改源码的重编译，以及**「仅为 Web Font 交付」目的**的子集与格式转换
  （且不得作为可安装桌面字体提供）。应用内嵌不在该特例内 →
  自定子集还沿用保留名，触 OFL 第 3 条。将来要压体积只有两条干净路：**用官方 Lite**（作者自己做的衍生，
  保留名合法），或向作者取得书面授权。
- 字形覆盖要**现读**：Lite 相对完整版**剔除了谚文与部分罕用汉字**。目标译文是简中时够用；
  若要往「回填日文」走，得先核覆盖表（其基础字 Klee 是日文字形优先，但 Lite 的删减面未逐项验证）。

### 6. 平台：Windows + macOS 同期（ADR-0006），Linux 顺带；Android / iOS 明确不做

这是**排除项，不是待办**。理由要说白：本仓 `ort` 的 linux/android 那段**没有任何加速器 EP**
（`std` + `ndarray` + `download-binaries` + `tls-rustls`，特性集必须与预编译发行包精确相等）= CPU only；
而 manga-ocr 是 fp32 ViT + BERT（~441 MB），移动端要可用得先做 int8 / QDQ 重导出
（Yakuyomi 为了在 ORT 上跑把识别压到 48 px CTC int8，是另一条工程量）。
与「移动端只做最低适配、不参与任何验收」一致。

### 7. 翻译本身不进 Rust，也不内置 NMT

走已有的 `reqwest`（Dart 侧 `WindHttp`）到 OpenAI-compatible 端点或本机 Ollama。
**不打包专用翻译模型**（OPUS-MT / NLLB / Marian 那一类）：漫画是短句 + 口语 + 语气词 + 需要跨格上下文，
这类句对模型质量不够，且是「检测/识别/擦字/回填」之外的第五个模型族。
**代价要写明**：断网且未起 Ollama 时，成品页链路只能出「擦字 + 原文回填」，翻不出译文。

**这一档已实现（2026-09-26），并且补了一条 ADR 当时没说清的铁律：降级产物不进指纹缓存。**
端点只是**当时**不可用，而缓存指纹里没有任何一项能表达这件事 —— 写进去就等于
「端点恢复之后永远端出这张未翻译的页」，正是本 ADR 一路在防的静默陈旧。
所以降级产物只落到系统临时目录的一个固定名字里（本次能显示、能注入，下次自然重来），
并且顶栏芯片显示成**「原文回填」**而不是「译文页」（`TranslatedPageChipState.showingOriginal`，
单独一个颜色）：一张「擦掉日文又画回日文」的页面看着像成功了，不标出来就是在撒谎。

## Considered Options

- **overlay-first（先只做叠加层，擦字回填另开一版）**：00948185 那一稿的选择，**已否决**。
  叠加层的译文排版不像成品，且「先叠加后回填」会把字体、竖排、字号塞框这几件事做两遍。
  代价是必须现在就把 §决定 3 的缓存与回退约束一起做掉 —— 那正是它比叠加层贵的部分。
- **搬 Koharu 的 crate**（`koharu-ml` / `-pipeline` 切得干净，MIT OR Apache-2.0）：否决。它需要 **LibTorch**
  （safetensors + libloading FFI）与 llama.cpp GGUF，等于在已跑通的 `ort` + CoreML/DirectML 旁边
  再养一个体积与交叉编译成本都更高的推理栈；iOS 上 libtorch 基本无法分发。
  **但回填半边的经验在它身上**：分层、以及 `vert` + `vrt2` 竖排组版（见其 `docs/vertical-text-opentype-plan.md`，
  与本仓 `vendor/mimageviewer` 的同一份文档同源）。
- **只读 Venera-SSR 自行重写**（ADR-0008 的默认路线）：否决。存在 MIT + 同栈的现成整链路，
  「自行重写」省的是许可证而不是时间，而许可证已经不是障碍。
- **搬 Kototoro / Yomihon**（Apache-2.0，法律上可搬）：否决为代码来源 —— Kotlin/Android 到
  Flutter/Dart + Rust 是重写；保留为**逐页开关状态机与任务队列**的形状参考（`REFERENCE_RESEARCH.md` §8.5）。
- **文字改由 Rust 侧绘制**（cosmic-text / swash + 自带 shaping）：否决，见 §决定 3。
  它唯一的收益是成品页可以完全在 Rust 侧闭环、不回调 Dart，但要付「自己维护 CJK shaping」的长期成本。
- **字体也走首下**（省 13 MB 包体）：否决。字体与权重的许可状态不同 —— 文楷是 **OFL、可随包**，
  而权重是「体积装不下 + 部分条款灰色」才被迫首下；把两者混成一条策略会让
  「回填出来是豆腐块」成为断网时的默认体验。
- **Mekuru 式自托管 OCR 服务**（AGPL 的 Python FastAPI）：否决。与「个人自用、离线读本地漫画」形态相反，
  AGPL 网络条款也覆盖该路线。
- **现在就决定把 Rossi 改为 GPL-3.0** 换源码自由度：否决，维持 ADR-0008 的「许可搁置」。
  值得记一笔：这个开关**至今仍未被 OCR 拨动过** —— 解冻靠的是 MIT 来源，不是靠换许可证。

## 批准后要改的四处（执行记录 2026-09-25）

1. ✅ `docs/ROADMAP.md`：冻结表的 OCR 一行改为「**已解冻（ADR-0018）**：成品页 + 落盘缓存 +
   代码来源 MIT/Apache 白名单，**不改仓库许可证**」；「上色」一行不再挂「同上」，独立写清继续冻结的理由。
   另修 `## 明确不做`：那条能力清单里**视频与 OCR 都已按流程解冻**，原表述已成假话；
   GPL 排除清单补上 `comic-text-detector` / `manga-image-translator` / Mekuru / Frank Yomik / Chimahon /
   mokuro / yomitan，并写明**权重首下、字体 OFL 可随包，是两件事**。
2. ✅ `docs/adr/0008-...md`：追加 ADR-0018 例外（照 ADR-0016 那段写法）；**占位②标为「已由 ADR-0018 定型」**；
   §许可搁置的「任何 GPL 源码不得进入本仓库」**原文保留**，只把「将来做 OCR 就自行重写」那句划掉
   并指向本 ADR §决定 1（上色 / Anime4K 仍沿用旧路线）。
3. ✅ `CONTEXT.md`：「OCR 翻译」条改为三处分工的能力参考并标已解冻；**新增「成品页」词条**
   （含缓存 key 的指纹口径与 `_Avoid_`）；「上色」条补「ADR-0018 不代为解冻」；
   「占位」条两处都标为已兑现；**许可边界节**的「可直接抄」加入 OCR 白名单与文楷（含不许子集化），
   「只能读不能抄」补全清单，并加一句「**HF 上标 apache-2.0 不代表权重可随包**」。
   另把 §外部参考里 `Venera-SSR` 那条「Rossi 的 OCR / 上色 / Anime4K 以其为能力参考」收窄为
   「上色 / Anime4K 的能力参考」—— OCR 的参考已经换了。
4. ⏸ `pubspec.yaml` 的字体段**未做**，留到真正接回填那一提交：13.2 MB 二进制一旦进 git 就永久留在历史里，
   而 `ocr_core` 还不存在，先落一个没有消费者的字体只是把不可逆的仓库膨胀提前。
   届时一并定：放哪个字重（Regular 13.2 MB / Medium 13.1 MB / 两个 26 MB）+ 把 `OFL.txt` 放进 `assets:` 段。

## Consequences

- **「最贵的一项」仍然最贵，而且这一稿把最贵的两半收进了一期**：擦字与回填。
  回填不是画字，是**字号自适应塞框 + 竖排 + 与框几何的反复求解**；再加上成品页缓存与失效指纹，
  这块的成本高于检测/识别本身。若中途要砍，砍的顺序应是：上色（已排除）→ 竖排（横排先过）→
  术语表；**不能砍的是 §决定 3 的缓存与回退**，那是它与判据 C 共存的前提。
- **坐标对齐的位置换了，没有消失**：选了成品页，就**不再有**「叠加层跟随缩放/平移」这个问题
  （文字烤进位图，显示路径与原图无异）；代价换成**管线内部**的对齐 —— 识别框、擦字掩膜、回填基线
  必须全在**同一套图像像素坐标**里，且任何一步做缩放/分块预处理都要正确还原。
  这是同一类错误的不同藏身处：错了不会崩，只会「字压在线上」或「擦不干净」。
  （Chimahon 为此写了 subsampling 视图与坐标映射器，那是 overlay 形态的解法；本形态要防的是预处理逆变换。）
- **判据 A–E 不变**，新增一条要进验收的约束：**OCR 开启后翻页帧时间不得劣化**（渲染路径只读缓存）。
  这条可测：同一章节「有成品页缓存」与「无缓存」两种状态下各跑一次判据 C，差值必须在噪声内。
- **新增一类跨页生命周期**（与 ADR-0016 的视频同类）：一个后台任务队列 + 一组落盘产物。
  退出阅读 / 切章 / 切 lane 时必须取消在途推理，且产物写入要原子（半张 webp 比没有更糟）。
- **明确不在本 ADR**：上色、词取字典（Yomihon 那种 tap-lookup）、移动端端侧 OCR、
  任何随包分发的权重、以及字体子集化。
- 13.2 MB 字体进包：桌面包可接受，但它会让**每次都重新链接**的调试构建变慢，
  若实测明显，处置是把字体从 `pubspec.yaml` 临时移出而不是换字体。

## 实现记录（2026-09-26，逐页这一期落地）

| 本 ADR 的决定 | 落点 | 状态 |
|---|---|---|
| §2 `rust/ocr_core` | `rust/ocr_core/src/{detect,postprocess,recognize,group,inpaint,session}.rs`，经 `rust/src/api/ocr.rs::ocr_analyze_page` 过 FRB | 已实现；`cargo test -p rossi_ocr_core` 21 条 |
| §3 成品页 = 缓存产物 | `translated_page_cache.dart`（指纹 + 可读标签目录 + `manifest.json` + 原子写） | 已实现 |
| §3 Dart 侧排版 | `translated_page_renderer.dart`（字号候选下降、越框禁止、OFL 字体运行时注册） | 已实现 |
| §3.4 每页开关 / 与超分互斥 / 状态核对 | `lib/reader/translated_page_controller.dart` + 顶栏 `reader_translated_page_chip.dart`；芯片状态表抽成纯函数 `translated_page_status.dart`（与超分那边同形） | 已实现 |
| §4 页后处理位定型 | 替代位图 = 成品页 PNG，替换入口 = 呈现器既有的增强图轨；`PageSource` 形状**未改**，没有引入图层集合 | 符合 |
| §5 权重首下 / 字体随包 | `ocr_models.dart` + `ocr_model_downloader.dart`；字体当普通 asset、`FontLoader` 注册（原因见 §决定 5 的实测更正） | 已实现 |
| §6 平台排除 | `ocrSupportedHere`：移动端连设置入口都不画 | 已实现 |
| §7 不内置 NMT | `ocr_translator.dart` 只走 OpenAI-compatible；真 HTTP 有 6 条测试 | 已实现 |

验证：`flutter test test/ocr/` + 两份 reader 测试共 **92 条全过 0 skip**（Dart 66 + 呈现器测试 26），
其中 `completed_page_e2e_test.dart` 用真权重跑通整条链路（15 块 / 827×1170 / 每块有墨 / 二次命中缓存）。
真机逐条判据在 `docs/ocr-completed-page-acceptance.md`。

**本期没做**（不是缺陷）：整本批量、真竖排（标点旋转与列读序）、拟声词、上色、Android / iOS。

## 未决（批准本 ADR 前需要先定的）

1. ~~**权重再分发条款核实不了**~~ → **已当场核实**（HF 从本机可达；之前记成「不可达」是调研环境的网络受限，
   不是事实）。识别与擦字这半边是干净的：`manga-ocr-base` **apache-2.0**、
   `mayocream/manga-ocr-onnx` **apache-2.0**、`lama-manga-onnx` **apache-2.0**、
   `mayocream/aot-inpainting` **mit**（全表见 `REFERENCE_RESEARCH.md` §8.6.1）。
   **风险一度整个挪到了检测半边**：气泡分割权重是 **gpl-3.0**，RF-DETR 那份是 `license: other`
   且 `datasets: mayocream/manga109-segmentation`（Manga109 衍生；其 RF-DETR 底座在 HF 上也**没有 license 字段**）。
   → 已由 §决定 3.3 收口：检测走 **PP-OCRv4 det（apache-2.0）**，那两份脏的都不选，本条不再是阻塞项。
   §决定 5（权重不随包分发）仍是**处置**，不是答案 —— 它防的是「将来要分发」时的再分发义务。
2. ~~**manga-ocr 的 encoder/decoder 导出能否在 CoreML EP 上跑**~~ → **已实测，见 §决定 3.2**：
   能跑、无算子硬失败，但**两边都比 CPU 慢**且多付 0.5–3.4 s 建会话；顺带查出这份导出
   **没有 KV cache**（自回归 O(n²)），那是比 EP 更要紧的预算问题。
3. ~~**检测件选哪个**~~ → **已由实测决定**，见 §决定 3.3：一期 PP-OCRv4 det（apache-2.0、4.7 MB、~70 ms/页）。
   Apple Vision 那条路**被实测否决**（漫画竖排 0 框），comic-text-detector 因权重源自 GPL 项目不作随包选项。
   **剩下的不是选型问题，而是能力缺口**：手写拟声词三家全漏 → 要补只能自己标数据训一个（另开 ADR）。
4. ~~**擦字件是否用 LaMa**~~ → **已由实测决定**，见 §决定 3.1：一期 LaMa，AOT-GAN 作难区域补路，
   且 AOT 那条要先补一次「MIT 权重 + Apache 实现」的自有导出。
5. 「个人自用」是否继续作为唯一分发形态（ADR-0006）—— 若哪天要分发，未决 1 里那份
   「权重不随包分发」的处置立刻从「够用」变「阻塞」。
6. **一期范围要不要把「手写拟声词」也算漏**（§决定 3.3.2）：现在的口径是「气泡与旁白翻，拟声词保持原样」。
   如果实际阅读体验里拟声词占比不可接受，唯一干净解是自标数据训检测器 —— 那是**另一版 ADR 的量级**，
   不要在本版里顺手扩。
7. **产物格式从 PNG 换成无损 WebP**（§决定 3 那条本 ADR 未达成，实现落地的是 `p<idx>.png`）。
   省每页约 0.49 MB（实测 1 200 482 → 707 680 B），要同时动四处：
   `rust/gpu_present/Cargo.toml` 的 `image` 特性（现在只有 `png`，不换的话注入直接解不开）、
   一个新的过桥转码 API、缓存文件名、`TranslatedPageCache.isUsable` 的签名判据
   （现在查的是 PNG 签名 + 结尾 `IEND`）。**外加一次 Windows 解码验证** —— 收益小、跨两平台解码路径，
   所以排在拟声词与真竖排之后，不在这一期硬做。

