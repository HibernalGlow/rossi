//! 文件管理器的对外数据结构：FRB 快照、页签、条目与目录树投影。

use crate::api::local::LocalRootLocation;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerInternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerViewMode {
    Compact,
    CoverList,
    MosaicList,
    Details,
    CoverGrid,
    MosaicGrid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerSortField {
    Name,
    Type,
    Size,
    Date,
    Random,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerSortOrder {
    Ascending,
    Descending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerEntryFilter {
    All,
    Folders,
    Archives,
    Images,
    Video,
    Audio,
}

#[derive(Debug, Clone)]
pub struct FileManagerTab {
    pub id: u64,
    pub title: String,
    pub path: String,
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub pinned: bool,
    pub can_close: bool,
    pub can_close_others: bool,
    pub can_close_left: bool,
    pub can_close_right: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerChild {
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    pub is_archive: bool,
    pub is_image: bool,
    pub is_video: bool,
    pub is_audio: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerEntry {
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    pub is_archive: bool,
    pub is_image: bool,
    pub is_video: bool,
    pub is_audio: bool,
    pub size: u64,
    pub modified_secs: i64,
    pub has_children: bool,
    /// NeoView 的「显示内部条目」投影。它不改变父目录列表，只为 UI 提供一小段
    /// 可点击的上下文提示。
    pub child_names: Vec<FileManagerChild>,
    /// 搜索结果页签里，这条命中在搜索根之下的目录（`/` 分隔）。普通浏览时为 `None`
    /// —— 那时父目录就是当前目录，写出来只是噪音。
    pub search_directory: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileManagerBreadcrumb {
    pub path: String,
    pub name: String,
    pub is_root: bool,
    pub is_current: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerDirectoryChoice {
    pub path: String,
    pub name: String,
    pub selected: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerDirectoryColumn {
    pub path: String,
    pub name: String,
    pub entries: Vec<FileManagerDirectoryChoice>,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileManagerSnapshot {
    pub session_id: u64,
    pub max_tabs: u8,
    pub can_create_tab: bool,
    pub generation: u64,
    pub active_tab_id: u64,
    pub active_path: String,
    pub can_go_up: bool,
    pub breadcrumbs: Vec<FileManagerBreadcrumb>,
    pub directory_columns_enabled: bool,
    pub directory_columns: Vec<FileManagerDirectoryColumn>,
    pub tabs: Vec<FileManagerTab>,
    pub recently_closed: Vec<FileManagerTab>,
    pub entries: Vec<FileManagerEntry>,
    pub roots: Vec<LocalRootLocation>,
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: FileManagerInternalItemsMode,
    pub max_depth: u8,
    pub view_mode: FileManagerViewMode,
    pub show_hidden_files: bool,
    pub search_query: String,
    /// 名称之外是否连同「相对搜索根的路径」一起匹配。
    pub search_in_path: bool,
    /// 多个词元的结合方式（false = AND，true = OR）。
    pub search_or_mode: bool,
    /// 递归搜索是否连同子目录。关掉时 `search_max_depth` 不参与。
    pub search_include_subfolders: bool,
    /// 递归层数上限（实际生效值再被核心的 `MAX_SEARCH_DEPTH` 夹一次）。
    pub search_max_depth: u8,
    /// 当前页签是不是「搜索结果页签」：列表画的是上一次遍历的命中，而不是目录。
    pub search_active: bool,
    /// 这批命中对应的查询（说明文案与页签标题用）。
    pub search_result_query: String,
    /// 检视过的条目数（含未命中）。区分「没有」与「还没扫到」。
    pub search_scanned: u32,
    /// 命中总数，可能因上限截断而大于列表长度。
    pub search_matched: u32,
    pub search_truncated: bool,
    pub search_cancelled: bool,
    /// 「把当前搜索存成页签」是否可用（需要有结果）。
    pub can_save_search_tab: bool,
    pub entry_filter: FileManagerEntryFilter,
    pub sort_field: FileManagerSortField,
    pub sort_order: FileManagerSortOrder,
    pub directories_first: bool,
    /// 用户指定的主页；`None` 时工具栏的主页键应禁用。
    pub home_path: Option<String>,
    pub is_home: bool,
    pub can_set_home: bool,
    /// 「临时排序」：排序变更不写回当前目录的视图状态。
    pub sort_temporary: bool,
    /// 目录级排序偏好是否可用（`remember_view_state`）。
    pub can_sort_preference: bool,
    /// 「记住每个目录的视图与排序」总开关的当前值。关闭时本会话不读不写目录偏好。
    pub remember_view_state: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerActionResult {
    pub snapshot: FileManagerSnapshot,
    /// 非空时表示 UI 应该把该路径交给 Reader；浏览器自身仍停留在原目录。
    pub opened_path: Option<String>,
    /// 核心拥有的上下本游标；UI 只需随阅读目标透传。
    pub book_navigation_json: Option<String>,
}

/// 文件树的一行：核心 `FolderPaneRow` 的字符串投影。
#[derive(Debug, Clone)]
pub struct FileManagerTreeRow {
    pub path: String,
    pub name: String,
    pub depth: u32,
    pub expanded: bool,
    /// 子目录正在后台枚举：这一行的箭头该转圈。
    pub loading: bool,
    /// 「有子目录，或者还没查过」。确认是空目录时 UI 才收起箭头。
    pub may_have_children: bool,
    pub is_active: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileManagerTreeSnapshot {
    pub rows: Vec<FileManagerTreeRow>,
    /// 仍有目录在枚举中。UI 据此决定要不要隔一会儿再问一次。
    pub has_pending: bool,
}
