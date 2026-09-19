# Rossi 文件管理器功能核对

核对日期：2026-09-19。目标是 NeoView 文件卡片与 mImageViewer 文件浏览能力的并集。
**当前尚未实现完整并集**；源码已存在、扩展名已识别、API 已暴露都不等于用户可以完成对应操作。

## 当前接通的操作

| 能力 | Rust 实现 | Flutter 入口与边界 |
|---|---|---|
| 多页签、切换、关闭、导航历史 | `FileManagerState`，最多 8 个页签 | 页签条；导航按钮 |
| 面包屑与路径编辑 | Rust 按平台路径组件投影；相对路径以当前页签为基准；所有成功跳转统一写入后退历史 | 点击祖先返回；点击当前段或编辑按钮输入路径；错误保留输入及旧目录；Esc 取消 |
| 内联目录列导航 | Rust 每页签保持开关、投影目录和选中态；只枚举当前路径最后三层，关闭时不枚举 | 可横向滚动的目录列；目录项点击跳转；使用 mImageViewer 适配层的自然排序与隐藏规则；暂不提供悬浮列宿主 |
| 固定、复制、关闭其他/左侧/右侧、恢复关闭 | 核心维护固定状态、关闭队列及能力标志；批量关闭跳过固定页签 | 页签菜单、恢复菜单；固定仅在当前会话有效 |
| 各页签搜索、筛选与视图独立 | 设置放在 Rust 的 `FileManagerTab` 中；复制和恢复带上设置及历史 | Dart 只保存快照和输入控件，不自行筛选或排序 |
| 名称搜索 | Rust 当前目录内、不区分大小写的名称匹配 | 回车提交；尚不是递归搜索、索引搜索或搜索结果页签 |
| 类型筛选 | 文件夹、归档、图片、视频、音频 | 类型菜单；基础枚举仍只包含 mImageViewer 识别的媒体与目录 |
| 排序 | 名称、类型、大小；升降序；文件夹优先 | 排序菜单；名称比较直接使用 mImageViewer `filename_sort::SortNameKey` |
| 隐藏项开关 | 调用 mImageViewer `fs_entry::should_hide_fs_entry`；列表、子文件名、穿透使用同一策略 | 浏览设置；内部元数据目录与 AppleDouble 仍不显示 |
| 穿透与子文件名 | 唯一目录链/归档、媒体目录、深度和循环保护；显示一个/全部子项 | 单击打开；文件夹按钮强制进入；尚无 Neo 内联分支抽屉与完整终点策略 |
| 列表和网格 | Rust 保持模式 | Flutter 布局；网格内长子项列表可滚动 |
| 归档双击 | 调用 `file_manager_open_archive` 验证并返回来源路径 | 双击一次只发送一个打开动作；单击沿用已有打开行为 |
| 无效目录操作回滚 | 会话在动作与快照都成功后才提交 | 错误保留当前可操作快照；初始化读取失败重试复用原会话 |
| 文件树面板状态机 | `FolderPaneState`、懒展开与 RAII 取消扫描、扁平行投影、游标键盘导航、激活路径同步 | 核心状态机就绪（`folder_pane.rs`）；待接 Flutter 虚拟列表与 UI 树组件 |
| Material 外壳 | 无业务逻辑 | 卡片及控件统一使用 `material_ui`，卡片自身提供带圆角的 Material |

## 直接复用的源函数与平台适配

来源为 `vendor/mimageviewer/src/folder_tree.rs`、`folder_pane.rs`、`fs_entry.rs`、`filename_sort.rs` 的源码副本，
沿用原模块与函数名，详见 [溯源清单](local-core-vendored-modules.md)。
本次增加的适配为：非 Windows 路径不折叠大小写/反斜杠；Unix 符号链接跟随目标分类；
穿透与上游 DFS 的循环键仍先 canonicalize，在 Unix 上保留路径大小写/反斜杠；Windows 补齐自然排序所需的
`Win32_Globalization` feature；文件树面板（`folder_pane`）委托 `file_tree::get_available_roots()` 获取跨平台挂载卷与主目录，
单元测试支持 Unix 路径等效验证。数据库已有 `path_key` 的键格式未改动。

