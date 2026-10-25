# 上游同步记录

## mImageViewer v4.8.1 同步（2026-10-25）

| 来源 | 先前内容基准 | 本次内容基准 |
|---|---|---|
| mImageViewer | `bb6ca0c665544da10b1acb061b590512acd0a4a4`（v4.6.0 线） | `94017f82e`（v4.8.1） |
| Breeze | 无更新 | 无更新 |

子模块快进 673 个提交（v4.6.0 → v4.8.1），`sync_vendored_modules.py` 全量
报告后按「上游优先」逐项处理，最终脚本 `exit 0`、`cargo test -p rossi_local_core`
516 项通过、`cargo check -p windcore` 通过。

**采用（合并进本仓）**：

- **同名文件夹/书三态策略**（上游 866c01f68，"one three-way same-name setting"）：
  旧 `skip_zip_if_folder_exists` 布尔升级为 `SameNameFolderBookPolicy`
  （PreferBook / PreferFolder / ShowBoth）。上游新模块 `src/same_name_folder_book.rs`
  是纯策略（serde + std），以构建期 AST 切片直接编译（`upstream_sources.json` 新条目，
  items = 枚举 + `canonicalize` + `keep_mask`，上游自带 `mod tests` 里依赖上游全量
  `Settings` 的用例不随切片）；`folder_tree::sorted_subdirs` 按上游形状改走
  `keep_mask` 投影（该函数在 PORTS 声明的人工读区域，比较不覆盖、手动移植）。
  `Settings` 字段同步替换，`settings_db::load_settings` 读取时先跑上游 `canonicalize`
  迁移旧布尔（开 → PreferBook、关 → ShowBoth；注意这是上游公告的**语义翻转**——
  旧「开」原本跳过 ZIP 保留文件夹，迁移后保留书）。上游为导航层加的
  `show_hidden_files` 字段无本地消费者（`listing_candidates` 概念随导航层未搬），
  与 EPUB 三字段同样以 strip 规则登记。
- **catalog 缓存清理删除单元修复**（上游 backlog 2.12）：`delete_old_cache` /
  `delete_all_cache` 从只删 `.db` 改为 `.db` + `-wal`/`-shm` 一起删
  （`.db` 删除失败不动 sidecar），clear-all 额外回收 `.db` 已不存在的孤儿 sidecar
  （上游实测旧版残留可积 1.4 GB）。本地 `cache_store.rs` 与上游修复前同病；
  该 API 目前无生产调用方，按已登记能力修正并补回归测试。

**登记不搬（上游动了文件但本地刻意不跟）**：

- `fs_page_load_scheduler` 的 `completion_without_worker_for_test`（5a7d3523e，
  backlog 1.114）：上游 PDF 拦截测试专用的 test-only 清理辅助，本仓无 rerender
  probe，PORTS 登记剥离。
- `folder_tree` 上游两个新测试（三态落点断言依赖未搬的 `sorted_subdirs_for_nav`；
  `hidden_same_name_qualification_tests` 整模依赖 `crate::app::*`），剥离登记；
  等价候选断言已移植进本地 `tests.rs`。
- 其余上游变更集中在 egui 0.37 迁移、书结构操作（STORES）、显示基准重构
  （backlog 1.165）、ZIP 嵌套缓存身份（1.194）、通知时长等 UI/应用层，不影响
  本仓借用的纯逻辑；15 个构建期切片项（exif_orientation、animation、
  natural_sort、rotation UV、fast_resize 等）pin..HEAD 逐字比对无变化。

**待决策能力（上游已实现、本仓未接，非同步范围）**：AVIF 解码
（v4.8.0 起内置 libavif + dav1d，位于 WIC 之前；`fast_resize::probe_dims` 也加了
AVIF 尺寸探测）。已在复用台账 `decode` / `fast_resize` / `thumb_loader` 条目的
parity_gaps 备注。

**台账维护**：30 项被标记能力逐项复核后 `reviewed_at` 跟到 `94017f82e`；
`local_adjust.rs`（local-adjust-core 薄适配，ADR-0024）补登记为 `local_adjust_bridge`；
`folder_tree` 条目挂上 `same_name_folder_book` 切片的两侧路径。`crates/unrar-patched`
与 `crates/local-adjust-core` 在本窗口无变化。

## Android QNN NPU 超分后端移植（2026-10-24）

