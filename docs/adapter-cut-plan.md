# 适配层「去 egui」工单

> 由 `docs/phase0-vendor-spike.md` §1 展开。那边量出「要处理 9 个模块」，
> 这里量出**每个模块到底要改什么**——结论是：这不是架构手术，是**类型替换**。
> 数据来源：`vendor/mimageviewer/`（gitlink `f2380d2b`），脚本见
> `poc/mimageviewer-adapter-thickness/measure.py`。

## 一句话

9 个模块的**生产代码**里 egui 相关行共 **67 行**，其中**真 UI 只有 4 行**（3 个文件）。
其余全是 `ColorImage` / `Color32` / `Rect` 这三个**与 UI 无关的纯数据类型**。
→ 「薄适配层」的代价是**可控的**，ADR-0005 的「`use egui` 探针」可以结案。

## 逐模块清单（生产代码 / 括号内为测试代码）

| 模块 | 生产 | 测试 | 生产代码用到的 egui | 要做什么 |
|---|---|---|---|---|
| `settings` | **1** | 2 | `Context`×1 | 唯一真 UI：`apply_ui_scale_factor(ctx: &egui::Context, ...)` → 拆成纯函数，系数由 UI 侧传入 |
| `grid_item` | **1** | 0 | `TextureHandle`×1 | 真 UI：纹理句柄留在 Rossi 渲染层，核心侧只给像素缓冲 |
| `catalog` | 2 | 0 | `ColorImage`×2 | 类型替换 |
| `thumb_loader` | 6 | 0 | `ColorImage`×6 | 类型替换 |
| `page_split` | 9 | 0 | `Rect`×6、`pos2`×8 | 纯几何，换成自有 `Rect` / `Point`（或 `glam`） |
| `canonical_image_loader` | **0** | 7 | — | **生产代码本来就干净**，只有测试引用 → 改测试即可 |
| `fs_animation` | 18 | 0 | `ColorImage`×16、`TextureHandle`×2 | 像素部分类型替换；2 个句柄与 `grid_item` 同处理 |
| `adjustment` | 20 | 24 | `ColorImage`×17、`Color32`×7 | 类型替换（纯像素运算：LUT、直方图、自动色阶） |
| `edit_preview_cache` | 10 | 42 | `ColorImage`×7、`Color32`×3 | 类型替换 + 两处 `repaint_ctx: Option<egui::Context>`（改成回调） |

合计：**生产 67 行 / 测试 75 行**。

## 类型替换的对应关系

不需要自己发明类型 —— `windcore` 已经依赖 `image` crate，而 mImageViewer 自己也在这两者之间互转，
直接用它现成的映射。
**更巧的是版本一致**：`rust/Cargo.toml` 里是 `image = "0.25.10"`，mImageViewer 的依赖表里也是
`image 0.25.10` —— 替换目标与对方同版本，不会引入双份编译（对比 §4.4 里 `zip 8.2.0` vs `zip 2` 那种情况）。

| egui 类型 | 换成 | 理由 |
|---|---|---|
| `egui::ColorImage` | `image::RgbaImage` | 就是 RGBA8 缓冲。`canonical_image_loader::dynamic_image_to_color_image` 已经是 `image::DynamicImage → ColorImage` 的转换，反着写即可 |
| `egui::Color32` | `image::Rgba<u8>` | 4 字节颜色，纯数据；`pixel_lum` / `build_luma_histogram` 这类函数与 UI 无关 |
| `egui::Rect` / `egui::pos2` | 自有 `Rect` / `Point`（f32） | `page_split::uv_rect` / `source_bbox` 是归一化坐标几何，与渲染后端无关 |
| `egui::TextureHandle` | **不替换** —— 留在 Rossi 渲染层 | 它就是 GPU 纹理句柄，核心侧不该有 |
| `egui::Context` | **不替换** —— 拆成纯函数 + 回调 | `apply_ui_scale_factor` / `repaint_ctx` 是「请求重绘 + 读缩放因子」，属于 UI 层职责 |

## 建议的执行顺序

1. **先做 `canonical_image_loader`**（生产 0 行）：只改测试，用来热身并验证替换口径。
2. `catalog` → `thumb_loader` → `page_split`：都是纯类型替换，机械但要小心 `from_rgba_unmultiplied`
   的 premultiplied 语义（`edit_preview_cache` 里同时出现了 premultiplied 与 unmultiplied 两个构造器，
   替换时必须逐个确认，别统一处理）。
3. `adjustment` / `edit_preview_cache`：像素运算量最大的两个，替换后应能直接复用它们现有的测试
   （测试也是 `ColorImage` 写的，改测试的成本已在上面计入）。
4. 最后处理 4 行真 UI：`settings` 拆纯函数、`grid_item` / `fs_animation` / `edit_preview_cache`
   的句柄与 `Context` 留在 UI 侧，核心侧暴露「给我像素」的接口。
5. `ui_helpers`（252 行，被 4 个种子共用）单独排期：**先判断那 252 行里哪些函数真的被核心用到**，
   能拆就拆、拆不动再说 —— 它是唯一一个「可能不便宜」的项。

## 与决策的关系

- 本工单**不改变任何 ADR**：本地核心仍是 mImageViewer（ADR-0011），复用形态仍是
  「外部 fork 源码 + rossi 内薄适配 crate」（ADR-0005 / ADR-0007）。
- 它只是把 ADR-0005 里「「薄」是设计目标，不是已成立的事实」这句话，变成了**已知量**。
- 顺带确认了 ADR-0007 §2 的结论在这里成立：只要这 9 个模块都不碰 `egui` / `eframe` / `egui-wgpu`，
  那份不传递的 `[patch.crates-io]` 就与我们无关 —— **连 patch 表都不用抄**。
