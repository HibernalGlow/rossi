# mImageViewer Rust 后端复用审计与直接源码接入（2026-10-13）

本轮按“能用上游函数就移除本地重复实现”的要求处理。结果是混合架构：部分链路已直接编译上游源码，部分仍为必要适配，完整归档转换、缓存证明及整套 AI 执行链尚不能宣称已复用。

## 1. 审计基线与范围

附件所指的远端 Rossi `main` 为 `7f411dd0dc85a319981944798cdaa111db8214ee`；当前工作区已叠加本轮上游同步提交，尚未推送：

- Breeze：内容同步提交 `dc3498c4`，上游基线 `68bebb2b83130c65ba3f6f709ca5413d2ae184d4`。
- mImageViewer：同步提交 `b169551c`，子模块为 v4.6.0 `bb6ca0c665544da10b1acb061b590512acd0a4a4`。
- 本次改动位于 `codex/audit-mimage-reuse-2026-10-13`，叠在上述同步分支上。

内容同步没有引入上游 merge parent；后续 Breeze 比较用 [upstream-sync.md](upstream-sync.md) 的内容基线，不能根据 merge-base 误判尚未同步。

本轮阅读了 `local_core`、`gpu_present`、`ocr_core`、`windcore` 的入口、依赖和相关实际调用链。每项来源、差异、验证缺口、责任角色及下一步统一登记在 [mimageviewer-reuse-inventory.json](mimageviewer-reuse-inventory.json)。该台账不是功能完成率；源文件数、同名模块数和行数都不足以证明后端等价。

## 2. 已删除重复函数体的部分

直接引用分两种：无适配的模块使用 `#[path]`，复杂文件里的纯逻辑由 `build.rs` 用 `syn` 解析上游 AST，选取符号写入 `OUT_DIR` 后 `include!`。源函数体只有 `vendor/mimageviewer` 一份。构建不依赖 Python；`syn`、`quote`、`prettyplease` 都只用于宿主构建。

[upstream_sources.json](../rust/local_core/upstream_sources.json) 是构建选择清单。除显式可见性提升、字段公开和移除未接入方法外，不替换函数体。符号消失、重名或语法变化会使构建失败；Cargo 监听上游源文件，子模块更新会重新抽取。同步检查仍要求人工复核行为变化。

| Rossi 接入点 | 上游来源 | 本轮接入方式与必要差异 |
|---|---|---|
| `filename_sort` | `src/filename_sort.rs` | 直接编译原文件及其全部测试，调用本地自然排序适配 |
| `auto_aspect` | `src/auto_aspect.rs` | 直接编译原文件及全部测试，`ThumbAspect` 由本地设置模型提供 |
| `path_key` | `src/path_key.rs` | 原模块及测试直接编译；仅排除并替换跨平台盘符根判定，Catalog 既有行为保持 |
| `prefetch_policy` | `src/app/prefetch_policy.rs` | 整个纯模块直接编译，机械提升 `pub(crate)`；上游新增策略和指示器类型也自动进入模块，保留本地契约测试 |
| `archive_converter` | `src/archive_converter.rs` | 直接编译 `ArchiveFormat`、格式/标签及分卷候选判定；只排除尚无消费者的 `temp_suffix`，不冒充完整转换器 |
| `entry_name` | `src/archive_converter.rs::dedup_entry_name` | 去重直接引用上游，严格路径规范化留在 Rossi |
| `fast_resize` | `src/fast_resize.rs` | RGB/RGBA/DynamicImage SIMD 缩放、比例误差策略直接引用；RAW 探测与 LibRaw 不进入本地核心 |
| `rotation` | `src/rotation_db.rs`、`src/displayed_image_transform.rs` | Rotation 类型/步进、UV 双向变换直接引用；本地只补 `Default`，不引入 egui 布局与旋转 DB |
| `ui_helpers` | `src/ui_helpers.rs` | 自然排序与全角数字解析直接引用；只保留 `NaturalChunk::Num` 在前的 Rossi 枚举约定 |
| `animation` | `src/canonical_image_loader.rs` | 直接使用上游 Read 型 PNG/WebP/GIF 容器扫描；Cursor 适配字节接口，保留 VP8X 动画标志的头部兜底 |
| `exif_orientation` → `decode` | `src/thumb_loader.rs`，与 canonical loader 调用方式对应 | 直接使用 EXIF 读取/旋转/镜像；接入 JPEG 快路、普通解码及朝向后的尺寸探测，已确认动图第一帧不另旋转 |
| `ai_size_limit` → `final_pipeline` | `src/ai/upscale.rs` | 尺寸类型与严格长短边限制直接引用；本地默认预算仍为 4096 |
| `ai_tiles` → `api/mimage_onnx` | `src/ai/upscale.rs` | tile 布局及 NCHW/零填充函数直接引用；公开 tile 类型/字段，ORT 会话继续由桥接层拥有 |