`archive_converter.rs` 目前只是扩展名判定适配，**没有搬入实际的归档转换器**。
双击返回 7z/LZH/PDF 路径不代表 Reader 已能读取它们。现有 LocalSource 为图片目录、ZIP/CBZ、
非固实且未加密 RAR/CBR 提供读取；视频/音频仍缺阅读器适配。

## 尚未接通的并集项

| 来源范围 | 尚缺的能力 |
|---|---|
| Neo 页签与导航 | 页签布局/宽度与跨重启持久化、最近访问页签策略、搜索/EFU 受保护页签、列导航的悬浮宿主/复制路径操作、文件树 UI（Rust 状态机已就绪） |
| Neo 搜索与排序 | 子目录递归与增量搜索、取消、路径/标签条件与历史、日期/随机/评分等排序、目录专属排序设置 |
| Neo 穿透 | 内联分支展开、分支数量限制、完整终点类型选择及激活身份跟踪 |
| Neo 展示 | 封面、横幅、详情、多图/马赛克、缩略图与悬停预览、尺寸/标题换行偏好 |
| Neo 文件操作 | 多选、键盘操作、剪切/复制/粘贴、移动/重命名/新建/回收站、监听、拖拽、空白区双击返回 |
| Neo 扩展信息 | 标签、评分、EMM、Clipm 等源功能及对应服务适配 |
| mImageViewer | 文件树 UI（Rust 状态机已就绪）与 DFS 相邻目录 UI、书签/历史/标签/评分/智能文件夹/全局搜索入口、系统文件操作与拖放 |
| mImageViewer 格式 | 实际归档转换/密码/进度/缓存、完整 PDF/音视频打开流程与各平台依赖 |
| 移动端 | Android 权限/SAF，iOS Documents/安全作用域访问；不能用桌面根目录枚举代替 |

Neo 对照入口：`Xiranite/src/nodes/neoview/features/panels/cards/folder/` 的
`FolderTabsHost`、`FolderTabBar`、`FolderToolbar`、`FolderSearchPanel`、`FolderTreePanel`、
`FolderContextActions`、`FolderInlineBranchPanel` 等。mImageViewer 对照入口除上述源函数外还有
`archive_converter`、`archive_cache`、`global_search`、`bookmark_browser` 等；这些尚未接入的模块
不能计入 Rossi 已完成能力。

## 验证范围

Rust 测试覆盖页签空操作、批量关闭保护、复制/恢复的设置和历史、失效目录回滚、
搜索/筛选/排序、隐藏策略一致性、子文件名目标、Unix 符号链接循环、
面包屑/路径编辑的统一历史与错误回滚、相对路径和符号链接父目录、列导航的按页签独立状态。
Widget 测试使用真实文件卡片、应用同款 Material 根和 FRB 替身，验证不同卡片宽度、
多条子文件名、搜索转发、页签操作、按钮能力、会话重试和单击/双击互斥，
以及面包屑/目录列点击转发、窄卡片路径编辑和错误恢复。
这不替代五个平台的实际运行验证，也不验证未接通的 Reader 格式。

2026-09-19 本机验证结果：

- `cargo test -p rossi_local_core -p windcore --lib --quiet`：173 + 27 项通过。
- `flutter test test/workspace/file_manager_card_test.dart --reporter expanded`：14 项通过。
  包括 260/340/700 像素宽度、260/760 像素独立面板高度；低高度面板工具区可滚动。
- 文件卡片、卡片外壳和对应测试的 `dart analyze`：无问题。
- `python3 script/sync_vendored_modules.py`：五份源码与固定版本的差异均已登记。
- `cargo build -p windcore --release`：成功，更新本地启动时会加载的动态库。