来源：[HaoweiLi97/mihon_img_upscale](https://github.com/HaoweiLi97/mihon_img_upscale)
（Apache-2.0，Mihon fork，v1.3.16 / master@2026-10-21）。上游已实现 Qualcomm
QNN / HTP NPU 超分后端且在本仓可用 —— 按 §13 口径整体采用上游实现，不另写
芯片识别与推理。移植面（`android/app/src/main/cpp/realsr_qnn/` 与
`android/.../kotlin/com/zephyr/breeze/realsr/`，文件头均带来源标注）：

- `qnn_backend.{h,cpp}`：QNN 推理引擎（dlopen `libQnnHtp.so`/`libQnnSystem.so`，
  分块、padding、FP16/量化 IO、burst 性能配置）。偏离：新增 `scale()` 访问器
  （上游由 ncnn 对象记账输出倍率；Rossi 无进程内 ncnn 对象，输出位图尺寸取
  上下文元数据推导值）。
- `spatial_qnn_runtime.{h,cpp}` + `qnn_context_bridge.cpp`：DLC → context
  设备端编译（`libQnnModelDlc.so`）。原样（仅 JNI 名随包名调整）。偏离：
  初始化日志开到 DEBUG，并打印 `ADSP_LIBRARY_PATH`（Skel/传输层故障只在
  QNN 内部日志里可见）。
- `realsr_qnn_jni.cpp` + `RealSrQnnChannel.kt`：新增 `JNI_OnLoad`，用
  `dladdr` 定位本 .so 目录，在任何 QNN `dlopen` 之前设置
  `ADSP_LIBRARY_PATH`；探测顺序改为 `architecture()` 先于
  `runtimeAvailable()`。上游把 setenv 放在各入口函数里，首次探测仍可能
  早于 setenv；DSP 一旦在缺路径时完成 Skel 查找，进程内重试会一直失败
  （4000 / transport 14001），只有重启进程才能恢复。
- `periodic_texture_guard.h` / `monochrome_guard.h`：网点纹理防护与单色保证。原样。
- `QualcommHtp.kt` / `QnnModelContexts.kt` / `NpuModelStatus.kt`：HTP 架构探测
  （v69/73/75/79/81）、上下文缓存（身份 = 缓存版本|运行时版本|模型哈希|HTP 架构|
  Build.FINGERPRINT|主 ABI）与状态。偏离：DLC 由 APK assets 改为首用时下载
  （沿用本仓「模型不打包」口径），编译前按 manifest 校验 DLC SHA-256（下载产物
  不受签名保护）；状态流从 StateFlow 换线程安全快照（Kotlin 侧未引入 coroutines）。
- `waifu2x_jni.cpp` 的 QNN 路径 → `realsr_qnn_jni.cpp`：只保留 QNN 推理 JNI
  （上游在同一库内混装 ncnn Vulkan / MediaTek LiteRT / Anime4K；Rossi 的
  Vulkan 走外部 waifu2x CLI 进程，不需要进程内 ncnn）。

不移植：上游 `ImageEnhancer.kt` / `ImageEnhancementCache.kt` 的调度与缓存
（Rossi 已有页面优先级调度、`UpscaledImageCache` 与在飞去重，功能是超集）。
上游失败语义保留：显式选 NPU 失败不回退 Vulkan，报错并保留原图。

模型：上游 15 个 FP16 DLC 中先收两个（`realcugan-se-x2-no-denoise`、
`realcugan-pro-x2-denoise3x`，padding 均 18），从上游 v1.3.16 发布 APK 提取到
`third_party/qnn-dlc/`（gitignore），`script/models/package_qnn_models.py` 打成
`realsr-qnn-android.7z`（4.4 MiB）托管 `HibernalGlow/breeze-binary`；
manifest.json 的 SHA-256 即完整性判据。

构建口径：QNN 运行时来自 Maven Central `com.qualcomm.qti:qnn-runtime:2.49.0`；
QAIRT SDK 2.49.0.260730 仅带 NPU 的发布构建需要（`local.properties` 的
`qnn.sdk.dir`：头文件 + `libQnnModelDlc.so`），无 SDK 时 stub 编译
（`ROSSI_ENABLE_QNN=0`，运行时如实报不可用）—— 与上游 CI 一致。HTP Skel 库按
`-PqnnHtpArchitectures`（默认 `69,79`，写 `all` 保留全部）裁剪，默认包约
+121 MB，全架构约 +175 MB。

验证：`flutter analyze` 无新增告警；`flutter test` 全量与 `test/real_sr/`
34 项通过。未验证项：Android 工程编译（本机无完整 SDK/NDK，留 CI）、真机
（SM8475 / SM8750）画质与整页耗时对照、模型 7z 上传托管。

## 2026-10-23

| 来源 | 先前内容基准 | 本次内容基准 |
|---|---|---|
| Breeze | `68bebb2b83130c65ba3f6f709ca5413d2ae184d4` | `10a0a4d70`（v3.0.35 线） |
| mImageViewer | `bb6ca0c665544da10b1acb061b590512acd0a4a4`（v4.6.0） | 无更新 |

真实 merge commit 集成（保留上游父节点），24 个提交按用户四组决策取舍：

**插件首页 / 云收藏（全量接入，改本仓导航）**：删除 `OldHomePage` /
`OldRankingPage` 与 `lib/page/old_page/`，移除 `oldPageRollbackEnabled` 与
`cloudFavoritePreferred` 两个设置（含设置页磁贴、同步键白名单与菜单互换逻辑）。
本仓自定义导航架构（侧栏 / Dock / 自定义清单）保留，`NavigationEntryId` 里
`oldHome` / `oldRank` 换成 `pluginHome` / `pluginCloudFavorite`，出厂清单对齐
上游五标签顺序。插件注册服务整体取上游（info / initOk 流、删除插件防残留、
init 超时为超集演进）；本仓 `PluginInitCoordinator` 保留给
`qjs_download_runtime` 的下载 runtime 预热。收藏改上游双按钮口径：操作区星标
（本地）+ 粉色云（云端），详情页菜单项移除。

**书架 / 章节行为（先接入行为）**：文件夹返回拦截（`LocalHistoryEntry` +
`ShelfBackAction`）、换文件夹按路径 key 重建回顶、文件夹直属漫画数
（`folderComicCounts`）、详情行选中防闪（provider 缓存嫁接进本仓
`LibraryImageGeometryReporter`/`ImageSleep` 管线）全部接入。章节组名前缀拼装
与去前缀显示按上游移除（追更、阅读过渡标题、无缝拼接全部改纯标题）。
`reverseChapters`（章节倒序默认）接入 `BookshelfSettingState` 并接进
initState / 下拉刷新。进详情确认最新章节（`_syncFollowFromOnlineDetail`）
移植进本仓表达版 `comic_info.dart`。

**web 风详情行（默认关，截图评审后再定）**：`detailLayout` 开关随上游带入
（横排详情行 + 作者 / 元信息行，`UnifiedComicSimplifyEntryInfo` 增加
`author` / `metadata` 字段与本仓画师分桶并存），开关落设置-外观页本仓
`SettingGroup` 块。本仓搜索结果页（展墙画布）与详情页表达版布局未接
`detailLayout` 分支；上游详情页章节虚拟化（`_buildEpisodeSlivers`，与 web 版
布局耦合）一并缓议，本仓已有等价的显示列表缓存。

**基础设施 / 性能（代码层全量接入）**：source map 按 bundle 名隔离、删除插件
后残留无限加载修复、脚本目录随上游（`script/build/`、`script/codegen/`）、
`.mcp.json` / `opencode.json` 删除、`tray_manager` 0.8、评论正文可选择复制与
头像全屏、繁简转换显示缓存（与本仓 `mode` 参数合并）。

**本仓保留项**：Rossi 品牌（README / flatpak / 包版本）、受限来源过滤
（`filterRestrictedPlugins` 包在上游 `registry.plugins` 结构外层）、已下载未读
批量查询、画师收藏分桶、表达版 UI（封面 glyph、弹层、设置页）。

验证：统一代码生成通过；`flutter analyze` 无 error；合并涉及模块定向回归
137 项全过（书架 / 导航 / 发现 / 同步 / 插件首页 / 面板预览）。全套件
2745 过 / 56 败，经干净 HEAD worktree 基线逐项对照归因：**3 项为合并引入
且提交前已修复**（discover_page_real / settings_sync_block /
panel_expressive_preview——注册服务在无 Rust 桥的测试环境直连 FFI 崩溃，
已加降级防护；同步块测试断言了已删除的设置键，已随设置移除）；46 项为
HEAD 既有失败（comic_read ×3、discover/setting ×14、workspace ×19、
download ×2、reader 处理 ×3、toast/theme/operation_binding ×4 等，基线
复跑逐一命中）；7 项来自并行会话对 real_sr 的在途改写（本合并未触碰
real_sr，合并树内该域与 HEAD 完全一致）。合并提交信息中「55 项失败归属
本次合并线」的说法按本条修正。
i18n 自动合并丢失的本地词条（`collectToLocal` 等四条、`comicFollow`
通知文案、`includeDownloadedSubtitle`）已从上轮内容基准恢复。

## 操作绑定 v2 与公共 Rust 核心（2026-10-13）

Breeze 与 mImageViewer 当前可用实现没有同时覆盖 Rossi 的区域触屏、多上下文、轮盘与
配置迁移链路。继续沿用 Rossi 现有绑定实现，将通用模型、Context、匹配、冲突、诊断和
迁移抽为 `rust/operation_binding_core`；动作目录、九宫格和默认值升级保留薄适配。
不另建 Dart 解析器，不引入 Bevy，不实现 Node 适配器。Rust 生态库的实际适配边界与
keybinds 隔离实验见 `docs/operation-binding-rust-library-review.md`。

未版本化设置统一迁移为 v2，保留扩展字段、禁用与自定义操作，失败不覆盖原文；本机备份
不随云同步。鼠标和触屏区域分别配置，Flutter 胜出的单击一次交给 Rust 匹配。

## 阅读单击响应适配（2026-10-14）

沿用 Flutter 的 Tap / DoubleTap 手势识别与原 Rust 绑定解析器，在按下时按设备、
按键、区域和活跃上下文决定双击识别器是否参加竞争。无关双击绑定不再让左右
单击等待 300ms；单击回调只等本轮指针记录完成的微任务，不再额外排入事件队列。
同一区域显式绑定双击、旧全屏双击缩放/操作栏仍保持互斥；子控件优先级、拖动
取消和真实触屏手指数沿用现有通道。Breeze 的该控制器仅有全屏双击开关，没有
可复用的区域/设备绑定筛选，因此新增的是 Flutter 识别器上的薄适配。

验证：触屏/鼠标即时翻页、快速连点、双击互斥、泳道分区、指针采集与轮盘回归；
Flutter 3.47.4 / Dart 3.13.3（仓库锁定 3.47.6），尚未测量真机完整呈现耗时。

## 2026-10-13

| 来源 | 先前内容基准 | 本次内容基准 |
|---|---|---|
| Breeze | `5853c2b4` | `68bebb2b83130c65ba3f6f709ca5413d2ae184d4` |
| mImageViewer | `8d95fffe`（v4.1.0） | `bb6ca0c665544da10b1acb061b590512acd0a4a4`（v4.6.0） |

本次按用户要求，重叠功能优先采用上游实现。Breeze 跟进 21 个提交，采用上游的
阅读设置组件、单本稀疏覆盖与 v12 迁移、章节分组、插件详情、图形验证码、自定义登录
标签、Freezed 状态及下载持续重试逻辑；QuickJS 原生二进制通道移除 JSON 兜底。
Rossi 独有的泳道弹窗、输入绑定、自适应背景、翻页预览、悬停、翻译和媒体控制保留在
独立扩展与薄适配中。下载队列的限流识别保留，操作内重试循环采用上游实现。

Flutter 配置跟到上游 3.47.6，Android minSdk 为 26，缺少签名密钥的 fork CI
采用上游的跳过逻辑。Rossi 包版本仍是 `0.1.0+1`，FRB 仍锁定 `2.12.0`，
代码生成脚本按项目锁定版本安装生成器，避免生成器与运行库不匹配。

mImageViewer 的 gitlink 与源码移植已同步；范围、跨平台差异和未接入功能见
[移植模块同步说明](local-core-vendored-modules.md)。不引入上游 Windows 应用的
UI、转换缓存或未具备消费者的 EPUB/LibRaw 链。

验证：统一代码生成完成；本地核心 462 项、QuickJS 原生通道 31 项、Flutter 相关
回归与 RAR 首卷识别 6 项通过；ObjectBox 旧实体/属性 UID 保留。静态分析没有 error，已有 warning/info
尚存。本机 Flutter 为 3.47.4（Dart 3.13.3），尚未验证 3.47.6 和各平台完整安装包。

## 展墙偏好同步扩展（2026-10-13）

展墙偏好沿用 `rossi.library.presentation.*`，通过现有 WebDAV / S3 设置同步新增
`libraryPresentation` 块；每个 scope 独立记录修改时间并合并，覆盖所有已保存位置与
完整展示参数。旧载荷缺项不清空本机，同步落盘后通知在场的展墙。该扩展接在上游
设置块协议上；上游没有本仓展墙及其 SharedPreferences 存储，无法直接复用对应实现。

同时修正书签、历史与页面列表的展墙持久化：底层列表样式恢复不再关闭并写回展墙，
只有用户明确选择普通视图才保存关闭状态；应用展墙设置会等待落盘完成。

验证：设置同步、按位置合并、旧键迁移、实时更新、面板重建与共享展墙回归 69 项通过，
本次修改文件静态分析无问题。使用 Flutter 3.47.4 / Dart 3.13.3；尚未连接真实云端验收。

## 键盘长按翻页节奏扩展（2026-10-13）

上游键盘仍以系统重复事件触发固定时长动画，没有可直接复用的应用级横翻长按速度控制。
Rossi 在原绑定解析与阅读设置（含本漫稀疏覆盖）上增加薄适配：默认 4 页/秒、
350ms 启动延迟，支持 0.5～15 页/秒和 100～2000ms 延迟；动画随连续翻页周期缩短。
显式 hold 绑定、ignoreRepeat、后续动作、视频上下文与条漫原行为继续由现有通道处理。
松手、方向切换、窗口失焦、编辑/模态上下文及卸载会停止计时；不补发错过的翻页。

验证：统一代码生成成功；键盘节奏、单本覆盖、绑定/滚轮、输入焦点与设置面板
回归 94 项通过；修改文件静态分析无问题；macOS Debug 构建成功。

## 下次同步

2026-10-23 这轮以真实 merge commit 集成（base `68bebb2b` → `10a0a4d70`），
上游父节点在 `main` 的历史里，`merge-base` 已随提交推进。后续同步继续用普通
Git：`git fetch upstream && git merge upstream/main`，保留真实 merge commit 与
上游父节点。不要覆盖 Rossi 独有接口或其他工作分支。

遗留决策点：`detailLayout`（web 风横排详情行）默认关带入，截图评审后决定
是否在本仓搜索结果页 / 详情页布局上继续接线或回退；上游详情页章节虚拟化
（`_buildEpisodeSlivers`）随 web 版布局一并缓议。

### detailLayout 与展墙分流（2026-10-24 用户口径）

用户裁决：`detailLayout` **开** = 关闭展墙、直接渲染 web 风详情行；**关** =
保持本仓展墙（上游该档是普通网格，本仓以展墙 + 其普通视图回退承接）。
接线点三处：`plugin_paged_comic_list_view` 的展墙分支让路给 `detailed`
（发现页 / 插件首页 / 云收藏 / 漫画列表页全覆盖，上游原版行为不变）；
`search_result_page` 在开关开启时直接渲染 `PluginComicGridSliver(detailed:
true)`；书架文件夹页类内 `_buildBody` 按开关显式分流——上游合并引入的类内
同名 `_buildBody` 曾把本仓展墙那条 extension 路径（`_buildWallBody`）整个
遮蔽成死代码（文件夹展墙自合并起静默失效），本次顺带修复。
`folder_shelf_back_test` 的回顶回归改走 detailLayout 开的分支（fling 目标
换成那支的 `CustomScrollView`，点按只挑可命中候选），展墙路径的滚动保管
不在这套 key 语义内。详情页表达版布局维持本仓现状，不受该开关影响。

mImageViewer 更新 gitlink 后运行 `python3 script/sync_vendored_modules.py`，
检查所有 `PORTS` 差异并更新 `pinned_at`；同时人工审查未登记的 `path_key`、
`thumb_loader`、`catalog`、`fast_resize` 与显示几何切片。

## 文件管理器页签布局与创建策略（2026-10-13）

Rossi 的文件管理器在已有 Rust 会话、`FolderPaneState` 与目录列导航上扩展：
`LayoutMode` 是页签级的内容布局（内容、树、分栏），不并入六档条目样式，也不写入
目录级视图偏好。普通树把展开目录的条目直接融合进 `TreeSliver`，目录节点与文件
都使用六档共享卡片；网格档按视口宽度排列同级文件，不另挂独立列表。
搜索树根据已返回命中的真实路径补齐祖先节点，不为展示层级重新扫描磁盘。
同名文件按完整路径区分。

Flutter 树视口采用 SDK 的 `TreeSliver`，目录展开与后台扫描仍由 Rust 管理。
分栏导航复用原有投影并扩展到完整祖先路径，各栏复用 `LibraryEntryList`，前面的
父级栏保留封面与文件元数据，当前目录只显示一次。树和分栏导航保留所选条目样式。
普通目录只枚举已展开的层；搜索各栏使用命中及祖先投影，不追加磁盘扫描。
尺寸拖动交给 `multi_split_view`；
两种布局都占用主内容区，窄窗口可横向滚动。上游 Windows UI 不能直接用于 Flutter，
因此只做现有状态到官方树组件和分栏容器的数据适配，不另写树或分隔拖动控件。

新页签来源可选预设默认值、最近活跃页签、触发页签；未激活页签的“从此页签新建”
可显式指定触发来源。首个页签没有来源时使用预设，目录记忆仍可覆盖条目样式。
后续修改预设不覆盖已打开页签。继承浏览与搜索选项，不复制查询、结果、导航历史或
选中项；复制和恢复页签继续保留原有状态。搜索回车原子创建独立结果页签，达到上限
时源页签不变，从已保存结果再次发起搜索也保留原结果。

验证：统一代码生成成功；Flutter 文件管理器及页签会话回归 114 项、分栏尺寸回归
1 项、真实 Rust 桥接 1 项通过；Rust 文件管理器已有回归 47 项、新布局与页签策略
6 项通过；本次改动的 Flutter 静态分析无问题。尚未运行各平台安装包和桌面交互验收。

2026-10-13 视图兼容修正：移除普通树的双面板；六档卡片统一接入树节点与父级分栏。
补充六种样式在 260/700 宽度下的普通树与父级栏回归，以及真实桥接的普通目录
文件融合、纯文件目录收起/展开与父级文件元数据验证。
本次验证：统一生成成功；文件管理器与分栏控件 Flutter 回归 127 项、真实桥接
2 项通过；Rust 原有回归 47 项、布局集成回归 8 项通过。静态分析无问题。
尚未执行桌面交互验收。

## 阅读器展示适配（2026-10-13）

2026-10-16：顶栏下载入口恢复为现有 `readWhileDownloading` 全局偏好的快捷开关，
选中态与阅读设置同步；窄屏更多菜单使用同一设置。复用现有图片落盘链路，
不跳转下载管理或创建整本下载任务。回归见 `test/comic_read/reader_download_toggle_test.dart`。

阅读设置继续复用上游设置读取、回调与本漫稀疏
覆盖写入，顶栏主行和二级行保留原有档位和全部功能入口。仅呈现层改为主题实色
Expressive 工具栏、进度轨道、缩略图选中形状与分组设置；宽屏分类使用现有
NavigationSidebar，窄屏使用 NavigationDock，分类、滚动位置和本漫写入目标在
窗口变化时保留。弹层进出和进度预览使用 CommonPopupRoute 的同一套托盘动画；
按压、悬停和选项切换复用 ElasticButton / ActionBubbleRegion / SpringLensBar。
增强入口统一采用 48dp tonal 按钮；超分保留本书启停与独立原图对比，翻译仍按
当前页归属、烘焙/叠层与原图旁路显示状态。超分、翻译与设置分别采用
cookie、slanted 与四瓣形状，沿用现有 Morph 路径和弹簧动效。二级工具栏
独立悬浮并按内容收紧，主行与二级行之间、工具栏两侧保留阅读画面；底栏
钉住常驻并移出更多菜单；窗口变化只调整排布，业务回调与存储作用域沿用原实现。

阅读设置的拖动/滚动交接直接使用 material_3_expressive 的
M3EBottomSheetScrollController。该版本 Frame 必带全屏标题和关闭按钮，没有
自定义标题接口，因此外壳采用薄适配：共享一套标题和关闭入口，以实际可见高度
布局正文，上拖先连续展开到全屏、之后滚正文，下拖收回；落位复用项目
SpringLensValue 与 LensMetrics，保留墨水屏、阅读无动画与系统减少动画设置。
技能安装在 .agents/skills/material3-expressive-flutter，来源提交记录在 SOURCE.json。
缩略图比例开关放在阅读设置的「界面 → 上下栏与边距」中，胶卷仅显示缩略图。
开关作为全局阅读偏好扩展，默认统一竖向卡片；开启后按原图比例
排列，极端长宽比保留完整图片。复用页面列表的 ReaderThumbnailWidget、共享
图片尺寸报告、320px 缩略图 LRU 与 Flutter ImageCache；本地同页生成请求合并。
可变宽胶卷使用 ListView 的 itemExtentBuilder 保留虚拟化与双向当前页居中。
验证见阅读设置、顶栏布局、缩略图、进度方向/防抖、视频组合底栏及共享弹层测试。

## 设置展示适配（2026-10-13）

设置仍采用 Breeze 的分类页、状态和持久化接口。其总览为单栏列表，没有可直接
复用的 Flutter Expressive 双栏设置浏览器；Rossi 在入口与公共外壳上添加展示适配，
使用 `material_3_expressive` 的 `M3EList` 分组和 `M3ECard` 主题选择，配色取现有
Material Theme（包含动态取色与导入主题），按设置面板的实际宽度选择单双栏。

详情区直接挂载原分类页，`SettingDetailScope` 只关闭该页的返回入口。下一层仍走
原路由和工作台守卫；阅读设置沿用上游共享面板。输入绑定页有未保存编辑的回退
保护，仍用原独立路由；不为了双栏绕过保存确认。保留超分、OCR 和工作台的平台
可用条件。新增搜索只检索分类名称、分组和当前摘要，不宣称能搜索所有设置项。

外观页仅重组原控件，主题预览写回原 `ThemeMode`；减少动画和墨水屏模式关闭
新增按压形变。分组、双栏、搜索、键盘与主题写回的回归见
`test/setting/setting_browser_test.dart`。

设置动效继续使用本仓统一组件：`CommonPopupRoute` 承担设置子页面、居中确认框和下拉菜单的进出场；`ActionBubbleRegion` / `ActionBubbleTarget` 在分类、主题预览与分组条目之间连续移动悬停高亮；`RetainedPanelSwitcher` 用 `SpringLensValue` 与 `LensMetrics` 承接连续切换的当前位置和速度，并保留已访问详情的滚动与输入状态。没有引入另一套弹出曲线。输入绑定仍经 auto_route 守卫与 PopScope 保存保护；墨水屏和系统减少动画模式跳过空间动画。

验证：设置导航、搜索、主题持久化、键盘导航、字号缩放、连续悬停与反向、保留详情、PopScope 返回保护、共享弹层返回值、菜单根层摆位与关闭生命周期、子菜单及保留面板绘制预算的 widget 测试；Flutter 3.47.4 / Dart 3.13.3 环境运行（仓库锁定 Flutter 3.47.6）。

## 设置分组统一与折叠大标题（2026-10-14）

`同步` 原先是唯一留在旧形态上的设置页：行直接坐在页面底色（浅色主题即纯白）上，用
`Divider` 分段；其余设置页已在 `SettingGroup`（`M3EList`，`surfaceContainerLow` 主题色表面）上。
本轮把剩下的设置页与两处二级页（字体设置、主题色）逐页并入同一口径：一律
`SettingPageShell` + `SettingSectionCard`，去掉 `Divider`，页边距统一 `kSettingPagePadding`。
分组后设置行的定位不变：`SettingEntryList` 的 id 会穿进分组卡（`flattenSettingEntries`），
落到卡内那一行用 `Scrollable.ensureVisible` 补挪 —— 包按下标收敛时，卡比视口高会让
`ListObserverController.animateTo` 永不完成（实测补挪步骤不执行且 `pumpAndSettle` 挂满超时）。

超分（RealSR）三份文件不参与统一：用户口径为「超分设置没有特定风格」，其条件是阅读端与工作台
共用的自定义面板。该排除写在门禁脚本里并每次运行打印理由，不是静默跳过。

独立成页的设置页改用折叠大标题：`SettingPageShell` 的外层换成 `NestedScrollView`，header 是
`material_3_expressive` 的 `M3EAppBar.sliver(variant: largeFlexible)`，各页仍只传 `child`，
不必改成 sliver。上游已有该组件，因此不另写 `SliverAppBar.large`。双栏右栏
（`SettingDetailScope.isEmbedded`）保留原实色小栏，避免左栏选中项与右栏大标题同屏两遍。
折叠只给二级页：设置总入口（一级页）传 `collapsingTitle: false`，它下面已经有双栏总览卡；
门禁对这一条也做了断言。
三条实测边界写进代码注释，别当参数调：该 sliver 不自动推导返回键（要显式
`leading: BackButton()`）；flexible 档的标题列是定高且 `M3EAppBarDensity` 没有更高一档，
360×800 / textScale 2 下钳到 1.2 仍溢出 1px，故标题区不跟随系统字号、正文照常放大；
展开带子的余量（同一探针，宽度 360 与 800 数字相同，说明它与宽度无关）：单行标题 132、
单行标题＋单行介绍 164，标题换成两行在 132 档 `overflowed by 36`、164 档 `overflowed by 28`
—— 所以「大标题自然换行」在上游实现里放不下，标题只能一行＋省略号（本页标题最长 6 个汉字，
实测远不到省略号阈值）。
「长句子完整可读」这一条改由介绍满足：它不再占 `subtitle`，而是外层 header 的第二条
`SliverToBoxAdapter`，按内容定高，因此能自然换行、跟随系统字号，并随内容卷走（顶栏只留常驻
小标题）。它本来就是原来那一句介绍，不是为折叠动画新造的内容。挪进 header 后唯一的视觉风险
是「小栏常驻时介绍画在它上面」，这条也不用等真机：pinned header 向后一条 sliver 报的通道在本
SDK 叫 `SliverConstraints.overlap`（由 `SliverGeometry.maxScrollObstructionExtent` 供），实测
进页面 0、滚过收起幅度后 >0，即介绍被压在小栏底下。
介绍文案只复用既有 `*Subtitle` 词条（12 页），没有为凑格式新造句子；缺介绍的工具页
（存储、缓存、调试等）保持只有大标题。

门禁：`python3 script/check_setting_group_style.py --strict` —— 按内容（不是文件名）取设置页范围，
四条硬红线：自带 `Scaffold` 未走外壳、还有 `Divider`、页面自己搭 `AppBar`/滚动视图（绕开折叠）、
有设置行却没有分组卡；外壳丢失折叠顶栏同样不合格。回归：`test/setting/setting_group_style_test.dart`
（13 页逐行「无行落在卡外」+ 阳性对照）、`test/setting/setting_collapsing_title_test.dart`
（展开高度、滚 320 后收起幅度、收起后标题常驻、应用真实弹层路由、textScale 2 窄面板不顶穿、
短页不为折叠造内容、双栏右栏不挂大标题），以及只 import 外壳的合成页
`test/setting/shell_collapsing_title_test.dart`（真页夹具要过 `GlobalSettingCubit` → `main.dart`
的整棵 import 图，别的会话在 `lib/page/comic_read/**` 留编不过的在途代码时，那份连编译都进不去，
这份仍然可跑）：折叠幅度、介绍换行后仍随内容卷走、以及「标题一行放不放得下」——后者拿
`RenderParagraph` 实宽与整句单行宽比，并用 22 字的假标题作阳性对照，证明这把尺看得见截断。
OCR 与按键绑定两页需过桥 dylib 才能 pump
（`./script/refresh_release_dylib.sh` 后加回表内），当前只由上述文件级门禁覆盖。

## 搜索组件历史适配（2026-10-13）

复用 `material_ui` 已包含的 Flutter 官方 `Autocomplete` 默认建议视图与
`PopupMenuButton` 历史菜单，不另写建议浮层、列表或键盘导航。共用组件仅适配
现有输入框、回调和存储。普通回车提交当前输入，方向键选择后回车接受历史；
点历史立即重搜。空输入聚焦展示最近记录，支持按输入过滤与清空当前用途的历史。

图源与聚合搜索继续读写 Breeze 的 `GlobalSettingState.searchHistory`，按来源
隔离；归属未知的旧历史留在原历史页。结果页改为从写入时的当前状态更新，避免
延迟保存旧列表覆盖其他页签的新历史。文件管理器复用 Rust 的 SettingsDb API，
成功创建搜索页签后才记录；移除旧历史 chip 行，改用同一套现成组件。

书架各模式、工作台书签和阅读历史、页码/文件名筛选、插件商店、字体选择、收藏
画师/标签、输入绑定及设置分类筛选使用已有 `shared_preferences`，各用途独立键。
本地筛选只在提交、失焦或结束编辑时保存完整词，保留原来的实时过滤；去重、最近
优先且每用途最多 50 条，共用写队列避免多个卡片覆盖。历史存储故障不阻断搜索。
上游只有图源搜索的历史页，没有上述跨搜索组件的自动完成接入，因此这是接在
上游历史模型与现成组件上的展示适配。

## 文件管理器面包屑展示适配（2026-10-13）

两种样式共用 `PathBreadcrumb`，继续消费 Rust 快照中的 breadcrumbs；不维护第二套
路径状态或祖先推导。克制型采用规整圆角与当前项文字强调，强表现型在轮廓带加入
轻微起伏，根节点及当前项使用 `material_3_expressive` 的形状。宽度不足时保留首尾，
中间祖先在现有 `CommonPopupBox` / `CommonPopupRoute` 中跳转；当前项仍编辑完整路径。
按压和跨项悬停复用 `ElasticPress` 与 `ActionBubbleRegion` 的物理弹簧，减少动画及墨水屏
模式遵守原开关。样式写入原 `FileManagerSettingState`，旧数据及未知枚举值降级为克制型。
该功能仅是现有文件管理导航上的 Flutter 展示扩展；mImageViewer 的原生文件管理界面
不能直接作为 Flutter 控件使用，Breeze 没有该工作台文件管理组件。

## 2026-10-13 藏书展示扩展

共用 `LibraryEntry`、`FolderShelfBloc`、`ComicInfo` 与文件管理器树快照，增加可组合的
M3 Expressive 展墙及原位详情，不另建导航、下载或阅读实现。目录数量/体积的异步扫描仅
为展示面积提供度量：现有核心快照的 `childNames` 是预览而非总数，没有可用于此展示的
完整数量/字节接口，因此使用可取消、带缓存的 Dart 薄展示服务。行为、边界与验证见
[藏书展示设计](design/library-expressive.md)。

原位详情使用专门的操作、Tag、简介、章节与预览布局，复用原有业务状态；不直接嵌入旧页。
原图比例选项共用于藏书、书签、历史、文件与页面列表，设置集中在既有顶栏弹出菜单。
展墙卡片使用完整等比封面与融合文字遮罩，宽卡增加真实标签和状态容量，标题不随面积放大。
原位详情首帧创建既有业务宿主，展墙和普通列表复用几何，不为展开重算权重排布；
多项详情独立保留状态，包括书签/历史时间线。已收起详情仅缓存最近 8 项，打开数量不受此限制。
文件夹合成保留既有候选规则，仅把中心裁切改成完整等比置入并升级策略缓存键；
实现与回归记录见 docs/local-core-vendored-modules.md。

## 阅读轮盘蜂窝展示适配（2026-10-13）

继续使用本仓 `flutter_ray_menu` 的条目、槽位和指针/键盘流程，以及原 Rust
操作绑定解析器；新增 surfaceBuilder、visualHitTest 和指针观察接口承载 Flutter
展示。按用户确定的 Apple Watch 应用视图方向，从中心填满紧凑蜂窝格点，
阅读时不为空槽保留视觉占位。逻辑 id、层号和槽位不变，视觉位置不再表达旧
扇区方向；编辑器仍能选择空槽。Breeze 没有可直接复用的上述 Flutter 展示。

指针局部放大、有限平移与选中态沿用 SpringLensValue/LensMetrics，浮层进出
沿用 CommonPopupOverlayMotion，图标选择器沿用 CommonPopupRoute。实际绘制
与命中共用变形几何；按下冻结几何，原指针路由继续负责松手去重与动作派发。
阅读图标通过原解析器按 reader/video 上下文匹配，编辑器提供可选的 iconId
展示覆盖，随 JSON 保存。Rust 的 NeoView 轮盘文档仅增加可选展示字段，未改变
槽位、动作与验证规则；该模型不是 mImageViewer 的直接源码或 PORTS 移植模块。

验证记录见 docs/design/reader-radial-menu-expressive.md 与 operation_binding 下的
聚焦几何、展示、图标、编辑器和阅读浮层回归，以及原 RayMenu 与 Rust 轮盘测试。

## 工作台设置与工具入口适配（2026-10-13）

工作台 `tools` 面板使用 `WorkspaceToolsPanel` 呈现入口，不再嵌入上游 `MorePage`
的品牌头。设置放在首屏顶部，外观、共享阅读设置和工作台布局提供快捷入口；
下载任务、同步和追更共享常用分组，更新日志与关于保留在次级分组。按面板实际
宽度和字号决定是否并排，不改变面板 id、已保存布局或独立模式的更多页。

这是原功能上的展示扩展：所有页面继续由现有 auto_route 路由、工作台守卫和
局部 Navigator 打开与返回；阅读设置仍使用共享 `showReaderSettingsSheet`。
不另建设置状态、下载队列或追更模型，主题摘要与追更数量读原 Cubit。
分组复用 `SettingGroup` / `M3EList`，主入口采用主题容器与 M3E 形状，
按压、跨入口悬停和弹层沿用统一组件；减少动画和墨水屏遵守原开关。
验证入口顺序、完整回调、窄面板与大字号、RTL、更新徽标、键盘和共享悬停。

## 阅读洞察展示与布局适配（2026-10-13）

原有近七日趋势、连续阅读、星期与小时热力、来源拆分继续使用
`history_insights.dart` 的聚合与 `HistoryInsightsWindow` 的 ObjectBox 有界查询。
新增概览、连续 28 日日历、星期节奏和六小时分布仅扩展同一份最近 500 条样本；
统一标注为漫画的最后阅读记录，不把 `lastReadAt` 当作完整访问日志或阅读时长。
来源归一仍调用 `classifyHistorySource`，日期使用原本的本地日历工具。
Breeze 没有该工作台统计面板；mImageViewer 的原生统计面板统计缩略图缓存、
文件格式与加载性能，依赖 egui 和原生应用状态，不能替代 Flutter 阅读历史洞察。

强表现集中在摘要字号、异形图标徽章、主指标色块、选中反馈和来源环图。
热力格、数值行和柱图保持一致几何；时段选择使用原 `CommonPopupBox`，
按压、悬停与数据变化使用 `ElasticPress`、`ActionBubbleRegion` 和
`SpringLensValue`，减少动画和墨水屏时跳过新增空间动画。

小尺寸连续阅读改用摘要 / 趋势分段；热力图按宽度汇总时段并保留全七行，
极小槽位显示摘要和统一弹层展开入口。切段箭头、段名 / 进度与热力粒度、
展开入口均在原卡片标题栏内适配宽度，不另占底部一行。正文状态通过帧尾绑定
更新标题操作，移除正文时释放绑定。两者通过内容适配消费实际高度，
不在卡片内嵌套滚动。设计与数据边界见 [洞察卡片内容适配](design/insight-card-content.md)。

显式网格跨度现在使用紧约束，固定宽高不再因内容多少改变。
`CollapsibleCard` 在有界槽位中保留标题和调整手柄，内容在内部滚动；
折叠复用 `RetainedPanelSwitcher` 的可重定向弹簧，保留内容状态和历史订阅，
外框尺寸不变。
独立自然高度卡片继续沿用原折叠行为。低高度编辑态预留的手柄空间按可用高度
收敛，避免最小档位溢出。新增分析卡注册在原工作台注册表，沿用布局持久化、
跨面板移动、隐藏和恢复，不引入第二套布局模型。

回归覆盖日期跨年与窗口边界、未来记录过滤、六小时时段、来源 UUID 归一、
180–760dp 卡宽、96–384dp 卡高、两倍字号、横纵网格同跨度对齐、内容刷新后
槽位不变、最小档编辑、真实统计面板调整与历史订阅保留、统一弹层时段选择。

## 发现页与通用展墙调整（2026-10-13）

发现列表继续使用 Breeze `68bebb2b` 的场景、插件筛选、分页 Cubit 和详情导航，
该基准的列表只有普通网格，没有可直接复用的 Flutter 展墙。展示层接入工作台
已有的 `LibraryEditorialCanvas`，保留刷新、分页失败重试、合集目标和发现页签导航。
筛选使用右下角主题色扩展 FAB，保留安全区、文字提示和当前筛选标记。

所有展墙设置收进宿主原有标题或工具栏的一颗按钮，通过统一弹出面板调整。
发现、书签、阅读历史、书架、文件管理器和阅读页列表不再在正文前单独铺设置行。
发现列表住在页签内时移除重复的页面标题栏，设置登记到所属页签组的工具栏；
横向标签条和竖向标签轨共用一份入口，切换、关闭与分屏按各组当前标签取工具。
独立列表路由仍保留自己的 AppBar。展墙入口改为调色盘图标，与条目视图模式区分。
卡片目标宽度、高度、间距与图片尺寸保存到原来的各用途偏好键，列数按面板实际
宽度计算。原图比例继续用已有图片解码结果，不新增图片请求或另写布局算法。
宽度调节前置到设置首组，范围为 80～420dp，并显示当前每行格数；2～6 格快捷项
按实际内容宽度反算目标尺寸，不存第二份固定列数。宽卡占两格，三格可排两格宽卡
与一格普通卡，缩窄窗口自动减列。发现默认目标宽度使用通用的 140dp。

设置面板使用 M3E 分组列表、滑杆与动作按钮，数值独立标记，尺寸/布局/权重按组
收纳。面积依据复用既有 CommonPopupBox/Menu 的锚点托盘弹簧，不使用 Flutter
原生下拉路由；减少动画、键盘选择、取消/应用与原偏好持久化继续保留。

发现页补接现有 `LibraryBookDetails` / `EmbeddedComicInfo`，封面右下角信息键直接
原位展开，与封面打开发现新页签共存。通用展墙设置增加「点击封面」的两种行为：
向下展开详情，或交还宿主打开详情页；书签、历史沿用原有详情视图，发现沿用现有
页签导航。选择按原来的位置键持久化并参与展示偏好同步，旧数据缺项时保持宿主
原先默认。展墙、自定义封面的内层手势与普通列表/网格共用同一判决，信息键独立
展开；文件夹仍然导航，禁用态不响应。发现内联详情同时传递合集目标，避免展开
后收藏操作丢失上下文，详情加载、章节和下载仍复用已有实现。

本轮封面行为验证：共享展墙、普通视图、设置持久化/同步、发现页签与详情回归
共 98 项通过；220dp 暗色大字号及减少动画设置可用，静态分析无问题。
本轮 macOS Debug 构建通过；尚未进行真实图源手动验收。

通用层只接收稳定 id 到数值的信号，以及宿主声明的标签名、默认权重。发现层
沿用现有喜欢标签、画师与汉化匹配器提供信号，默认权重为 3、2、1；用户可改为
0～10，0 关闭。多项命中取最强信号，标签只改变面积、保持图源原顺序；单列也
通过高度体现层级。未知信号保留，后续新增种类无需修改展墙的判决算法。

验证：相关 widget/单元回归 177 项通过，另有 3 项明暗主题、窄屏和大字号预览通过；
本次文件静态分析无问题；macOS Debug
构建成功。本机 Flutter 3.47.4 / Dart 3.13.3，仓库锁定 3.47.6。扩大到整个发现模块
时另有 6 项既有测试失败，涉及插件胶囊测试未初始化 ObjectBox 与页签关闭悬停
查找器。尚未进行真实图源与各平台交互验收。

## 发现列表滚动与浏览位置扩展（2026-10-16）

继续复用 Breeze `68bebb2b` 的插件分页 Cubit、请求封装与筛选状态，在其上增加
直接请求目标页、请求代次隔离与可见条目页码索引。该基准没有浏览位置恢复与
通用浏览菜单；本仓以薄宿主接入已有展墙及普通视图，不新增平行分页状态机。
右下角菜单收纳筛选、展示设置、上一页/下一页、快速跳页和恢复上次位置；
总页数仅采用插件明确返回的 totalPages/pageCount，未知时只显示当前页。
位置按插件、函数和筛选参数隔离，自动保存页码、首个可见条目及视口偏移，
恢复直接请求该页。记录最多保留 128 组，不保存封面或漫画列表。

macOS Profile 现场采样显示主线程反复在封面布局中解析喜欢画师名单。沿用原
匹配优先级，缓存当前名单的解析与索引、分模式兜底词和最多 512 条文字匹配结果，
名单内容改变即失效。发现 scheme 的纵向内容改用同一 CustomScrollView 的
SliverList/SliverGrid，避免 shrinkWrap 嵌套网格全量创建。展墙继续使用已有懒列表，
只登记实际挂载的卡片锚点，替换页时清理旧比例与锚点。

验证：45 项定向测试通过，覆盖 2000 条内容持续滚动时视口外回收、直接跳页、
迟到响应隔离、真实可见页码、条目偏移恢复、重新进入不覆盖旧记录、菜单验证
和 Dock 避让。macOS Profile 包构建成功。尚未重启用户正在运行的应用进行真实
图源滚动帧率复测。本机仍为 Flutter 3.47.4，仓库锁定 3.47.6。

扩大回归还遇到未涉及路径的测试问题：发现详情测试的页签 mock 缺少新封面参数；
时间线查找器把同名分组与卡片文字一起计数；图片比例测试让装饰拼贴覆盖了主卡片
几何回报，或把装饰图的 cover 与主图的 contain 混为一谈。保留这些失败记录，
不将本轮定向通过解释为全仓测试通过。


## 标签搜索触发的界面阻塞（2026-10-16）

继续使用 Breeze 的标签动作、搜索请求和历史记录接口；图片休眠与喜欢画师高亮
属于本仓扩展，没有新增平行搜索流程。macOS Profile 两次现场采样分别命中
`ImageSleep.build → globalSetting → ObjectBox / jsonDecode` 与
`AllChipWidget.build → chipIsFavorite → _parseFavorite`。搜索结果保存历史会发布
全局设置，原有宽泛监听扩大了页面重建开销。

图片在无休眠 scope 或 scope 清醒时直接返回；休眠时只订阅 Cubit 内存中的开关。
详情标签与发现宿主只监听实际使用的设置字段，标签文字转换显式传入内存中的
简繁模式，避免每段文字读库。标签高亮复用封面匹配已经准备好的收藏名单与索引；
仍按名单内容失效，保留原地修改支持和既有匹配规则。

本地 debug 测试基准（1000 个收藏、100 个不命中标签、连续 3 次匹配）从 8037 ms
降至 44 ms；这是匹配函数计时，不代表端到端搜索延迟或 macOS 实机帧率。
定向回归覆盖无数据库图片/标签构建、标签点击、历史写入不重建相关组件、设置开关
与收藏变化即时生效，以及搜索历史浮层和键盘行为。尚未重启运行中的用户应用，
新版真实图源搜索交互仍需复测。

验证结果：80 项定向测试通过，所改组件与新增测试静态分析通过，macOS Profile
包构建成功。本机 Flutter 3.47.4 / Dart 3.13.3，仓库锁定 3.47.6。

验证时另遇工作区在途的 `goToComicRead` 新增可空导航参数仍要求位置实参，导致
旧调用无法编译；将该参数改为可选位置参数以保持兼容，该处与其他阅读修改一起
留在工作区，不纳入本轮性能提交。

## 标签与单图源搜索结果展墙适配（2026-10-16）

标签搜索和单图源搜索沿用 Breeze 的 `SearchResultPage`、搜索 Bloc、筛选、历史与
跳页接口，结果呈现改为复用发现页已有的 `DiscoverLibraryView` 与封面映射。
该上游基准只有普通网格，没有本仓的展墙与原位详情，因此只增加呈现宿主薄适配，
不新增搜索或详情业务。封面右下角信息键使用 `LibraryBookDetails` /
`EmbeddedComicInfo` 原位展开；展墙偏好按图源隔离，设置入口登记到页签工具栏，
独立路由保留右下角菜单。聚合搜索的按来源分组布局不在本轮变更范围内。

沿用共享展墙的懒列表与普通视图回退；加载更多、失败重试保留同一画布和滚动控制器，
重试请求最后成功页的下一页。设置订阅仅选择高亮与简繁模式，保存搜索历史不触发
整面高亮信号重算。

## 本地设置与数据备份适配（2026-10-13）

沿用 Breeze 的 ZIP 备份、文件选择和 Rust 流式打包接口，增加同步页内直接操作和
设置首页「本地导入/导出」入口；无需配置 WebDAV / S3。没有另建归档协议或备份页面。

全局设置导出、导入复用同步设置块白名单；ObjectBox 输出的字符串与解码对象同时过滤。
旧全量备份导入也先过滤，本机路径、代理、应用锁、同步凭据和窗口几何保留。
工作台和展墙偏好分别复用 WorkspaceSyncCodec 与 LibraryPresentationPreferences；
移动端沿用同步规则保留本机工作台几何与临时状态。

导入前校验格式、ObjectBox 实体及附加设置，数据库替换放在同一写事务中。
不包含下载文件时保留本机下载记录、下载目录和链接，不引入备份设备的下载记录。
继续支持上游无格式版本字段的旧备份，以及可选的漫画文件备份。

## 展墙空隙填充（2026-10-14）

展墙的行高取同行最高的一块，宽卡又占两格，于是矮卡下方与行尾都会留下不规则空白。
新增 `LibraryPresentation.gapFill` 四档（不填充 / 随机图形 / 小组件 / 组件 + 图形，默认最后一档），
**并且每一项都能单独开关**：`gapShapes` 单独管随机图形，`gapWidgets` 是一张
`id → bool` 表管每一款组件（缺键 = 开，所以以后新增组件不需要迁移）。设置弹层里
先选总口径、再列子开关，子开关只在当前口径下真能改变输出时才出现 ——
选了「不填充」还留一颗「随机图形」开关就是装饰品。生效口径的换算在
`libraryGapMode`（shapes 档关掉图形 = 不填；both 档关掉图形 = 只剩组件），
套件过滤在 `libraryGapKit`，两者都是纯函数并有全表测试。
与其它展墙偏好同走 `rossi.library.presentation.*`；旧载荷缺该键按默认档解析，
只带该键的记录也算「可用」（`LibraryPresentationPreferences.parsePresentation`），
`gapWidgets` 的键在合并前按 id 排序，插入顺序不影响合并结果。

* 随机图形复用本仓已有的 `ExpressiveBlob`（种子决定轮廓，同一位置永远同一形状）
  加一枚语义中性图标；轮廓只在槽位矩形内侧变形，不压相邻卡片。
* 小组件是**按空隙尺寸现算的汇总卡**，共 11 款（封面拼贴 / 接着看 / 连续天数 /
  近 7 日 / 时段 / 常见标签 / 在读 / 来源 / 近 3 天 / 体积 / 条目数），
  只读 `LibraryEntry` 已有字段，不查 ObjectBox、不接 Bloc。
* 没有复用卡片注册表里的洞察卡，三条都量过：`CollapsibleCard` 的标题行约 48 高，
  而竖向余量常见只有 64~120；`DailyTrendView` 写死柱区 `height: 124`、
  且 `maxWidth < 364` 时按 364 起横向滚动，两张 `InsightMetric` 是 padding 14 +
  `headlineMedium` 没有降级分支；数据侧 `HistoryInsightsWindow` 直连
  `objectbox.unifiedHistoryBox`，并把 `insight_components.dart → global_setting.dart`
  拖进依赖链，而「前 7 日 / deltaPercent」要的整库窗口一墙条目里根本没有。
  ⇒ 注册卡在这一层**不可用**（尺寸与依赖两条都不满足），不是同名模块的平行实现。
* 注入点只有一个：`LibraryEditorialCanvas.gapWidgets`（宿主可整替换或传 `const []` 只留图形），
  `defaultLibraryGapWidgets()` 返回 `List.unmodifiable`。
* 并存档里每款组件一面墙最多出现一次，装不下或已经用过的槽位改用随机图形 ——
  「防止小组件重复出现」落在这一条，判据在 `libraryGapChoices`。

验证：`test/workspace/library_gap_fill_test.dart` 13 项（槽位几何、三档口径、组件去重、
偏好往返与坏值回退、每款组件在自己下限尺寸 + 2 倍字号下不溢出）；
展墙端到端三档对照写在 `test/workspace/library_gap_wall_fill_test.dart`。

## 阅读器三块：页面排序 / 幻灯片 / 放大镜（2026-10-14）

顶栏 `_kReaderComingSoon` 里那三颗占位（页面排序、幻灯片、放大镜）接成了真面板。
上游 `deretame/Breeze` 没有这三块（`git grep -iE "magnif|loupe|slideshow" upstream/main -- lib` 零命中），
所以按 AGENTS §13 第 3 条属本地新建；但**判据尽量取上游 mImageViewer 那份**，取不到的原因逐块写明。

### 放大镜：几何照抄上游，只有像素来源换了

`lib/page/comic_read/model/reader_magnifier.dart` 是 `vendor/mimageviewer/src/ui_fullscreen.rs`
里那套 loupe 的逐行移植：常数 `LOUPE_SIZE/ZOOM/OFFSET`（`:328-333`）、
`loupe_sample_mapping`（`:3821-3846`，边缘收缩绘制矩形以保持单位屏幕像素的倍率不变）、
窗口落点与出屏翻转（`:41811-41822`）、「帧没就位/旋转页不做」这类闸门（`:41794-41797`）。
行为规格也照上游的测试（`:66142-66175`）在 Dart 侧复写了一份。

上游那份**不能直接搬**：它画的是 egui `painter.image(id, image_rect, uv_rect)`，
消费的是显存纹理 handle；本仓的对应物是 `Canvas.drawImageRect` + 一份 `ui.Image`。
换的是取样端，不是判据。两处有意的偏离：窗口形状从方框改成圆形（触屏优先的读法，
圆镜头一眼就是「放大镜」），以及上游的全景模式闸门在这里没有对应物（本仓还没有那一档）。

### 幻灯片：计时复用本仓那套控制器纪律，策略取上游

结束策略三档取自 `vendor/mimageviewer/src/settings.rs` 的
`SlideshowEndAction { Stop, LoopFolder, NextFolder }`，第三档在本仓的对应物是「续下一章」
（无缝拼接已经把邻章接进来了，不需要新机制）。「帧没解出来就别推进」照
`current_slideshow_frame_ready`（`:35644`）落成 `ReaderSlideshowTick.hold`。
计时器不复用 `ReaderAutoReadController`，而是**同纪律另建一个**
（`controller/reader_slideshow_controller.dart`）：两者节奏不同 ——
一个是按像素连续滚，一个是整页驻留，共用一张表会让改间隔连带改掉滚屏节奏。
自动滚屏那一份原样保留，没有缩它的功能。

### 页面排序：章节内页序，本仓与上游都没有对应物

上游没有「章内页重排」这一块：mImageViewer 的 `display_order: &[usize]` 是**索引间接层**
（`ui_helpers.rs:1987` 的 `adjacent_slideshow_idx` 那条路径），本仓借的正是这个「不改页表、
只加一层排列」的形状 —— 每一页仍带自己的 `chapterPageIndex`（源下标），
所以尺寸缓存、历史、预取、OCR 覆盖层都不必知道排序存在。

自然序那一档的**算法**与 `rust/local_core/src/ui_helpers.rs` 的 `natural_sort_key` 同源，
但在 Dart 侧另写了一份（`model/reader_page_order.dart`）。不可用的理由是可达性而不是能力：
这一档要在 `buildColumnEntries` / `buildRowEntries` 里每次构建都被问一遍，
走 Rust 就得为它新开一条 `#[frb(sync)]` 桥、并让每次条目构建都过一次 FFI；
而页表最长几百个名字，纯 Dart 的比较代价低于那条桥。两份实现的口径差异写在了函数注释里
（`local_core` 保留「数字块先于文本块」，Dart 这份跟它一致）。
后续若把章内排序下沉到 Rust，这两份必须收敛成一份，判据以 Rust 侧为准。

验证：`test/comic_read/reader_page_order_test.dart`（自然序与排列校验、按章隔离、
页表变短退回原样）、`test/comic_read/reader_slideshow_policy_test.dart`（结束策略与
帧就绪顺序）、`test/comic_read/reader_slideshow_controller_test.dart`（分派与计时器不重启）、
`test/comic_read/reader_magnifier_test.dart`（取样几何与边缘不改变倍率）。

## 自动裁边与 JPEG 降噪高级设置（2026-10-14）

沿用 mImageViewer `margin_fit.rs` 和 RealPLKSR 1× 分块执行器；未复制 egui UI。
Flutter 新增 `AutoTrimSettings` 薄适配：容差交给已有 Rust 检测入口，裁切上限与
安全留边只能向外扩大内容矩形，默认保持上游 24 / 20% / 0.6%。检测参数变更
会使结果缓存与显示几何失效。条漫上下边保留完整，列表项同步按内容宽高比重排，
位图、GPU 与译文叠层共用 `PageTrimTransform`，放大镜取样也使用裁边后的 UV。

JPEG 降噪新增独立分块档位与按文件头选择仅 JPEG；在线原图解析后由
`EnhancedOnlinePage` 观察设置并切换另存的结果。本地呈现器使用相同降噪参数。
缓存身份包含源文件版本、模型修订、参数和阶段顺序；通用在线下载管线不再覆写
原文件。模型管理状态跨面板共享，包含进度（总长度未知时不定进度）、校验、
已安装大小、失败/重试及移除。权重版本固定为 vendor 的 bb6ca0c6，28.2 MiB；
SHA-256 校验通过后才安装，更新失败保留旧权重。

UI 使用 Material 3 Expressive 分组、主题色、胶囊操作、弹簧展开、触觉反馈，
支持系统减少动画与大字号。上游没有 Flutter 跨在线/本地的缓存显示与设置宿主，
因此保留这层适配；并未宣称移植上游完整模型管理、TensorRT 或全部后处理。
当前 RealPLKSR 推理后端支持 macOS / iOS / Windows / Linux；Android 入口明确
披露未具备该后端。拆分出的半页仍按既有安全策略不裁边。

两张设置卡的预览默认折叠，不加载位图。展开时从当前阅读页读取已经应用的内容矩形
与增强结果，只在没有当前页时加载内置示例。预览缩略图最长边 720，收起、换页和退出
时释放；不重新运行裁边检测或整页 AI 推理。示例素材及来源仍记录在
`asset/image/processing_examples/`，可用 `script/generate_image_processing_examples.py`
重新生成。

2026-10-14 显示裁边修正：继续复用上游检测器，Flutter GPU 合成层对已有 Texture
按内容区裁剪、等比变换和居中，无需修改原图或重写纹理。高度受限、倍率为 1 时也要
裁掉区外余白，不能用“是否放大”代替“是否裁边”的判断。GPU 检测采样改为最长边
1000；CPU/GPU 检测共享请求身份，过期结果丢弃。当前页检查读取阅读器的有效书级
开关与布局矩形，区分未开启、待检测、无需裁边和已应用，避免预览另算一份结果却
宣称已经上屏。文件版本切换时清除旧布局结果。验证覆盖像素裁剪、GPU 节点切换/
重复重建、长条采样、请求去重/过期、预览懒加载与既有原生检测。

## 阅读器悬停唤出修正（2026-10-14）

悬停唤出是本仓的 Flutter 扩展；当前 Breeze 上游没有对应感应层，mImageViewer 的
egui 输入体系不能用于 Flutter 命中测试。保留现有控制器与延时策略，以
`ReaderHoverStack` 统一把感应层放在阅读叠层最后，解决页码信息底板等兄弟节点
截断命中后无法唤出的问题。提示装饰使用 IgnorePointer，感应带透传按钮、点击与
滚动；带内移动可恢复唤出状态。控制器与感应几何共用已经合并的本漫有效设置，
不在鼠标每次移动时重算整份设置。

验证：悬停控制器与 widget 回归共 28 项通过，覆盖实际 PageCountWidget 顶部/底部
底板、栏体阴影、按钮点击、滚动透传、本漫覆盖、状态恢复及动画开关下的连续显隐。
连续显隐测试同时推进模拟时钟与更新页码；尚未实测高负载下的桌面窗口长期运行。


## 阅读泳道返回后的界面更新修正（2026-10-14）

现场在 macOS Profile 捕获：ReaderHoverController 与 ReaderCubit 已响应进入/离开，
ReaderChromeTransition 的 visible 却保持旧值。WorkspaceReaderHost 的 LayoutBuilder
作用域积压 dirty elements，渲染对象为 needsRebuild=true、needsLayout=false；改变
泳道尺寸才会再次执行回调。这是布局期间子树通知引发的调度问题，键盘归属与阴影
均不能解释该现场；输入绑定升级增加的泳道高亮/尺寸切换会暴露这条路径。

ReaderViewport 继续使用 Flutter AbstractLayoutBuilder 的约束、构造与重建作用域，
只将自身 performLayout 期间收到的再次布局回调合并到帧尾，下一帧正常处理。
不依赖定时轮询，不重挂局部 Navigator，不改变键盘编辑、模态或滚轮归属。
这是本仓工作台宿主的薄适配：Breeze 和 mImageViewer 没有可用于该 Flutter
布局调度场景的现成宿主。Flutter 修正相同调度后可移除此适配。

验证：布局期间通知的回归先在普通 LayoutBuilder 失败、替换视口后通过；47 项
定向测试涵盖真实阅读顶栏与实际透明度、跨泳道返回、输入框持有焦点、泳道内容
重建预算、点击/滚动及栏体连续显隐。独立 macOS Profile 场景中，普通 LayoutBuilder
的通知值到 2 而显示仍为 0；ReaderViewport 的通知与显示均到 2。应用 Profile 包
构建成功，静态分析通过。

## 文件管理器搜索与汇总条目的新页签行为（2026-10-16）

首次输入搜索词（防抖后）、回车和点选搜索历史均通过已有的
`fileManagerSearchInNewTab` 创建独立结果页签；同轮后续输入和回车复用该页签。
源目录与先前保存的搜索不再先被输入预览修改；创建期间的新输入会等页签就绪后
提交，连续回车不重复创建。达到页签上限时保留原目录且不记入搜索历史。

搜索结果（内容、树、分栏）与普通目录共用条目菜单，文件也支持“在新页签打开”。
书签、历史继续使用同一个 `FileManagerTabBridge`，传递原始路径；共用的落点解析
对目录打开自身，对文件打开所在目录并按新目录的路径/下标选中该文件。已知文件
类型优先于扩展名猜测，书签/历史在操作时查询文件类型，兼容无扩展名文件和带
归档扩展名的目录。插件条目没有本地路径时维持禁用。

沿用既有 Rust 搜索、页签和文件选中 API，仅适配 Flutter 入口与菜单。Breeze 没有
该工作台组件，mImageViewer 的原生 UI 不能直接用于 Flutter，未新增平行搜索或
文件导航实现。回归覆盖独立搜索、创建期间改词、连续回车、页签上限、三种结果
布局的文件/目录菜单，以及书签/历史共用通道的真实文件定位。

验证：141 项 widget 回归、239 条菜单/路径断言通过，本次涉及的 Dart 文件静态
分析无问题。使用本机 Flutter 3.47.4 / Dart 3.13.3（仓库锁定 3.47.6）；
尚未进行桌面应用的手动交互验收。