原先分卷候选只列举少数后续卷名，现在采用上游 UnRAR 判定，覆盖 `part04`、`part11` 等。候选名称不是卷头证明；`rar_source` 仍检查真实头部。

EXIF 原先没有贯穿本地链路。现在 5–8 朝向会交换布局宽高，快路与降采样路径共用上游变换，避免列表尺寸与阅读方向不一致。这里只补齐朝向，不能据此宣称 ICC、RAW 或完整 canonical decoder 已对齐。

## 3. 核心链路逐项判断

### 3.1 归档读取与转换

| 能力 | 实际形态 | 为什么没有直接复用全模块 | 应用位置与验证缺口 |
|---|---|---|---|
| UnRAR 解压 | `crates/unrar-patched` 的真正 Cargo path 依赖 | 已直接复用；没有本地解压器副本 | 子模块更新即可进入依赖；RAR 真实样本与 Windows 回调/链接验证 |
| ZIP 页枚举/读取 | 本地兼容改写 `zip_source`，`zip_loader` 是首图适配 | 中央目录 index 与展示名分离，保证原始同名条目可分别读回；上游 by-name/tree/cache 协议不同 | 保留 index 定位；上游纯过滤和嵌套扫描可抽取。已测试碰撞、自然序和按 index 读回 |
| RAR 直读 | `rar_source` 包装 patched crate，`rar_loader` 适配本地检查 | 每页按需读、不驻留句柄；显式拒绝固实/加密/嵌套，不能把拒绝当作全格式实现 | 保留直读接口，将转换兜底接到来源解析边界 |
| 完整转换、原子替换与缓存 | **未实现** | 上游 `archive_converter` 当前 2431 行，调用 `archive_cache/archive_origin/folder_tree/zip_loader/zip_tree/logger`；需要接口拆分，不能称为零依赖纯 T1，也不是不可抽取的 Windows 障碍 | 优先抽取 `ConvertCtx`、scan/expand/进度/取消/上限保护；注入日志、类型过滤、ZIP 输入与缓存接口。补故障注入、固实/密码/嵌套、限制、缓存失效/清理测试 |

`LocalSource::open` 的可读来源仍是文件夹、单媒体文件、ZIP/CBZ、可直读 RAR/CBR。7z/LZH/PDF 出现在识别或浏览表中，不代表 Reader 能打开。完整转换和缓存没有被本轮的元数据切片“顺便实现”。

### 3.2 解码

上游 canonical loader 当前 1801 行，统一 RAW、WIC、Susie、动画模式和路径/字节入口；Rossi 需要跨平台内存字节解码、`PagePixels`、JXL 多后端和 Flutter 回退。选择不同底层后端有具体理由，但这些理由不能自动证明输出一致。

本轮抽取了无 Windows 依赖的 EXIF 与动画容器策略。仍需黄金样本验证 ICC/CMYK、16bit/alpha、JXL 内嵌方向、动画处置/循环、损坏输入、降采样和取消。WIC/Susie 的平台运行时应保持可替换后端，尺寸、方向、颜色政策优先提取为共用逻辑。

### 3.3 缩略图与 Catalog

上游 `catalog.rs` 当前 4900 行，`thumb_loader.rs` 当前 10174 行。旧文档的 4500 行不能作为当前依据。

- Catalog 是上游 schema/CRUD 的切片及本地拆分，具有 WAL、旧库迁移、尺寸、淘汰等测试；没有完整固定封面/selection-proof、编辑源、EPUB/RAW 缓存链。
- `thumb_loader` 的代表图解析经过改造。上游 direct-image-first 单代表图与 Rossi 目录块优先、多候选、失败回退/归档候选不同。四图目录封面是明确产品差异，保留在 `thumbnail_pipeline`。
- SIMD 缩放已直接接上游；缓存 key、源身份与失效策略不宜再逐行硬比整份大文件。它们进入台账的“上游变化必复核”门禁，必须先用源变化、目录增删、尺寸变动、pin、并发和旧库样本确定契约，再抽取共有 schema/CRUD 或候选过滤。

当前缓存测试通过，不等于已提供上游全部缓存一致性证明。

### 3.4 ONNX 与最终执行管线

`api/mimage_onnx` 仍拥有模型路径、CoreML/DirectML/CPU EP、Session 生命周期与输出文件；这些属于 Flutter/跨平台接口适配。tile 布局及输入 NCHW/固定 shape/零填充已委托上游函数。

尚未替换的 blend 有实质差异：上游按 RGB/W 四个 float 平面累积，最后统一归一化；本地用 u8 输出逐块合并，较少整图中间内存，但每块合并会取整。直接换上游会同时改变峰值内存和像素输出，需要模型黄金样本与预算决定。输入构造从本地复用 buffer 改为上游每 tile 零初始化 ndarray，需验证实际热路径性能。

下一步抽取 `build_tile_output`/blend 时，应先验证 shape、通道、alpha、padding crop、seam、倍率、输出容差，再验证取消、Session 失效/释放与 CPU/CoreML/DirectML 实机性能。上游 runtime 1012 行绑定 native assets、GPU/EP/worker 管理，保留平台后端并不妨碍共享这些纯策略。

`final_pipeline` 的本地 `ModelKind`、输出结构与连续邻页 keep-set 属于兼容模型，不是上游完整最终管线。模块头和台账已纠正这一声明；完整分类、调整、模型管理与最终执行未对齐。

## 4. 其余 Rust 能力

| 能力 | 上游对应物 / 形态 | 保留或抽取的具体理由 | 验证与责任 |
|---|---|---|---|
| 文件树/面板/页许可/搜索 | `folder_tree/folder_pane/fs_entry/fs_page_load_scheduler/search_query/search_norm/path_key/page_split`，源码移植与边界适配 | Unix 大小写/符号链接、NFKC、共享设置、perf sink、无 egui 几何；`path_key` 改为直接编译，只留下盘符根策略适配 | PORTS 归一化比较及模块回归；Rust 核心维护者复核剥离区域，Windows 分支需原生验证 |
| 文件管理器会话/根目录 | headless `file_manager/file_tree` 对应 egui `app/ui_main` | Flutter/NeoView 页签与来源模型不同；列表规则已委托上游模块 | 页签/搜索/穿透与 Flutter 测试；FRB/核心维护者 |
| 文件操作 | `delete_worker/cut_clipboard/shell_file_ops` 平台改写 | Windows API 不能直接成为 macOS/Linux/mobile 后端；std/fs/trash 是平台适配 | 错误/批次/取消与系统回收站测试；平台维护者 |
| crash-safe 事务 | `book_fs_journal`，**未接入** | 1253 行纯 Rust，与 Windows 后端不能搬是两回事 | 应优先抽取，需每步故障、重启、rollback/冲突/哈希测试 |
| Settings/收藏视图 | `settings/settings_db/favorite_view_state` 缩减改写 | Breeze 设置与 Rossi 会话共同拥有配置，没有上游全量 schema | 持久化回归不能证明全量迁移；核心/Flutter 维护者 |
| `activity_gate` / `susie_loader` / `books` | 同名兼容 shim | 分别是 no-op wait、固定 false、`path.starts_with` 子集，不能算全能力 | 编译/消费者测试；需要完整行为时优先接上游 |
| GPU 上屏/缩放/增强 | `gpu_lanczos/wgpu_backend_policy/video/native_presenter/gpu_anime4k/post_filter` 的平台/架构改写 | Flutter C ABI、DXGI/IOSurface 纹理租约与 egui/D3D 视频窗口生命周期不同；GPU 参数、预算、shader 可分别对照抽取 | 像素/色彩/alpha、fence、设备丢失/重开、缓存/清理；GPU 维护者，需实机 |
| 波形 | `video/seek_strip_wave` 的语义改写 | symphonia 窗口 RMS 对应 media_kit；上游 music_core/wgpu/SQLite tile 服务并非同一接口 | 窗口/绝对幅度回归及硬件/媒体样本；音视频维护者 |
| 操作绑定 | `keymap/ring_shortcut` 的功能对应，Rossi 自研 | 操作身份、Flutter 输入及轮盘 schema 不同；共有冲突政策可抽取 | 冲突/轮盘/解析回归；输入维护者 |
| OCR/inpaint | 独立 PP-OCR/manga-ocr/LaMa 管线 | 没有主张其来自 mImageViewer | 模型与过桥端到端验证；OCR 维护者 |
| Breeze/windcore 插件、HTTP、备份/JM | Breeze 来源，非 mImageViewer 改写 | 图源插件运行时和在线能力独立 | Breeze 内容基线、QuickJS 测试及 FRB；Breeze/桥接维护者 |
| 探针/FRB 生成物 | 诊断/生成代码 | 不算产品后端复用 | 生成物只走统一脚本；探针按平台执行 |

## 5. 同步责任与门禁

运行 `python3 script/sync_vendored_modules.py`：

1. 直接源码：检查引用及文件存在；源码更新列出变更，Cargo 和契约测试负责接口/行为检查。
2. 人工移植：保留已登记归一化比较，发现未登记偏离即非零退出。
3. 改写、切片或未实现：从每条 `reviewed_at` 到 vendor HEAD 检查对应上游文件/目录的改动，打印负责人、差异原因和验证缺口。
4. 四个 Rust 源码根目录中，不属于任何已登记能力的新增文件触发失败。PORTS 的来源映射也必须与能力台账一致。
5. 上游文件删除/重命名、无效或非祖先的复核基线，以及 vendor 工作树与 HEAD 不同，触发失败。

`--bump` 只更新 PORTS 的源码同步 pin，**不更新人工复核 `reviewed_at`**。后者必须检查改动、适配与验证缺口后逐项修改。即使本地选择保留产品差异，也要留下理由；不需要制造一份整文件无意义 diff。

仅新增函数到未选中的上游大文件不会自动加入产品。完整纯模块（例如预取）直接跟随所有源码；切片清单要在复核后扩展选择项并接真实消费者。此区别避免把未用的源码或格式表算作新能力。

## 6. 本轮验证与后续顺序

- 本地核心：EXIF 全朝向、JPEG 快路/缩放/探尺寸一致、RAR 后续卷名、tile 布局/全覆盖、RGB NCHW/零填充、原有文件/缓存/调度回归。
- 构建抽取：上游函数体变化进入产物、符号消失/重名拒绝、字符串/注释中的括号安全、derive/字段可见性、整模块新增函数自动进入。
- Python：未进 PORTS 的上游改写模块变化、新本地模块、路径消失、无效 pin、重复 ID/遗漏根目录、错误映射和当前真实清单。
本轮最终结果：

```text
cargo test --manifest-path rust/Cargo.toml -p rossi_local_core --lib --test upstream_source_extraction
  local_core: 473 passed；源码抽取: 5 passed
cargo check --manifest-path rust/Cargo.toml -p windcore --lib
  passed（现有 file_manager glob re-export 警告）
python3 -m unittest discover -s script -p test_mimage_reuse_inventory.py -v
  9 passed
python3 script/sync_vendored_modules.py
  exit 0，直接引用、移植偏离、Rust 覆盖和人工复核基线通过
dart ./script/code_generate.dart
  完整通过 slang/build_runner/FRB/格式化
```

统一代码生成最初遇到并行文件管理器重构的缺失模块，待该改动恢复后重跑完整脚本成功；未撤销其他工作。生成物中的其他文件管理器 API 变化属于并行改动，不混入本轮提交。Windows/Linux/Apple GPU 与真实 ONNX 模型链未在本轮做端到端验证，不能以纯函数测试代替。

后续减少维护副本的顺序：先接完整归档转换/缓存与纯事务日志；再抽共享 Catalog schema/CRUD、候选过滤与缓存身份；随后以模型样本/预算决定 AI 输出构造与 blend；继续提取 decoder 的颜色/尺寸政策及 GPU 纯策略。平台 API、会话所有者及明确产品差异放在薄适配层中。
