//! 可迁移的文件管理器状态机。
//!
//! 这一层只依赖 `std::fs` 和本 crate 已有的目录枚举器，不依赖 Flutter、egui 或
//! 任何具体 UI。Rossi 的泳道卡片、桌面边栏以及后续的 Tauri / WASM 外壳都应该只
//! 负责把这里的快照画出来并转发动作。
//!
//! 目录枚举与自然排序沿用 `file_tree`（其过滤、排序规则对应 mImageViewer 的
//! `folder_tree` / `filename_sort`），状态机则把 NeoView 的多页签、穿透和子文件名
//! 投影收拢到一个可测试的 Rust API 中。

use std::collections::{HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Result, anyhow};

use crate::file_tree::{FileTreeNode, list_directory_with_hidden};

/// NeoView 文件卡片默认的页签上限。上限属于核心状态，而不是 Dart 的布局常量，
/// 这样其它 UI 不会因为自己的按钮实现而出现不同的行为。
pub const MAX_FILE_MANAGER_TABS: usize = 8;
pub const MAX_RECENTLY_CLOSED_TABS: usize = 16;
pub const MAX_PENETRATION_DEPTH: usize = 32;
/// 一次递归搜索最多交出多少条。与 NeoView 的 `SEARCH_RESULT_LIMIT` 同值：
/// 再多的命中在这一屏里也看不清，而截断可以让遍历提前结束。
pub const MAX_SEARCH_RESULTS: usize = 512;
/// 递归搜索的目录深度上限。穿透用 `MAX_PENETRATION_DEPTH` 是有意的单链，
/// 这里按层展开，取更小的值以免一次键入扫完整棵盘树。
pub const MAX_SEARCH_DEPTH: usize = 12;
/// 默认递归深度：`库/分组/本/页` 这种常见结构够用。
pub const DEFAULT_SEARCH_DEPTH: usize = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum ViewMode {
    #[default]
    Compact,
    CoverList,
    MosaicList,
    Details,
    CoverGrid,
    MosaicGrid,
}

/// 字段级排序沿用 NeoView 文件卡片的可切换排序模型。名称排序本身仍交给
/// mImageViewer 的 `filename_sort`，所以 Windows 与其它平台不会各自出现一套自然排序。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SortField {
    Name,
    Type,
    Size,
    /// 修改时间。目录的 `modified_secs` 同样参与比较，不做目录/文件特殊处理。
    Date,
    /// 稳定洗牌。顺序由 `FileManagerSettings::shuffle_seed` 决定，同一目录在
    /// 两次快照之间不会因为重新求值而跳动；重新洗牌只发生在切到该字段或刷新时。
    Random,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SortOrder {
    Ascending,
    Descending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum EntryFilter {
    All,
    Folders,
    Archives,
    Images,
    Video,
    Audio,
}

/// 一个目录「上次怎么看的」的完整快照：目录级视图状态的持久化单元。
///
/// **为什么不复用 reader 侧的 `crate::settings::FavoriteViewState`**：那是 viewer 的表示状態
/// （网格列数、缩略图比例、翻页方向、阅读流），视图口径只有 Thumbnail / Details 两档。
/// 文件管理器有六种视图模式，经那套映射往返会把「紧凑列表 / 封面列表 / 横幅」全部塌成
/// 「详细信息」——所以这里要一套自己的、逐字往返的字段。
///
/// 字段范围＝「用户会期望按目录记住」的那些：视图模式、排序字段与方向、类型筛选、
/// 目录优先、显示隐藏项。`shuffle_seed` 跟着排序一起记，否则「随机」在重启后会换一副顺序。
/// 搜索词、穿透深度、目录列开关**不进**这里：它们描述的是这次浏览动作，不是这个目录的偏好。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct FileManagerViewState {
    pub view_mode: ViewMode,
    pub sort_field: SortField,
    pub sort_order: SortOrder,
    pub shuffle_seed: u64,
    pub entry_filter: EntryFilter,
    pub directories_first: bool,
    pub show_hidden_files: bool,
}

impl FileManagerViewState {
    pub fn from_settings(settings: &FileManagerSettings) -> Self {
        Self {
            view_mode: settings.view_mode,
            sort_field: settings.sort_field,
            sort_order: settings.sort_order,
            shuffle_seed: settings.shuffle_seed,
            entry_filter: settings.entry_filter,
            directories_first: settings.directories_first,
            show_hidden_files: settings.show_hidden_files,
        }
    }

    /// 目录视图状态的唯一写入口。
    ///
    /// 「临时排序」只应该活在当前画面里，所以置位时把上一次锁定的排序与种子盖回去，
    /// 避免它在离开目录（`transition_view_state_for_path`）或另一次 capture 时顺带落进目录偏好。
    pub fn from_settings_keeping_locked_sort(settings: &FileManagerSettings, base: &Self) -> Self {
        let mut state = Self::from_settings(settings);
        if settings.sort_temporary {
            state.sort_field = base.sort_field;
            state.sort_order = base.sort_order;
            state.shuffle_seed = base.shuffle_seed;
        }
        state
    }

    pub fn apply_to_settings(&self, settings: &mut FileManagerSettings) {
        settings.view_mode = self.view_mode;
        settings.sort_field = self.sort_field;
        settings.sort_order = self.sort_order;
        settings.shuffle_seed = self.shuffle_seed;
        settings.entry_filter = self.entry_filter;
        settings.directories_first = self.directories_first;
        settings.show_hidden_files = self.show_hidden_files;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSettings {
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: InternalItemsMode,
    pub max_depth: usize,
    pub view_mode: ViewMode,
    pub show_hidden_files: bool,
    pub search_query: String,
    /// 查询词元在「条目名 + 相对根目录的路径」上匹配，还是只看条目名。
    /// 当前目录内的条目相对路径为空，因此单层浏览时该开关不改变结果。
    pub search_in_path: bool,
    /// 多个 include 词元的结合方式：`false` 为 AND（默认），`true` 为 OR。
    /// 否定词元（`-词`）在两种模式下都是硬性排除。
    pub search_or_mode: bool,
    /// 是否连同子目录一起搜。关掉时只在当前这一层找（`search_max_depth` 被忽略）。
    pub search_include_subfolders: bool,
    /// 递归搜索的层数上限，实际生效值再被 [`MAX_SEARCH_DEPTH`] 夹一次。
    pub search_max_depth: usize,
    pub entry_filter: EntryFilter,
    pub sort_field: SortField,
    pub sort_order: SortOrder,
    pub directories_first: bool,
    pub directory_columns_enabled: bool,
    /// 「临时排序」：置位时排序变更只影响当前画面，不写回当前目录的视图状态。
    /// 关闭时会把当前排序固化成该目录的偏好（工具栏的「锁定当前目录排序」）。
    pub sort_temporary: bool,
    /// `SortField::Random` 的洗牌种子。0 表示尚未洗过牌。
    pub shuffle_seed: u64,
}

impl Default for FileManagerSettings {
    fn default() -> Self {
        Self {
            penetration_enabled: false,
            show_child_names: true,
            internal_items_mode: InternalItemsMode::Single,
            max_depth: 3,
            view_mode: ViewMode::Compact,
            show_hidden_files: false,
            search_query: String::new(),
            search_in_path: true,
            search_or_mode: false,
            // 默认只搜当前一层：一次键入就扫整棵树的第一印象太差。要不要连子目录
            // 一起搜是搜索框上那颗开关的职责（并可被全局设置记住默认值）。
            search_include_subfolders: false,
            search_max_depth: DEFAULT_SEARCH_DEPTH,
            entry_filter: EntryFilter::All,
            sort_field: SortField::Name,
            sort_order: SortOrder::Ascending,
            directories_first: true,
            directory_columns_enabled: false,
            sort_temporary: false,
            shuffle_seed: 0,
        }
    }
}

impl FileManagerSettings {
    /// 回到「没有目录偏好」的公共值。
    ///
    /// 与 mImageViewer 的 `clear_favorite_view_overlay` 同一分工：切换位置时先干净回退，
    /// 再套用新位置的 overlay，避免上一个目录的局部修改在无匹配目录上漏出来。
    pub fn reset_view_fields_to(&mut self, common: &Self) {
        self.view_mode = common.view_mode;
        self.sort_field = common.sort_field;
        self.sort_order = common.sort_order;
        self.shuffle_seed = common.shuffle_seed;
        self.entry_filter = common.entry_filter;
        self.directories_first = common.directories_first;
        self.show_hidden_files = common.show_hidden_files;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerChild {
    pub path: PathBuf,
    pub name: String,
    pub is_dir: bool,
    pub is_archive: bool,
    pub is_image: bool,
    pub is_video: bool,
    pub is_audio: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerEntry {
    pub node: FileTreeNode,
    pub children: Vec<FileManagerChild>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerBreadcrumb {
    pub path: PathBuf,
    pub name: String,
    pub is_root: bool,
    pub is_current: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerDirectoryChoice {
    pub path: PathBuf,
    pub name: String,
    pub selected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerDirectoryColumn {
    pub path: PathBuf,
    pub name: String,
    pub entries: Vec<FileManagerDirectoryChoice>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerTab {
    pub id: u64,
    pub path: PathBuf,
    pub back: Vec<PathBuf>,
    pub forward: Vec<PathBuf>,
    pub pinned: bool,
    pub settings: FileManagerSettings,
    pub common_settings: FileManagerSettings,
    pub active_view_state_id: Option<String>,
    /// 搜索结果列表。非空时这个页签画的就是这份命中，而不是 `path` 那一层
    /// （NeoView 的 `virtual://search` 页签）。
    ///
    /// 命中存在核心里而不是 UI 里，为的是让**列表只有一个真本**：换布局、重建卡片
    /// 或别的页签切回来，看到的仍是同一份结果；陈旧判定也才能用会话的 generation。
    pub search: Option<FileManagerSearchListing>,
}

/// 一次搜索落在页签上的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchListing {
    /// 搜索根。结果里的条目都在这下面，页签的 `path` 也停在这里。
    pub root: PathBuf,
    /// 这批命中对应的查询，用于说明与「重新搜索」。
    pub query: String,
    pub entries: Vec<FileManagerEntry>,
    pub scanned: usize,
    pub matched: usize,
    pub truncated: bool,
    pub cancelled: bool,
}

/// 页签标题里最多露出多少个搜索词。再长就该去输入框里看，而不是把页签条撑开。
const SEARCH_TITLE_QUERY_CHARS: usize = 24;

impl FileManagerTab {
    fn new(id: u64, path: PathBuf) -> Self {
        Self {
            id,
            path,
            back: Vec::new(),
            forward: Vec::new(),
            pinned: false,
            settings: FileManagerSettings::default(),
            common_settings: FileManagerSettings::default(),
            active_view_state_id: None,
            search: None,
        }
    }

    pub fn title(&self) -> String {
        if let Some(search) = &self.search {
            // NeoView 的 `searchTabTitle`：有词就露词，没词（纯条件筛选）叫「搜索结果」。
            let query = search.query.trim();
            if query.is_empty() {
                return "搜索结果".to_string();
            }
            let short: String = query.chars().take(SEARCH_TITLE_QUERY_CHARS).collect();
            let needs_ellipsis = query.chars().count() > SEARCH_TITLE_QUERY_CHARS;
            return if needs_ellipsis {
                format!("搜索: {short}…")
            } else {
                format!("搜索: {short}")
            };
        }
        self.path
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty())
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| self.path.to_string_lossy().into_owned())
    }

    pub fn can_go_back(&self) -> bool {
        !self.back.is_empty()
    }

    pub fn can_go_forward(&self) -> bool {
        !self.forward.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PenetrationResult {
    /// 目录本身是一个纯媒体来源，或目录链最终落到唯一归档。
    Terminal(PathBuf),
    /// 存在多个候选，用户必须进入目录自行选择。
    Branch,
    Empty,
    Blocked,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenEntryResult {
    Entered(PathBuf),
    Opened(PathBuf),
}

/// 一个 UI 无关的文件浏览状态。
#[derive(Clone)]
pub struct FileManagerState {
    tabs: Vec<FileManagerTab>,
    active_tab: usize,
    next_tab_id: u64,
    recently_closed: Vec<FileManagerTab>,
    generation: u64,
    /// 目录 → 该目录的视图与排序。键来自 [`crate::settings_db::view_state_key`]。
    view_states: std::collections::HashMap<String, FileManagerViewState>,
    /// 自上次 [`FileManagerState::take_dirty_view_states`] 之后发生变化的目录键。
    ///
    /// 核心不认识数据库：它只回答「哪些目录的偏好变了」，由会话层决定什么时候落盘。
    dirty_view_states: std::collections::BTreeSet<String>,
    remember_view_state: bool,
    /// 用户指定的「主页」。跨页签共享，未设置时导航掌的主页键不可点（与 NeoView 一致）。
    home_path: Option<PathBuf>,
}

impl FileManagerState {
    pub fn new(initial_path: Option<PathBuf>) -> Result<Self> {
        let path = initial_path
            // mImageViewer resolves stale launch paths and accepted containers before
            // the browser chooses its directory. This keeps Windows junctions,
            // removable volumes and dropped archive paths on the same code path.
            .and_then(|path| crate::folder_tree::resolve_openable_path(&path))
            .and_then(normalize_initial_directory)
            .or_else(default_directory)
            .ok_or_else(|| anyhow!("没有可用的本地目录"))?;
        Ok(Self {
            tabs: vec![FileManagerTab::new(1, path)],
            active_tab: 0,
            next_tab_id: 2,
            recently_closed: Vec::new(),
            generation: 1,
            view_states: std::collections::HashMap::new(),
            dirty_view_states: std::collections::BTreeSet::new(),
            remember_view_state: true,
            home_path: None,
        })
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn settings(&self) -> &FileManagerSettings {
        &self.tabs[self.active_tab].settings
    }

    pub fn tabs(&self) -> &[FileManagerTab] {
        &self.tabs
    }

    pub fn recently_closed(&self) -> &[FileManagerTab] {
        &self.recently_closed
    }

    pub fn can_create_tab(&self) -> bool {
        self.tabs.len() < MAX_FILE_MANAGER_TABS
    }

    pub fn can_close_tab(&self, id: u64) -> bool {
        self.tabs.len() > 1 && self.tabs.iter().any(|tab| tab.id == id)
    }

    pub fn can_close_other_tabs(&self, id: u64) -> bool {
        self.tabs.iter().any(|tab| tab.id == id)
            && self.tabs.iter().any(|tab| tab.id != id && !tab.pinned)
    }

    pub fn can_close_tabs_on_side(&self, id: u64, left: bool) -> bool {
        self.tabs
            .iter()
            .position(|tab| tab.id == id)
            .is_some_and(|target| {
                self.tabs.iter().enumerate().any(|(index, tab)| {
                    !tab.pinned && if left { index < target } else { index > target }
                })
            })
    }

    pub fn active_tab(&self) -> &FileManagerTab {
        &self.tabs[self.active_tab]
    }

    pub fn active_tab_id(&self) -> u64 {
        self.active_tab().id
    }

    pub fn active_path(&self) -> &Path {
        &self.active_tab().path
    }

    pub fn can_go_up(&self) -> bool {
        self.active_path().parent().is_some_and(|parent| {
            !parent.as_os_str().is_empty() && !same_path(parent, self.active_path())
        })
    }

    /// 导航掌的主页键。未设置主页时为 `None`，UI 据此禁用，而不是自己再记一份路径。
    pub fn home_path(&self) -> Option<&Path> {
        self.home_path.as_deref()
    }

    pub fn is_home(&self) -> bool {
        self.home_path
            .as_deref()
            .is_some_and(|home| same_path(home, self.active_path()))
    }

    /// 已经站在主页上时不再提供「设为主页」，否则右键菜单会写出一条空操作。
    pub fn can_set_home(&self) -> bool {
        self.home_path
            .as_deref()
            .is_none_or(|home| !same_path(home, self.active_path()))
    }

    /// 主页只接受真实存在的目录；传 `None` 表示清除。非法路径保持原值不变。
    pub fn set_home_path(&mut self, path: Option<PathBuf>) -> bool {
        let next = match path {
            Some(path) if path.is_dir() => Some(path),
            Some(_) => return false,
            None => None,
        };
        if self.home_path == next {
            return false;
        }
        self.home_path = next;
        self.bump_generation();
        true
    }

    /// 主页跳转同样走 `navigate`，因此会进入后退栈。
    pub fn go_home(&mut self) -> bool {
        let Some(home) = self.home_path.clone() else {
            return false;
        };
        if same_path(&home, self.active_path()) {
            return false;
        }
        self.navigate(home).is_ok()
    }

    pub fn sort_temporary(&self) -> bool {
        self.settings().sort_temporary
    }

    /// 目录级排序偏好只有在 `remember_view_state` 打开时才存在。
    pub fn can_sort_preference(&self) -> bool {
        self.remember_view_state
    }

    /// 关闭「临时排序」＝把当前排序锁进本目录的视图状态。
    pub fn set_sort_temporary(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.sort_temporary == enabled {
            return;
        }
        self.tabs[self.active_tab].settings.sort_temporary = enabled;
        if !enabled {
            self.capture_active_view_state();
        }
        self.bump_generation();
    }

    /// 使用本机 Path 组件，不把 Unix 文件名中的反斜杠当分隔符，也不拆开 Windows UNC 根。
    pub fn breadcrumbs(&self) -> Vec<FileManagerBreadcrumb> {
        let mut paths: Vec<_> = self
            .active_path()
            .ancestors()
            .filter(|path| !path.as_os_str().is_empty())
            .collect();
        paths.reverse();
        paths
            .iter()
            .enumerate()
            .map(|(index, path)| FileManagerBreadcrumb {
                path: path.to_path_buf(),
                name: directory_title(path),
                is_root: index == 0,
                is_current: index + 1 == paths.len(),
            })
            .collect()
    }

    /// Neo 列导航只展开当前路径最后三层，关闭时完全不读取列目录。
    /// 枚举/隐藏规则/自然排序继续复用 mImageViewer 适配层；搜索不会隐藏导航目录。
    pub fn directory_columns(&self) -> Vec<FileManagerDirectoryColumn> {
        if !self.settings().directory_columns_enabled {
            return Vec::new();
        }
        let breadcrumbs = self.breadcrumbs();
        breadcrumbs
            .iter()
            .skip(breadcrumbs.len().saturating_sub(3))
            .map(|segment| {
                let (entries, error) = match list_directory_with_hidden(
                    &segment.path,
                    self.settings().show_hidden_files,
                ) {
                    Ok(nodes) => (
                        nodes
                            .into_iter()
                            .filter(|node| node.is_dir)
                            .map(|node| FileManagerDirectoryChoice {
                                selected: breadcrumbs
                                    .iter()
                                    .any(|part| same_path(&part.path, Path::new(&node.path))),
                                path: PathBuf::from(node.path),
                                name: node.name,
                            })
                            .collect(),
                        None,
                    ),
                    Err(error) => (Vec::new(), Some(error.to_string())),
                };
                FileManagerDirectoryColumn {
                    path: segment.path.clone(),
                    name: segment.name.clone(),
                    entries,
                    error,
                }
            })
            .collect()
    }

    pub fn set_directory_columns_enabled(&mut self, enabled: bool) {
        if self.tabs[self.active_tab]
            .settings
            .directory_columns_enabled
            != enabled
        {
            self.tabs[self.active_tab]
                .settings
                .directory_columns_enabled = enabled;
            self.bump_generation();
        }
    }

    /// 编辑框的文本解析也属于核心。相对路径以当前页签为基准；成功跳转统一进入后退栈。
    pub fn navigate_text(&mut self, text: &str) -> Result<()> {
        let text = text.trim();
        let text = text
            .strip_prefix('"')
            .and_then(|value| value.strip_suffix('"'))
            .unwrap_or(text);
        if text.is_empty() {
            return Err(anyhow!("请输入目录路径"));
        }
        self.navigate(PathBuf::from(text))
    }

    pub fn set_penetration_enabled(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.penetration_enabled != enabled {
            self.tabs[self.active_tab].settings.penetration_enabled = enabled;
            self.bump_generation();
        }
    }

    pub fn set_show_child_names(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.show_child_names != enabled {
            self.tabs[self.active_tab].settings.show_child_names = enabled;
            self.bump_generation();
        }
    }

    pub fn set_internal_items_mode(&mut self, mode: InternalItemsMode) {
        if self.tabs[self.active_tab].settings.internal_items_mode != mode {
            self.tabs[self.active_tab].settings.internal_items_mode = mode;
            self.bump_generation();
        }
    }

    pub fn set_max_depth(&mut self, depth: usize) {
        let depth = depth.clamp(1, MAX_PENETRATION_DEPTH);
        if self.tabs[self.active_tab].settings.max_depth != depth {
            self.tabs[self.active_tab].settings.max_depth = depth;
            self.bump_generation();
        }
    }

    fn transition_view_state_for_path(&mut self, target_path: &Path) {
        if !self.remember_view_state {
            return;
        }
        let tab = &mut self.tabs[self.active_tab];
        // 1. 如果之前有 active_view_state_id，保存当前活跃修改
        if let Some(id) = tab.active_view_state_id.take() {
            let base = self
                .view_states
                .get(&id)
                .cloned()
                .unwrap_or_else(|| FileManagerViewState::from_settings(&tab.common_settings));
            let updated =
                FileManagerViewState::from_settings_keeping_locked_sort(&tab.settings, &base);
            if self.view_states.get(&id) != Some(&updated) {
                self.view_states.insert(id.clone(), updated);
                self.dirty_view_states.insert(id);
            }
        }

        // 2. 核心规则：切换位置时先干净回退到 common 公共值正本
        tab.settings.reset_view_fields_to(&tab.common_settings);

        // 3. 寻找新路径的最长匹配并套用 overlay
        if let Some((id, state)) =
            crate::settings_db::resolve_view_state_for_path(target_path, &self.view_states)
        {
            tab.active_view_state_id = Some(id);
            state.apply_to_settings(&mut tab.settings);
        }
    }

    /// 把当前目录的视图与排序收进它的视图状态。
    ///
    /// 这是目录偏好的**唯一写入口**：只有真的变了才标脏，所以来回切换视图再切回去
    /// 不会在数据库里产生多余的写。
    fn capture_active_view_state(&mut self) {
        if !self.remember_view_state {
            return;
        }
        let tab = &mut self.tabs[self.active_tab];
        let key = crate::settings_db::view_state_key(&tab.path);
        tab.active_view_state_id = Some(key.clone());
        let base = self
            .view_states
            .get(&key)
            .cloned()
            .unwrap_or_else(|| FileManagerViewState::from_settings(&tab.common_settings));
        let updated = FileManagerViewState::from_settings_keeping_locked_sort(&tab.settings, &base);
        if self.view_states.get(&key) == Some(&updated) {
            return;
        }
        self.view_states.insert(key.clone(), updated);
        self.dirty_view_states.insert(key);
    }

    pub fn hydrate_view_states(
        &mut self,
        states: std::collections::HashMap<String, FileManagerViewState>,
    ) {
        self.view_states = states;
        // 刚从盘上读回来的不是「待写入的改动」。
        self.dirty_view_states.clear();
        let current_path = self.active_path().to_path_buf();
        self.transition_view_state_for_path(&current_path);
    }

    pub fn view_states(&self) -> &std::collections::HashMap<String, FileManagerViewState> {
        &self.view_states
    }

    /// 取出并清空「自上次调用后发生过变化」的目录视图状态。
    ///
    /// 会话层用它在每次用户动作之后落盘；核心自己不碰数据库。
    pub fn take_dirty_view_states(&mut self) -> Vec<(String, FileManagerViewState)> {
        let keys: Vec<String> = self.dirty_view_states.iter().cloned().collect();
        self.dirty_view_states.clear();
        keys.into_iter()
            .filter_map(|key| {
                self.view_states
                    .get(&key)
                    .cloned()
                    .map(|state| (key, state))
            })
            .collect()
    }

    pub fn set_remember_view_state(&mut self, enabled: bool) {
        if self.remember_view_state == enabled {
            return;
        }
        self.remember_view_state = enabled;
        if !enabled {
            // 关掉记忆时断开「当前活跃目录」的归属：否则重新打开记忆后，
            // 第一次 capture 会把关机前的旧值当成这个目录的偏好写回去。
            self.tabs[self.active_tab].active_view_state_id = None;
        }
    }

    pub fn remember_view_state(&self) -> bool {
        self.remember_view_state
    }

    pub fn set_view_mode(&mut self, mode: ViewMode) {
        if self.tabs[self.active_tab].settings.view_mode != mode {
            self.tabs[self.active_tab].settings.view_mode = mode;
            self.capture_active_view_state();
            self.bump_generation();
        }
    }

    pub fn set_show_hidden_files(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.show_hidden_files != enabled {
            self.tabs[self.active_tab].settings.show_hidden_files = enabled;
            self.capture_active_view_state();
            self.bump_generation();
        }
    }

    pub fn set_search_query(&mut self, query: impl Into<String>) {
        let query = query.into().trim().to_owned();
        if self.tabs[self.active_tab].settings.search_query != query {
            self.tabs[self.active_tab].settings.search_query = query;
            // 词都清空了，上一批命中就不该继续占着这个页签。
            if self.tabs[self.active_tab].settings.search_query.is_empty() {
                self.tabs[self.active_tab].search = None;
            }
            self.bump_generation();
        }
    }

    pub fn set_search_in_path(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.search_in_path != enabled {
            self.tabs[self.active_tab].settings.search_in_path = enabled;
            self.bump_generation();
        }
    }

    pub fn set_search_or_mode(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.search_or_mode != enabled {
            self.tabs[self.active_tab].settings.search_or_mode = enabled;
            self.bump_generation();
        }
    }

    pub fn set_search_include_subfolders(&mut self, enabled: bool) {
        if self.tabs[self.active_tab]
            .settings
            .search_include_subfolders
            != enabled
        {
            self.tabs[self.active_tab]
                .settings
                .search_include_subfolders = enabled;
            self.bump_generation();
        }
    }

    /// 递归层数。`0` 与「不递归」等价，交给搜索时再被上限夹一次。
    pub fn set_search_max_depth(&mut self, depth: usize) {
        let depth = depth.min(MAX_SEARCH_DEPTH);
        if self.tabs[self.active_tab].settings.search_max_depth != depth {
            self.tabs[self.active_tab].settings.search_max_depth = depth;
            self.bump_generation();
        }
    }

    pub fn set_entry_filter(&mut self, filter: EntryFilter) {
        if self.tabs[self.active_tab].settings.entry_filter != filter {
            self.tabs[self.active_tab].settings.entry_filter = filter;
            self.capture_active_view_state();
            self.bump_generation();
        }
    }

    pub fn set_sort(&mut self, field: SortField, order: SortOrder) {
        let tab = &mut self.tabs[self.active_tab];
        if tab.settings.sort_field == field && tab.settings.sort_order == order {
            return;
        }
        // 只有「切进随机」才重掷种子：在随机字段上反复切换升降序若也重掷，
        // 同一目录会因为换方向而整体换一次顺序，看起来像刷新。
        if field == SortField::Random && tab.settings.sort_field != SortField::Random {
            tab.settings.shuffle_seed = fresh_shuffle_seed();
        }
        tab.settings.sort_field = field;
        tab.settings.sort_order = order;
        if !self.tabs[self.active_tab].settings.sort_temporary {
            self.capture_active_view_state();
        }
        self.bump_generation();
    }

    pub fn set_directories_first(&mut self, enabled: bool) {
        if self.tabs[self.active_tab].settings.directories_first != enabled {
            self.tabs[self.active_tab].settings.directories_first = enabled;
            self.capture_active_view_state();
            self.bump_generation();
        }
    }

    pub fn navigate(&mut self, path: impl Into<PathBuf>) -> Result<()> {
        let path = path.into();
        let path = if path.is_absolute() {
            path
        } else {
            self.active_path().join(path)
        };
        // 含 .. 的输入必须由文件系统解析，不能词法折叠后越过符号链接的真实父目录。
        let path = if path
            .components()
            .any(|part| matches!(part, std::path::Component::ParentDir))
        {
            std::fs::canonicalize(&path)
                .map_err(|error| anyhow!("无法打开目录 {}: {error}", path.display()))?
        } else {
            path
        };
        std::fs::read_dir(&path)
            .map_err(|error| anyhow!("无法打开目录 {}: {error}", path.display()))?;
        let tab = &mut self.tabs[self.active_tab];
        if same_path(&tab.path, &path) {
            return Ok(());
        }
        let previous = std::mem::replace(&mut tab.path, path);
        tab.back.push(previous);
        tab.forward.clear();
        tab.settings.search_query.clear();
        // 导航即离开搜索结果：命中列表属于「上一次搜索的那个根」，跟着新目录走
        // 会让人以为搜遍全盘只有一本。
        tab.search = None;
        let current_path = self.tabs[self.active_tab].path.clone();
        self.transition_view_state_for_path(&current_path);
        self.bump_generation();
        Ok(())
    }

    pub fn go_back(&mut self) -> bool {
        let tab = &mut self.tabs[self.active_tab];
        let Some(previous) = tab.back.pop() else {
            return false;
        };
        let current = std::mem::replace(&mut tab.path, previous);
        tab.forward.push(current);
        tab.settings.search_query.clear();
        // 导航即离开搜索结果：命中列表属于「上一次搜索的那个根」，跟着新目录走
        // 会让人以为搜遍全盘只有一本。
        tab.search = None;
        let current_path = self.tabs[self.active_tab].path.clone();
        self.transition_view_state_for_path(&current_path);
        self.bump_generation();
        true
    }

    pub fn go_forward(&mut self) -> bool {
        let tab = &mut self.tabs[self.active_tab];
        let Some(next) = tab.forward.pop() else {
            return false;
        };
        let current = std::mem::replace(&mut tab.path, next);
        tab.back.push(current);
        tab.settings.search_query.clear();
        // 导航即离开搜索结果：命中列表属于「上一次搜索的那个根」，跟着新目录走
        // 会让人以为搜遍全盘只有一本。
        tab.search = None;
        let current_path = self.tabs[self.active_tab].path.clone();
        self.transition_view_state_for_path(&current_path);
        self.bump_generation();
        true
    }

    pub fn go_up(&mut self) -> bool {
        let Some(parent) = self.active_path().parent().map(Path::to_path_buf) else {
            return false;
        };
        if same_path(&parent, self.active_path()) {
            return false;
        }
        self.navigate(parent).is_ok()
    }

    pub fn refresh(&mut self) {
        // 随机排序下刷新应当给出新的洗牌，否则「刷新」看不到任何变化。
        if self.tabs[self.active_tab].settings.sort_field == SortField::Random {
            self.tabs[self.active_tab].settings.shuffle_seed = fresh_shuffle_seed();
        }
        self.bump_generation();
    }

    pub fn new_tab(&mut self, path: Option<PathBuf>) -> Result<u64> {
        if self.tabs.len() >= MAX_FILE_MANAGER_TABS {
            return Err(anyhow!("页签数量已达到上限 ({MAX_FILE_MANAGER_TABS})"));
        }
        let target = path
            .and_then(|path| crate::folder_tree::resolve_openable_path(&path))
            .and_then(normalize_initial_directory)
            .unwrap_or_else(|| self.active_path().to_path_buf());
        if !target.is_dir() {
            return Err(anyhow!("路径不是有效目录: {}", target.display()));
        }
        let id = self.next_tab_id;
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        self.tabs.push(FileManagerTab::new(id, target));
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(id)
    }

    pub fn duplicate_tab(&mut self, id: u64) -> Result<u64> {
        if self.tabs.len() >= MAX_FILE_MANAGER_TABS {
            return Err(anyhow!("页签数量已达到上限 ({MAX_FILE_MANAGER_TABS})"));
        }
        let Some(source) = self.tabs.iter().find(|tab| tab.id == id).cloned() else {
            return Err(anyhow!("页签不存在: {id}"));
        };
        let new_id = self.next_tab_id;
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        let mut copy = source;
        copy.id = new_id;
        copy.pinned = false;
        self.tabs.push(copy);
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(new_id)
    }

    pub fn activate_tab(&mut self, id: u64) -> bool {
        let Some(index) = self.tabs.iter().position(|tab| tab.id == id) else {
            return false;
        };
        if self.active_tab != index {
            self.active_tab = index;
            self.bump_generation();
        }
        true
    }

    pub fn close_tab(&mut self, id: u64) -> bool {
        if !self.can_close_tab(id) {
            return false;
        }
        let Some(index) = self.tabs.iter().position(|tab| tab.id == id) else {
            return false;
        };
        let removed = self.tabs.remove(index);
        self.remember_closed(removed);
        if self.active_tab > index {
            self.active_tab -= 1;
        } else if self.active_tab == index {
            self.active_tab = self.active_tab.min(self.tabs.len() - 1);
        }
        self.bump_generation();
        true
    }

    pub fn toggle_tab_pinned(&mut self, id: u64) -> bool {
        let Some(tab) = self.tabs.iter_mut().find(|tab| tab.id == id) else {
            return false;
        };
        tab.pinned = !tab.pinned;
        self.bump_generation();
        true
    }

    pub fn close_other_tabs(&mut self, keep_id: u64) -> bool {
        let Some(keep_index) = self.tabs.iter().position(|tab| tab.id == keep_id) else {
            return false;
        };
        let active_id = self.active_tab_id();
        let mut removed = Vec::new();
        let mut kept = Vec::with_capacity(self.tabs.len());
        for (index, tab) in self.tabs.drain(..).enumerate() {
            if index == keep_index || tab.pinned {
                kept.push(tab);
            } else {
                removed.push(tab);
            }
        }
        self.tabs = kept;
        if removed.is_empty() {
            return false;
        }
        self.remember_closed_many(removed);
        self.active_tab = self
            .tabs
            .iter()
            .position(|tab| tab.id == active_id)
            .unwrap_or_else(|| self.tabs.iter().position(|tab| tab.id == keep_id).unwrap());
        self.bump_generation();
        true
    }

    pub fn close_tabs_left(&mut self, id: u64) -> bool {
        self.close_tabs_on_side(id, true)
    }

    pub fn close_tabs_right(&mut self, id: u64) -> bool {
        self.close_tabs_on_side(id, false)
    }

    pub fn reopen_closed_tab(&mut self, closed_id: u64) -> Result<u64> {
        if self.tabs.len() >= MAX_FILE_MANAGER_TABS {
            return Err(anyhow!("页签数量已达到上限 ({MAX_FILE_MANAGER_TABS})"));
        }
        let Some(index) = self
            .recently_closed
            .iter()
            .position(|tab| tab.id == closed_id)
        else {
            return Err(anyhow!("已关闭页签不存在: {closed_id}"));
        };
        let path = &self.recently_closed[index].path;
        std::fs::read_dir(path)
            .map_err(|error| anyhow!("无法恢复页签 {}: {error}", path.display()))?;
        let mut tab = self.recently_closed.remove(index);
        let id = self.next_tab_id;
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        tab.id = id;
        tab.pinned = false;
        self.tabs.push(tab);
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(id)
    }

    fn close_tabs_on_side(&mut self, id: u64, left: bool) -> bool {
        let Some(target_index) = self.tabs.iter().position(|tab| tab.id == id) else {
            return false;
        };
        let should_remove = |index: usize| {
            if left {
                index < target_index
            } else {
                index > target_index
            }
        };
        let active_id = self.active_tab_id();
        let mut removed = Vec::new();
        let mut kept = Vec::with_capacity(self.tabs.len());
        for (index, tab) in self.tabs.drain(..).enumerate() {
            if should_remove(index) && !tab.pinned {
                removed.push(tab);
            } else {
                kept.push(tab);
            }
        }
        self.tabs = kept;
        if removed.is_empty() {
            return false;
        }
        self.remember_closed_many(removed);
        self.active_tab = self
            .tabs
            .iter()
            .position(|tab| tab.id == active_id)
            .unwrap_or_else(|| self.tabs.iter().position(|tab| tab.id == id).unwrap());
        self.bump_generation();
        true
    }

    fn remember_closed(&mut self, tab: FileManagerTab) {
        self.recently_closed.push(tab);
        if self.recently_closed.len() > MAX_RECENTLY_CLOSED_TABS {
            let drop_count = self.recently_closed.len() - MAX_RECENTLY_CLOSED_TABS;
            self.recently_closed.drain(..drop_count);
        }
    }

    fn remember_closed_many(&mut self, tabs: Vec<FileManagerTab>) {
        for tab in tabs {
            self.remember_closed(tab);
        }
    }

    pub fn open_entry(
        &mut self,
        path: impl AsRef<Path>,
        force_enter: bool,
    ) -> Result<OpenEntryResult> {
        let path = path.as_ref();
        if path.is_dir() {
            if !force_enter && self.tabs[self.active_tab].settings.penetration_enabled {
                match self.resolve_penetration(path) {
                    PenetrationResult::Terminal(target) => {
                        return Ok(OpenEntryResult::Opened(target));
                    }
                    PenetrationResult::Empty
                    | PenetrationResult::Blocked
                    | PenetrationResult::Branch => {}
                }
            }
            self.navigate(path.to_path_buf())?;
            return Ok(OpenEntryResult::Entered(path.to_path_buf()));
        }
        if path.is_file() {
            let extension = path
                .extension()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_ascii_lowercase();
            let is_image = crate::folder_tree::is_recognized_image_ext(&extension);
            if !crate::file_tree::is_comic_archive_path(path)
                && !is_image
                && !crate::page_order::is_video_name(&path.to_string_lossy())
            {
                return Err(anyhow!("当前 Reader 暂不支持直接打开 {}", path.display()));
            }
            // mImageViewer 口径：松散图片不是一本书，它所在的那个目录才是；点开的那张
            // 只是书里的一页。压缩包按自身成一本书，因此不走这条解析。
            // 判据取「算不算一页」那张表，不取文件列表的可见性表：后者还含 RAW 等
            // 页序不认的后缀，提升上去会翻出一本空书，平铺为空时更要递归进子目录，
            // 把完全无关的目录当成这一本的内容。
            if is_image && crate::page_order::is_page_name(&path.to_string_lossy()) {
                if let Some(resolved) = crate::folder_tree::resolve_openable_path_detailed(path) {
                    if resolved.kind == crate::folder_tree::OpenablePathKind::Directory
                        && resolved.requested_is_file
                    {
                        return Ok(OpenEntryResult::Opened(resolved.path));
                    }
                }
            }
            return Ok(OpenEntryResult::Opened(path.to_path_buf()));
        }
        Err(anyhow!("文件或目录不存在: {}", path.display()))
    }

    /// Open an archive without changing the browser location.
    ///
    /// The archive predicate deliberately comes from the vendored mImageViewer
    /// folder tree.  This keeps a double-click action in every UI in sync with
    /// the directory listing (including case-insensitive CBZ/ZIP and converted
    /// RAR/7z/LZH containers), instead of maintaining a second extension list.
    pub fn open_archive(&mut self, path: impl AsRef<Path>) -> Result<PathBuf> {
        let path = path.as_ref();
        if !path.is_file() {
            return Err(anyhow!("压缩包不存在或不是文件: {}", path.display()));
        }
        if !crate::folder_tree::is_virtual_folder(path)
            && !crate::folder_tree::is_convertible_archive_path(path)
        {
            return Err(anyhow!("不是可打开的压缩包: {}", path.display()));
        }
        Ok(path.to_path_buf())
    }

    pub fn resolve_penetration(&self, origin: &Path) -> PenetrationResult {
        let mut visited = HashSet::new();
        resolve_penetration_inner(
            origin,
            0,
            self.tabs[self.active_tab]
                .settings
                .max_depth
                .min(MAX_PENETRATION_DEPTH),
            self.settings().show_hidden_files,
            &mut visited,
        )
    }

    pub fn entries(&self) -> Result<Vec<FileManagerEntry>> {
        let settings = &self.tabs[self.active_tab].settings;
        // 搜索结果页签：列表就是上一次遍历交出的命中，不再枚举当前目录。
        // 「列表只有一份真本」是这里的目的 —— UI 不再自己揣一份结果数组。
        if let Some(search) = &self.tabs[self.active_tab].search {
            return Ok(search.entries.clone());
        }
        // 词元在整份列表上复用，只在解析查询时 lowercase 一次；逐条目再解析会把
        // O(条目) 变成 O(条目 × 查询长度) 的分配。
        let tokens = crate::search_query::parse(&settings.search_query);
        let root = self.active_path();
        let mut nodes = list_directory_with_hidden(root, settings.show_hidden_files)?;
        nodes.retain(|node| matches_entry(settings, node, &tokens, root));
        nodes.sort_by(|left, right| compare_entries(settings, left, right));
        Ok(nodes
            .into_iter()
            .map(|node| {
                let children =
                    if node.is_dir && settings.penetration_enabled && settings.show_child_names {
                        describe_children(Path::new(&node.path), settings)
                    } else {
                        Vec::new()
                    };
                FileManagerEntry { node, children }
            })
            .collect())
    }

    /// 把「当前生效的搜索条件」打包成一次可以脱离会话独立执行的请求。
    ///
    /// 递归遍历跑在 `spawn_blocking` 的线程上，不能拿着 `DashMap` 会话的借用
    /// （那会和并发的动作互相等），所以这里交出的是**值**：根路径 + 设置快照。
    /// 遍历期间用户改了设置，代价只是这一次按旧条件出结果。
    pub fn search_request(&self) -> FileManagerSearchRequest {
        FileManagerSearchRequest {
            root: self.active_path().to_path_buf(),
            settings: self.tabs[self.active_tab].settings.clone(),
        }
    }

    /// 把一次遍历的结果交给当前页签，于是它就是「搜索结果页签」。
    pub fn set_search_listing(&mut self, listing: FileManagerSearchListing) {
        self.tabs[self.active_tab].search = Some(listing);
        self.bump_generation();
    }

    /// 退出搜索结果视图，回到页签自己那一层目录。
    pub fn clear_search_listing(&mut self) {
        if self.tabs[self.active_tab].search.take().is_some() {
            self.bump_generation();
        }
    }

    /// 把当前搜索结果另存成一个页签（保留查询、条件与命中），并切到它。
    pub fn save_search_as_tab(&mut self) -> Result<u64> {
        if self.tabs.len() >= MAX_FILE_MANAGER_TABS {
            return Err(anyhow!("页签数量已达到上限 ({MAX_FILE_MANAGER_TABS})"));
        }
        let source = &self.tabs[self.active_tab];
        if source.search.is_none() {
            return Err(anyhow!("当前页签没有可保存的搜索结果"));
        }
        let id = self.next_tab_id;
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        let mut copy = source.clone();
        copy.id = id;
        copy.pinned = false;
        self.tabs.push(copy);
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(id)
    }

    /// 当前页签的搜索结果摘要，用于快照投影与「能不能存成页签」。
    pub fn search_listing(&self) -> Option<&FileManagerSearchListing> {
        self.tabs[self.active_tab].search.as_ref()
    }

    fn bump_generation(&mut self) {
        self.generation = self.generation.wrapping_add(1).max(1);
    }
}

/// 一条目是否命中当前设置里的查询与类型筛选。
///
/// `tokens` 由调用方解析一次后复用（见 [`entries`]）。
fn matches_entry(
    settings: &FileManagerSettings,
    node: &FileTreeNode,
    tokens: &[crate::search_query::Token],
    root: &Path,
) -> bool {
    if !tokens.is_empty() {
        let mode = if settings.search_or_mode {
            crate::search_query::MatchMode::Or
        } else {
            crate::search_query::MatchMode::And
        };
        let hay = search_hay(node, settings.search_in_path.then_some(root));
        // 索引期 / 查询期 / 后置过滤必须走同一个归一化函数，否则出假阴性；
        // 查询期由 `search_query::parse` 内部完成，这里负责 hay 侧。
        let hay = crate::search_norm::normalize_for_match(&hay);
        if !crate::search_query::matches_lowercased_with_mode(tokens, &hay, mode) {
            return false;
        }
    }
    entry_filter_matches(settings.entry_filter, node)
}

fn entry_filter_matches(filter: EntryFilter, node: &FileTreeNode) -> bool {
    match filter {
        EntryFilter::All => true,
        EntryFilter::Folders => node.is_dir,
        EntryFilter::Archives => node.is_archive,
        EntryFilter::Images => node.is_image,
        EntryFilter::Video => node.is_video,
        EntryFilter::Audio => node.is_audio,
    }
}

pub(crate) fn compare_entries(
    settings: &FileManagerSettings,
    left: &FileTreeNode,
    right: &FileTreeNode,
) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    let rank = |node: &FileTreeNode| !node.is_dir;
    let directories = settings
        .directories_first
        .then(|| rank(left).cmp(&rank(right)));
    let field_order = match settings.sort_field {
        SortField::Name => natural_name_cmp(&left.name, &right.name),
        SortField::Type => {
            extension_cmp(left, right).then_with(|| natural_name_cmp(&left.name, &right.name))
        }
        SortField::Size => left
            .size
            .cmp(&right.size)
            .then_with(|| natural_name_cmp(&left.name, &right.name)),
        SortField::Date => left
            .modified_secs
            .cmp(&right.modified_secs)
            .then_with(|| natural_name_cmp(&left.name, &right.name)),
        SortField::Random => {
            // 名称兜底让比较器保持全序；同一目录内名称唯一，实际不会触发。
            shuffle_key(settings.shuffle_seed, &left.name)
                .cmp(&shuffle_key(settings.shuffle_seed, &right.name))
                .then_with(|| natural_name_cmp(&left.name, &right.name))
        }
    };
    let order = if settings.sort_order == SortOrder::Descending {
        field_order.reverse()
    } else {
        field_order
    };
    directories.unwrap_or(Ordering::Equal).then(order)
}

/// 搜索的 hay：条目名，加上（可选）相对搜索根的那段目录。
///
/// 只喂**相对**路径，父目录名才不会把它的所有子项都匹配上；分隔符统一成 `/`，
/// 这样 Windows 的 `春\001.jpg` 用 `春/001` 也能命中。
fn search_hay_for_name(name: &str, relative_dir: Option<&str>) -> String {
    match relative_dir {
        Some(rel) if !rel.is_empty() => format!("{rel}/{name}"),
        _ => name.to_owned(),
    }
}

fn search_hay(node: &FileTreeNode, root: Option<&Path>) -> String {
    let Some(root) = root else {
        return node.name.clone();
    };
    let relative_dir = Path::new(&node.path)
        .parent()
        .and_then(|parent| parent.strip_prefix(root).ok())
        .filter(|rel| !rel.as_os_str().is_empty())
        .map(|rel| rel.to_string_lossy().replace('\\', "/"));
    search_hay_for_name(&node.name, relative_dir.as_deref())
}

/// 一次递归搜索的输入：搜索根 + 当时生效的设置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchRequest {
    pub root: PathBuf,
    pub settings: FileManagerSettings,
}

/// 一条命中就是目录列表里那种条目，不另加「相对目录」字段：那段信息已经完整地
/// 包含在 `path` 里，展示时由 UI 投影层用搜索根算出来（同一事实不留两份）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchOutcome {
    pub root: PathBuf,
    /// 这一次结果对应的查询原文（回声）。UI 用它与 `generation` 一起把迟到的
    /// 旧结果丢掉 —— 遍历跑在别的线程上，返回时用户可能已经改了词。
    pub query: String,
    pub hits: Vec<FileTreeNode>,
    /// 检视过的条目数（含未命中的）。用来区分「确实没有」和「还没扫到」。
    pub scanned: usize,
    /// 命中总数，可能大于 `hits.len()`（被 [`MAX_SEARCH_RESULTS`] 截断）。
    pub matched: usize,
    pub truncated: bool,
    pub cancelled: bool,
}

/// 在搜索根（可选地连同子目录）里按名称找条目。
///
/// 三处刻意的设计：
///
/// 1. **广度优先**。搜索要的是「最近的命中」，深度优先会先钻到某一条分支的
///    最深处，撞上 [`MAX_SEARCH_RESULTS`] 上限时把同级的其它分支整个丢掉。
/// 2. **未命中的条目不付 syscall 代价**。`file_name()` 与 `file_type()` 来自目录
///    枚举本身，先按名字预筛，只有命中项和候选目录才构造完整节点（那才需要
///    `metadata()`）。整库扫一眼与逐条目 stat 的差距就在这里。
/// 3. **策略只有一个出口**。隐藏项、内部 bundle、「已识别媒体」的判定全部经由
///    [`crate::file_tree::node_for_dir_entry`]，所以搜索结果里不会出现列表里根本
///    不存在条目，反之也不会把列表能看到的漏掉。
///
/// `cancel` 在每条目与每目录两处检查；置位后已收集的结果照常交出。
pub fn search_entries(
    request: &FileManagerSearchRequest,
    cancel: &AtomicBool,
) -> FileManagerSearchOutcome {
    let settings = &request.settings;
    let tokens = crate::search_query::parse(&settings.search_query);
    let mode = if settings.search_or_mode {
        crate::search_query::MatchMode::Or
    } else {
        crate::search_query::MatchMode::And
    };
    let max_depth = if settings.search_include_subfolders {
        settings.search_max_depth.min(MAX_SEARCH_DEPTH)
    } else {
        0
    };
    let show_hidden = settings.show_hidden_files;
    // 与列表同一口径：关掉路径匹配后，相对目录不参与命中，只看条目名。
    let in_path = settings.search_in_path;

    let mut queue = VecDeque::new();
    queue.push_back((request.root.clone(), 0usize, String::new()));
    // 环保护与上游 DFS 同一把键（canonicalize 后按平台决定大小写敏感性）。
    let mut visited: HashSet<String> = HashSet::new();
    let mut outcome = FileManagerSearchOutcome {
        root: request.root.clone(),
        query: settings.search_query.clone(),
        hits: Vec::new(),
        scanned: 0,
        matched: 0,
        truncated: false,
        cancelled: false,
    };
    // 空查询**不是**「全量列出」。少了这道闸，一次误触（或一个忘了判空的调用方）
    // 就会把整棵目录树扫一遍再交出前 512 条 —— 那不是搜索结果，是磁盘遍历。
    if tokens.is_empty() {
        return outcome;
    }

    while let Some((directory, depth, relative)) = queue.pop_front() {
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            outcome.cancelled = true;
            break;
        }
        if !crate::fs_entry::mark_directory_visited(&directory, &mut visited) {
            continue;
        }
        let Ok(entries) = std::fs::read_dir(&directory) else {
            // 权限 / 失效目录 / 竞态删除：跳过这一支，不把整次搜索作废。
            continue;
        };
        let descend = depth < max_depth;
        for entry in entries.flatten() {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                outcome.cancelled = true;
                break;
            }
            outcome.scanned += 1;
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            let raw_name = entry.file_name();
            let Some(name) = raw_name.to_str() else {
                continue;
            };
            // 目录即使不命中也要检视（下钻用）；符号链接目录要靠 classify 才认得出来。
            let candidate_dir = descend && (file_type.is_dir() || file_type.is_symlink());
            // 词元非空由上面的早退保证：空查询根本不进这里。
            let name_hit = {
                let hay = crate::search_norm::normalize_for_match(&search_hay_for_name(
                    name,
                    in_path.then_some(relative.as_str()),
                ));
                crate::search_query::matches_lowercased_with_mode(&tokens, &hay, mode)
            };
            if !name_hit && !candidate_dir {
                continue;
            }
            let Some(node) =
                crate::file_tree::node_for_dir_entry(&entry, &file_type, show_hidden, false)
            else {
                continue;
            };
            if candidate_dir && node.is_dir {
                let child_relative = if relative.is_empty() {
                    node.name.clone()
                } else {
                    format!("{relative}/{}", node.name)
                };
                queue.push_back((
                    Path::new(&node.path).to_path_buf(),
                    depth + 1,
                    child_relative,
                ));
            }
            if !name_hit || !entry_filter_matches(settings.entry_filter, &node) {
                continue;
            }
            outcome.matched += 1;
            if outcome.hits.len() >= MAX_SEARCH_RESULTS {
                outcome.truncated = true;
                break;
            }
            outcome.hits.push(node);
        }
        if outcome.truncated || outcome.cancelled {
            break;
        }
    }

    // 主序仍是用户的排序字段（与列表同一比较器）；同键时按「离搜索根更近」，
    // 例如两个不同目录里的同名 `001.jpg` —— 浅层的那本先出现。
    let depth_of = |node: &FileTreeNode| {
        Path::new(&node.path)
            .parent()
            .and_then(|parent| parent.strip_prefix(&outcome.root).ok())
            .map_or(0, |rel| rel.iter().count())
    };
    outcome.hits.sort_by(|left, right| {
        compare_entries(settings, left, right)
            .then_with(|| depth_of(left).cmp(&depth_of(right)))
            .then_with(|| left.path.cmp(&right.path))
    });
    outcome
}

fn normalize_initial_directory(path: PathBuf) -> Option<PathBuf> {
    let path = std::path::absolute(path).ok()?;
    if path.is_dir() {
        return Some(path);
    }
    if path.is_file() {
        return path.parent().map(Path::to_path_buf);
    }
    None
}

fn directory_title(path: &Path) -> String {
    path.file_name()
        .filter(|name| !name.is_empty())
        .unwrap_or(path.as_os_str())
        .to_string_lossy()
        .into_owned()
}

fn default_directory() -> Option<PathBuf> {
    crate::file_tree::get_available_roots()
        .into_iter()
        .find_map(|root| normalize_initial_directory(PathBuf::from(root.path)))
}

fn same_path(a: &Path, b: &Path) -> bool {
    crate::folder_tree::path_eq(a, b)
}

fn natural_name_cmp(left: &str, right: &str) -> std::cmp::Ordering {
    crate::filename_sort::SortNameKey::with_natural(left)
        .compare_natural(&crate::filename_sort::SortNameKey::with_natural(right))
}

/// splitmix64 终混。只用于把种子与名称摊平，不承担任何密码学职责。
fn mix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9E37_79B9_7F4A_7C15);
    value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    value ^ (value >> 31)
}

/// 每个名称在给定种子下得到固定的洗牌键，所以同一目录的快照之间顺序不会跳动。
fn shuffle_key(seed: u64, name: &str) -> u64 {
    let mut hash = 0xCBF2_9CE4_8422_2325u64;
    for byte in name.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01B3);
    }
    mix64(seed ^ mix64(hash))
}

fn fresh_shuffle_seed() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as u64)
        // 时间不可用时退回固定种子：顺序不随机仍是合法排序，不能因此 panic。
        .unwrap_or(0x5EED_5EED)
        .max(1)
}

fn extension_cmp(left: &FileTreeNode, right: &FileTreeNode) -> std::cmp::Ordering {
    let extension = |node: &FileTreeNode| {
        Path::new(&node.path)
            .extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .unwrap_or_default()
    };
    extension(left).cmp(&extension(right))
}

fn visit_key(path: &Path) -> String {
    crate::fs_entry::directory_visit_key(path)
}

fn resolve_penetration_inner(
    path: &Path,
    depth: usize,
    max_depth: usize,
    show_hidden_files: bool,
    visited: &mut HashSet<String>,
) -> PenetrationResult {
    if depth > max_depth || depth >= MAX_PENETRATION_DEPTH {
        return PenetrationResult::Blocked;
    }
    if !visited.insert(visit_key(path)) {
        return PenetrationResult::Blocked;
    }
    let entries = match list_directory_with_hidden(path, show_hidden_files) {
        Ok(entries) => entries,
        Err(_) => return PenetrationResult::Blocked,
    };
    if entries.is_empty() {
        return PenetrationResult::Empty;
    }

    let directories: Vec<&FileTreeNode> = entries.iter().filter(|entry| entry.is_dir).collect();
    let archives: Vec<&FileTreeNode> = entries.iter().filter(|entry| entry.is_archive).collect();
    let media: Vec<&FileTreeNode> = entries
        .iter()
        .filter(|entry| entry.is_image || entry.is_video || entry.is_audio)
        .collect();

    // Neo 的混合媒体目录：两张以上散图作为一本，子目录留给上下本遍历。
    if !directories.is_empty() && media.len() >= 2 {
        return PenetrationResult::Terminal(path.to_path_buf());
    }

    // 唯一归档允许和封面图共存；多个候选或归档与子目录混合时必须让用户选择。
    if directories.is_empty() && archives.len() == 1 {
        return PenetrationResult::Terminal(PathBuf::from(&archives[0].path));
    }
    if directories.is_empty() && archives.is_empty() && !media.is_empty() {
        return PenetrationResult::Terminal(path.to_path_buf());
    }
    if directories.len() == 1 && archives.is_empty() {
        if depth >= max_depth {
            return PenetrationResult::Blocked;
        }
        return resolve_penetration_inner(
            Path::new(&directories[0].path),
            depth + 1,
            max_depth,
            show_hidden_files,
            visited,
        );
    }
    PenetrationResult::Branch
}

fn describe_children(path: &Path, settings: &FileManagerSettings) -> Vec<FileManagerChild> {
    let Ok(entries) = list_directory_with_hidden(path, settings.show_hidden_files) else {
        return Vec::new();
    };
    let limit = match settings.internal_items_mode {
        InternalItemsMode::Single => 1,
        InternalItemsMode::All => entries.len(),
    };
    entries
        .into_iter()
        .take(limit)
        .map(|entry| {
            if entry.is_dir && settings.penetration_enabled {
                let mut visited = HashSet::new();
                if let PenetrationResult::Terminal(target) = resolve_penetration_inner(
                    Path::new(&entry.path),
                    0,
                    settings.max_depth.min(MAX_PENETRATION_DEPTH),
                    settings.show_hidden_files,
                    &mut visited,
                ) {
                    let name = target
                        .file_name()
                        .and_then(|value| value.to_str())
                        .unwrap_or(&entry.name)
                        .to_string();
                    let extension = target
                        .extension()
                        .and_then(|value| value.to_str())
                        .map(|value| value.to_ascii_lowercase())
                        .unwrap_or_default();
                    let target_is_archive = crate::file_tree::is_comic_archive_path(&target);
                    let is_dir = target.is_dir();
                    return FileManagerChild {
                        path: target,
                        name,
                        is_dir,
                        is_archive: !is_dir && target_is_archive,
                        is_image: crate::folder_tree::is_recognized_image_ext(&extension),
                        is_video: crate::media_formats::is_video_ext(&extension),
                        is_audio: crate::folder_tree::is_audio_ext(&extension),
                    };
                }
            }
            FileManagerChild {
                path: PathBuf::from(&entry.path),
                name: entry.name,
                is_dir: entry.is_dir,
                is_archive: entry.is_archive,
                is_image: entry.is_image,
                is_video: entry.is_video,
                is_audio: entry.is_audio,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn touch(path: &Path) {
        fs::write(path, b"x").unwrap();
    }

    #[test]
    fn video_entries_open_as_the_selected_media_file() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("000-cover.jpg"));
        for ext in crate::page_order::VIDEO_EXTENSIONS {
            touch(&dir.path().join(format!("视频 2.{}", ext.to_uppercase())));
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_entry_filter(EntryFilter::Video);
        let entries = state.entries().unwrap();
        assert_eq!(entries.len(), crate::page_order::VIDEO_EXTENSIONS.len());
        for entry in entries {
            let entry = entry.node;
            assert!(entry.is_video, "{}", entry.name);
            let OpenEntryResult::Opened(path) = state.open_entry(&entry.path, false).unwrap()
            else {
                panic!("点击视频应该打开 Reader");
            };
            assert_eq!(path, Path::new(&entry.path));
            assert_eq!(state.active_path(), dir.path());

            // 不能只放行文件管理器：交给 Reader 的路径也必须能真正打开。
            let source = crate::LocalSource::open(&path).unwrap();
            assert_eq!(source.kind(), crate::SourceKind::MediaFile);
            assert_eq!(source.root(), path);
            assert_eq!(source.len(), 1);
            assert_eq!(source.pages()[0].name, entry.name);
            assert_eq!(source.total_bytes(), 1);
            assert_eq!(source.page_bytes(0).unwrap(), b"x");
            assert!(source.page_bytes(1).is_err());
        }
    }

    #[test]
    fn loose_image_opens_the_directory_it_lives_in() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("page_1.jpg"));
        let target = dir.path().join("page_2.jpg");
        touch(&target);
        fs::create_dir(dir.path().join("nested")).unwrap();
        touch(&dir.path().join("nested").join("page_9.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();

        let OpenEntryResult::Opened(opened) = state.open_entry(&target, false).unwrap() else {
            panic!("点击松散图片应该打开 Reader");
        };
        // 书是那个目录，不是这一张；点开的那一张由调用方作为起始页带上。
        assert_eq!(opened, dir.path());
        let source = crate::LocalSource::open(&opened).unwrap();
        assert_eq!(source.kind(), crate::SourceKind::Folder);
        // 平铺里有东西就不进子目录，所以这一本只有两张。
        assert_eq!(source.len(), 2);

        // 压缩包自身就是一本书，不能被同样的解析提到父目录。
        let archive = dir.path().join("book.cbz");
        touch(&archive);
        assert_eq!(
            state.open_entry(&archive, false).unwrap(),
            OpenEntryResult::Opened(archive)
        );

        // RAW 在文件列表那张表里算图片，但页序不认它：提升上去只会翻出一本空书，
        // 平铺为空时还要递归进子目录捞无关页，所以这种后缀保持按单个文件交给 Reader。
        let raw = dir.path().join("shot.cr2");
        touch(&raw);
        assert!(crate::folder_tree::is_recognized_image_ext("cr2"));
        assert!(!crate::page_order::is_page_name("shot.cr2"));
        assert_eq!(
            state.open_entry(&raw, false).unwrap(),
            OpenEntryResult::Opened(raw)
        );
    }

    #[test]
    fn open_entry_still_rejects_unsupported_or_missing_files() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        for name in ["readme.txt", "song.mp3"] {
            let path = dir.path().join(name);
            touch(&path);
            assert!(state.open_entry(&path, false).is_err());
        }
        assert!(
            state
                .open_entry(dir.path().join("missing.mp4"), false)
                .is_err()
        );
        assert_eq!(state.active_path(), dir.path());
    }

    #[test]
    fn tabs_keep_history_and_switch_active_tab() {
        let dir = tempdir().unwrap();
        let a = dir.path().join("a");
        let b = dir.path().join("b");
        fs::create_dir(&a).unwrap();
        fs::create_dir(&b).unwrap();
        let mut state = FileManagerState::new(Some(a.clone())).unwrap();
        state.navigate(b.clone()).unwrap();
        assert!(state.active_tab().can_go_back());
        assert!(state.go_back());
        assert!(same_path(state.active_path(), &a));
        let id = state.new_tab(Some(b.clone())).unwrap();
        assert_eq!(state.active_tab_id(), id);
        assert!(state.activate_tab(1));
        assert!(same_path(state.active_path(), &a));
    }

    #[test]
    fn breadcrumb_navigation_and_text_edits_share_history_and_reject_bad_paths() {
        let dir = tempdir().unwrap();
        let chapter = dir.path().join("中文 空格").join("chapter");
        fs::create_dir_all(&chapter).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate_text("\"中文 空格/chapter\"").unwrap();
        assert_eq!(state.active_path(), chapter);
        let parts = state.breadcrumbs();
        assert!(parts.first().unwrap().is_root);
        assert!(parts.last().unwrap().is_current);
        assert_eq!(parts.last().unwrap().name, "chapter");
        assert_eq!(parts[parts.len() - 2].name, "中文 空格");
        state.navigate(&parts[parts.len() - 2].path).unwrap();
        assert!(state.go_back());
        assert_eq!(state.active_path(), chapter);
        let tabs = state.tabs().to_vec();
        let generation = state.generation();
        for invalid in ["", " \"\" ", "missing", "missing/../chapter"] {
            assert!(state.navigate_text(invalid).is_err());
            assert_eq!(state.tabs(), tabs);
            assert_eq!(state.generation(), generation);
        }
        state.navigate(&parts.first().unwrap().path).unwrap();
        assert!(!state.can_go_up());
    }

    #[test]
    fn directory_columns_are_opt_in_tab_local_and_independent_of_search() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let chapter = books.join("chapter 2");
        fs::create_dir_all(&chapter).unwrap();
        fs::create_dir(books.join("chapter 10")).unwrap();
        touch(&books.join("book.cbz"));
        let mut state = FileManagerState::new(Some(chapter.clone())).unwrap();
        assert!(state.directory_columns().is_empty());
        state.set_directory_columns_enabled(true);
        state.set_search_query("does not match folders");
        let columns = state.directory_columns();
        assert!(columns.len() <= 3);
        let column = columns.iter().find(|column| column.path == books).unwrap();
        assert_eq!(
            column
                .entries
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>(),
            ["chapter 2", "chapter 10"]
        );
        assert!(column.entries[0].selected);
        assert!(!column.entries[1].selected);
        assert!(columns.last().unwrap().entries.is_empty());
        state.new_tab(None).unwrap();
        assert!(!state.settings().directory_columns_enabled);
        state.activate_tab(1);
        assert!(state.settings().directory_columns_enabled);
        let copied = state.duplicate_tab(1).unwrap();
        assert!(state.settings().directory_columns_enabled);
        assert_eq!(state.active_tab_id(), copied);
    }

    #[cfg(unix)]
    #[test]
    fn path_edit_resolves_parent_after_symlink_and_preserves_backslash_names() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        let real = dir.path().join("real").join("child");
        fs::create_dir_all(&real).unwrap();
        symlink(&real, dir.path().join("link")).unwrap();
        fs::create_dir(dir.path().join(r"a\b")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate_text(r"a\b").unwrap();
        assert_eq!(state.breadcrumbs().last().unwrap().name, r"a\b");
        assert!(state.go_back());
        state.navigate_text("link/..").unwrap();
        assert_eq!(
            state.active_path(),
            fs::canonicalize(real.parent().unwrap()).unwrap()
        );
    }

    #[test]
    fn penetration_resolves_unique_nested_archive_and_rejects_branch() {
        let dir = tempdir().unwrap();
        let root = dir.path().join("root");
        let nested = root.join("nested");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&nested).unwrap();
        touch(&nested.join("book.cbz"));
        let state = FileManagerState::new(Some(root.clone())).unwrap();
        assert_eq!(
            state.resolve_penetration(&root),
            PenetrationResult::Terminal(nested.join("book.cbz"))
        );
        touch(&nested.join("second.cbz"));
        assert_eq!(state.resolve_penetration(&root), PenetrationResult::Branch);
    }

    #[test]
    fn child_name_projection_supports_single_and_all_modes() {
        let dir = tempdir().unwrap();
        let root = dir.path().join("root");
        let child = root.join("child");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&child).unwrap();
        touch(&child.join("1.cbz"));
        touch(&child.join("2.cbz"));
        let mut state = FileManagerState::new(Some(root)).unwrap();
        state.set_penetration_enabled(true);
        state.set_show_child_names(true);
        assert_eq!(state.entries().unwrap()[0].children.len(), 1);
        state.set_internal_items_mode(InternalItemsMode::All);
        assert_eq!(state.entries().unwrap()[0].children.len(), 2);
    }

    #[test]
    fn open_archive_accepts_mimageviewer_containers_without_navigating() {
        let dir = tempdir().unwrap();
        let archive = dir.path().join("book.CBZ");
        touch(&archive);
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        let generation = state.generation();

        assert_eq!(state.open_archive(&archive).unwrap(), archive);
        assert_eq!(state.generation(), generation);
        assert!(same_path(state.active_path(), dir.path()));
    }

    #[test]
    fn open_archive_rejects_non_archive_files() {
        let dir = tempdir().unwrap();
        let image = dir.path().join("cover.jpg");
        touch(&image);
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();

        let error = state.open_archive(&image).unwrap_err().to_string();
        assert!(error.contains("不是可打开的压缩包"));
    }
    #[test]
    fn bulk_close_noop_keeps_tabs_and_generation() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let original = state.tabs().to_vec();
        let generation = state.generation();
        assert!(!state.close_other_tabs(1));
        assert!(!state.close_tabs_left(1));
        assert!(!state.close_tabs_right(1));
        assert_eq!(state.tabs(), original);
        assert_eq!(state.active_tab_id(), 1);
        assert_eq!(state.generation(), generation);
        let second = state.new_tab(None).unwrap();
        state.toggle_tab_pinned(second);
        assert!(!state.close_other_tabs(1));
        assert_eq!(state.tabs().len(), 2);
        assert_eq!(state.active_tab_id(), second);
    }

    #[test]
    fn bulk_close_protects_pins_and_preserves_surviving_active_tab() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let pinned = state.new_tab(None).unwrap();
        state.toggle_tab_pinned(pinned);
        let third = state.new_tab(None).unwrap();
        let fourth = state.new_tab(None).unwrap();
        state.activate_tab(pinned);
        assert!(state.close_tabs_right(third));
        assert_eq!(state.active_tab_id(), pinned);
        assert_eq!(state.recently_closed()[0].id, fourth);
        assert!(state.close_other_tabs(1));
        assert_eq!(
            state.tabs().iter().map(|tab| tab.id).collect::<Vec<_>>(),
            [1, pinned]
        );
        assert_eq!(state.active_tab_id(), pinned);
        assert!(!state.close_tabs_right(1));
        assert!(!state.can_close_tabs_on_side(1, false));
    }

    #[test]
    fn duplicate_and_reopen_keep_independent_query_sort_and_history() {
        let dir = tempdir().unwrap();
        let child = dir.path().join("child");
        fs::create_dir(&child).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate(&child).unwrap();
        state.set_search_query("book");
        state.set_sort(SortField::Size, SortOrder::Descending);
        state.set_entry_filter(EntryFilter::Archives);
        let copied = state.duplicate_tab(1).unwrap();
        state.set_search_query("other");
        state.activate_tab(1);
        assert_eq!(state.settings().search_query, "book");
        assert!(state.close_tab(copied));
        let reopened = state.reopen_closed_tab(copied).unwrap();
        assert_ne!(reopened, copied);
        assert_eq!(state.settings().search_query, "other");
        assert_eq!(state.settings().sort_field, SortField::Size);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);
        assert_eq!(state.settings().entry_filter, EntryFilter::Archives);
        assert!(state.active_tab().can_go_back());
        assert!(state.go_back());
        assert!(state.settings().search_query.is_empty());
        assert!(same_path(state.active_path(), dir.path()));
    }

    #[test]
    fn unavailable_closed_tab_is_not_lost_and_limits_are_enforced() {
        let dir = tempdir().unwrap();
        let child = dir.path().join("removed");
        fs::create_dir(&child).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let closed = state.new_tab(Some(child.clone())).unwrap();
        assert!(state.close_tab(closed));
        fs::remove_dir(child).unwrap();
        assert!(state.reopen_closed_tab(closed).is_err());
        assert_eq!(state.recently_closed().len(), 1);
        assert_eq!(state.tabs().len(), 1);
        assert!(!state.can_close_tab(1));
        for _ in 1..MAX_FILE_MANAGER_TABS {
            state.new_tab(None).unwrap();
        }
        assert!(!state.can_create_tab());
        assert!(state.new_tab(None).is_err());
        assert!(state.duplicate_tab(1).is_err());
        assert!(state.reopen_closed_tab(closed).is_err());
    }

    #[test]
    fn search_is_unicode_name_matching_and_filters_sort_in_rust() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("zzz-folder")).unwrap();
        fs::write(dir.path().join("Book 2.cbz"), b"xx").unwrap();
        fs::write(dir.path().join("Book 10.cbz"), b"xxxxxxxxxx").unwrap();
        touch(&dir.path().join("ÉTÉ.jpg"));
        touch(&dir.path().join("aaa.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_search_query("  BOOK  ");
        let names = |state: &FileManagerState| {
            state
                .entries()
                .unwrap()
                .into_iter()
                .map(|entry| entry.node.name)
                .collect::<Vec<_>>()
        };
        assert_eq!(names(&state), ["Book 2.cbz", "Book 10.cbz"]);
        state.set_sort(SortField::Size, SortOrder::Descending);
        assert_eq!(names(&state), ["Book 10.cbz", "Book 2.cbz"]);
        state.set_search_query("été");
        assert_eq!(names(&state), ["ÉTÉ.jpg"]);
        state.set_entry_filter(EntryFilter::Archives);
        assert!(names(&state).is_empty());
        state.set_search_query("");
        assert_eq!(names(&state).len(), 2);
        state.set_entry_filter(EntryFilter::All);
        state.set_sort(SortField::Name, SortOrder::Ascending);
        assert_eq!(names(&state)[0], "zzz-folder");
        assert_eq!(names(&state)[1], "aaa.jpg");
        state.set_directories_first(false);
        assert_eq!(names(&state)[0], "aaa.jpg");
        // A parent directory name must not make every child match.
        state.set_search_query(dir.path().file_name().unwrap().to_string_lossy());
        assert!(names(&state).is_empty());
    }

    #[test]
    fn search_uses_token_grammar_and_or_mode() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("summer_photo.jpg"));
        touch(&dir.path().join("summer draft.jpg"));
        touch(&dir.path().join("autumn.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let names = |state: &FileManagerState| {
            state
                .entries()
                .unwrap()
                .into_iter()
                .map(|entry| entry.node.name)
                .collect::<Vec<_>>()
        };
        // 空格分词：整串子串匹配在这条上必然 0 结果，文件名里的 `_` 也不该挡住。
        state.set_search_query("summer photo");
        assert_eq!(names(&state), ["summer_photo.jpg"]);
        // 否定词元与引号短语。
        state.set_search_query("summer -draft");
        assert_eq!(names(&state), ["summer_photo.jpg"]);
        state.set_search_query(r#""summer draft""#);
        assert_eq!(names(&state), ["summer draft.jpg"]);
        // AND 下两个词都必须在；切到 OR 后任命中即保留，并按名称排序。
        state.set_search_query("photo autumn");
        assert!(names(&state).is_empty());
        state.set_search_or_mode(true);
        assert_eq!(names(&state), ["autumn.jpg", "summer_photo.jpg"]);
        // 只有否定词元时是「不含它的都留下」。
        state.set_search_query("-summer");
        assert_eq!(names(&state), ["autumn.jpg"]);
    }

    #[test]
    fn search_in_path_never_lets_the_root_name_match_every_child() {
        let dir = tempdir().unwrap();
        let spring = dir.path().join("spring");
        fs::create_dir(&spring).unwrap();
        touch(&spring.join("001.jpg"));
        touch(&spring.join("002.jpg"));
        let mut state = FileManagerState::new(Some(spring.clone())).unwrap();
        assert!(state.settings().search_in_path);
        state.set_search_query("spring");
        assert!(state.entries().unwrap().is_empty());
        state.set_search_query("00");
        assert_eq!(state.entries().unwrap().len(), 2);
        state.set_search_in_path(false);
        assert_eq!(state.entries().unwrap().len(), 2);
    }

    fn search_fixture(root: &Path) {
        fs::create_dir_all(root.join("春组/本子")).unwrap();
        fs::create_dir_all(root.join("秋组")).unwrap();
        touch(&root.join("春组/本子/001.jpg"));
        touch(&root.join("春组/cover.cbz"));
        touch(&root.join("秋组/wind.jpg"));
        // 非媒体：列表本来就不收，搜索也不该凭空造出一条来。
        touch(&root.join("readme.txt"));
    }

    #[test]
    fn recursive_search_descends_and_reports_relative_directory() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_query("春");
        let single = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(single.scanned, 3);
        assert_eq!(single.matched, 1);
        assert_eq!(single.hits[0].name, "春组");
        assert_eq!(
            single.hits[0].path,
            dir.path().join("春组").to_string_lossy()
        );

        state.set_search_include_subfolders(true);
        let deep = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(deep.scanned, 7);
        // 命中 4 条：`春组` 本身，以及相对路径里带着 `春` 的三条
        //（`春组/本子`、`春组/cover.cbz`、`春组/本子/001.jpg`）。
        assert_eq!(deep.matched, 4);
        // 相对目录不再单独带字段，用 path 相对搜索根算出来即可。
        let mut hits = deep
            .hits
            .iter()
            .map(|node| {
                let relative = Path::new(&node.path)
                    .parent()
                    .and_then(|parent| parent.strip_prefix(dir.path()).ok())
                    .map(|rel| rel.to_string_lossy().replace('\\', "/"))
                    .unwrap_or_default();
                (relative, node.name.clone())
            })
            .collect::<Vec<_>>();
        hits.sort_unstable();
        assert_eq!(
            hits,
            [
                (String::new(), "春组".to_string()),
                ("春组".to_string(), "cover.cbz".to_string()),
                ("春组".to_string(), "本子".to_string()),
                ("春组/本子".to_string(), "001.jpg".to_string()),
            ]
        );
        assert!(!deep.truncated);
    }

    #[test]
    fn recursive_search_matches_relative_path_tokens_and_respects_depth() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_include_subfolders(true);
        // 「本子 001」跨目录分隔符匹配：词元分别命中相对目录与条目名。
        state.set_search_query("本子 001");
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            1
        );
        state.set_search_in_path(false);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );

        // 深度 1 只多扫一层：春组看得到，春组/本子 看不到。
        state.set_search_in_path(true);
        state.set_search_query("001");
        state.set_search_max_depth(99);
        let deep = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert!(deep.hits[0].path.ends_with("春组/本子/001.jpg"));
        state.set_search_max_depth(1);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );
    }

    #[test]
    fn recursive_search_honours_hidden_policy_entry_filter_and_cancel() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        touch(&dir.path().join("春组/.secret.cbz"));
        fs::create_dir(dir.path().join("春组/mimageviewer.meta.miv")).unwrap();
        touch(&dir.path().join("春组/mimageviewer.meta.miv/ghost.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_include_subfolders(true);
        state.set_search_query("secret ghost");
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );
        state.set_search_query("secret ghost 001 wind cover");
        state.set_search_or_mode(true);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            3
        );
        state.set_search_or_mode(false);
        // 空查询不是「全量列出」：递归搜索直接早退，一个条目都不检视。
        state.set_search_query("");
        let idle = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert!(idle.hits.is_empty());
        assert_eq!(idle.scanned, 0);
        state.set_search_query("cbz");
        state.set_entry_filter(EntryFilter::Archives);
        let archives = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(
            archives
                .hits
                .iter()
                .map(|node| node.name.as_str())
                .collect::<Vec<_>>(),
            ["cover.cbz"]
        );
        state.set_show_hidden_files(true);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            2
        );

        // 取消：已置位的令牌让遍历一步都不走，但请求本身仍算正常交出。
        let cancelled = search_entries(&state.search_request(), &AtomicBool::new(true));
        assert!(cancelled.cancelled);
        assert!(cancelled.hits.is_empty());
        assert_eq!(cancelled.scanned, 0);
    }

    #[test]
    fn recursive_search_caps_results_at_the_limit_and_flags_truncation() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("many")).unwrap();
        for index in 0..=MAX_SEARCH_RESULTS {
            touch(&dir.path().join("many").join(format!("book-{index:04}.cbz")));
        }
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_query("book");
        state.set_search_include_subfolders(true);
        let outcome = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(outcome.hits.len(), MAX_SEARCH_RESULTS);
        assert!(outcome.truncated);
        assert!(outcome.matched >= MAX_SEARCH_RESULTS);
        assert!(!outcome.cancelled);
    }

    #[cfg(unix)]
    #[test]
    fn hidden_policy_is_shared_by_listing_children_and_penetration() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        touch(&books.join("visible.cbz"));
        touch(&books.join(".hidden.cbz"));
        touch(&books.join("._metadata.jpg"));
        fs::create_dir(books.join("mimageviewer.meta.miv")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_penetration_enabled(true);
        state.set_internal_items_mode(InternalItemsMode::All);
        assert!(matches!(
            state.resolve_penetration(&books),
            PenetrationResult::Terminal(_)
        ));
        assert_eq!(state.entries().unwrap()[0].children.len(), 1);
        state.set_show_hidden_files(true);
        assert_eq!(state.resolve_penetration(&books), PenetrationResult::Branch);
        assert_eq!(state.entries().unwrap()[0].children.len(), 2);
        state.navigate(books).unwrap();
        assert_eq!(state.entries().unwrap().len(), 2);
    }

    #[test]
    fn projected_media_directory_can_be_opened_as_a_directory() {
        let dir = tempdir().unwrap();
        let series = dir.path().join("series");
        let chapter = series.join("chapter");
        fs::create_dir_all(&chapter).unwrap();
        touch(&chapter.join("page.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_penetration_enabled(true);
        let child = state.entries().unwrap().remove(0).children.remove(0);
        assert!(child.is_dir);
        assert_eq!(
            state.open_entry(&child.path, false).unwrap(),
            OpenEntryResult::Opened(chapter)
        );
    }

    #[cfg(unix)]
    #[test]
    fn unix_symlinks_are_browsable_and_penetration_stops_cycles() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        touch(&books.join("book.cbz"));
        symlink(&books, dir.path().join("linked-books")).unwrap();
        symlink(books.join("book.cbz"), dir.path().join("linked.cbz")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let entries = state.entries().unwrap();
        assert!(
            entries
                .iter()
                .any(|entry| entry.node.name == "linked-books" && entry.node.is_dir)
        );
        assert!(
            entries
                .iter()
                .any(|entry| entry.node.name == "linked.cbz" && entry.node.is_archive)
        );
        state.navigate(dir.path().join("linked-books")).unwrap();
        assert_eq!(state.entries().unwrap().len(), 1);
        let loop_dir = dir.path().join("loop");
        fs::create_dir(&loop_dir).unwrap();
        symlink(&loop_dir, loop_dir.join("self")).unwrap();
        assert_eq!(
            state.resolve_penetration(&loop_dir),
            PenetrationResult::Blocked
        );
    }

    #[cfg(unix)]
    #[test]
    fn upstream_dfs_does_not_fold_distinct_unix_paths_into_a_cycle() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        // Backslash is a valid Unix filename character, not a path separator.
        // This works on the default case-insensitive macOS filesystem as well.
        let origin = dir.path().join(r"a\b");
        let target = dir.path().join("a").join("b");
        fs::create_dir(&origin).unwrap();
        fs::create_dir_all(&target).unwrap();
        let link = origin.join("link");
        symlink(&target, &link).unwrap();
        assert_eq!(
            crate::folder_tree::next_folder_dfs(
                &origin,
                crate::folder_tree::FolderTreeOptions::default()
            ),
            Some(link),
        );
    }

    #[test]
    fn natural_sort_orders_numbers_before_letters_in_entries() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("BaiduNetdiskDownload")).unwrap();
        fs::create_dir(dir.path().join("CloudMusic")).unwrap();
        fs::create_dir(dir.path().join("Game")).unwrap();
        fs::create_dir(dir.path().join("1BACKUP")).unwrap();
        fs::create_dir(dir.path().join("1GAME")).unwrap();

        let state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let names: Vec<String> = state
            .entries()
            .unwrap()
            .into_iter()
            .map(|e| e.node.name)
            .collect();

        assert_eq!(
            names,
            vec![
                "1BACKUP",
                "1GAME",
                "BaiduNetdiskDownload",
                "CloudMusic",
                "Game"
            ]
        );
    }

    #[test]
    fn per_location_view_state_persistence_and_inheritance() {
        let dir = tempdir().unwrap();
        let folder_a = dir.path().join("folder_a");
        let sub_a = folder_a.join("sub");
        let folder_b = dir.path().join("folder_b");
        fs::create_dir_all(&sub_a).unwrap();
        fs::create_dir_all(&folder_b).unwrap();

        let mut state = FileManagerState::new(Some(folder_a.clone())).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::Compact);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);

        // 在 folder_a 中设置封面网格和降序
        state.set_view_mode(ViewMode::CoverGrid);
        state.set_sort(SortField::Name, SortOrder::Descending);

        // 导航到 sub_a，继承 folder_a 的视图配置
        state.navigate(&sub_a).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);

        // 导航到未配置的 folder_b，恢复默认配置（Compact + Ascending）
        state.navigate(&folder_b).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::Compact);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);

        // 后退回到 sub_a，再次继承并还原 folder_a 的 CoverGrid + Descending
        assert!(state.go_back());
        assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);
    }

    fn entry_names(state: &FileManagerState) -> Vec<String> {
        state
            .entries()
            .unwrap()
            .into_iter()
            .map(|entry| entry.node.name)
            .collect()
    }

    fn set_mtime(path: &Path, secs: u64) {
        let file = fs::File::options().write(true).open(path).unwrap();
        file.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(secs))
            .unwrap();
    }

    #[test]
    fn home_pad_target_is_settable_and_enters_the_back_stack() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(other.clone())).unwrap();

        // 未设置主页：主页键不可跳转，但允许右键写入一个主页。
        assert!(state.home_path().is_none());
        assert!(!state.is_home());
        assert!(state.can_set_home());
        assert!(!state.go_home());

        assert!(state.set_home_path(Some(books.clone())));
        assert_eq!(state.home_path(), Some(books.as_path()));
        assert!(state.can_set_home());
        assert!(!state.is_home());
        // 同一值重复写入是空操作。
        let generation = state.generation();
        assert!(!state.set_home_path(Some(books.clone())));
        assert_eq!(state.generation(), generation);

        assert!(state.go_home());
        assert!(state.is_home());
        assert!(!state.can_set_home());
        assert!(same_path(state.active_path(), &books));
        assert!(state.generation() > generation);
        // 主页跳转进入后退栈，后退回到原目录。
        assert!(state.go_back());
        assert!(same_path(state.active_path(), &other));

        // 已在主页上再点一次不产生历史、也不推进 generation。
        assert!(state.go_home());
        let generation = state.generation();
        assert!(!state.go_home());
        assert_eq!(state.generation(), generation);
        assert!(same_path(state.active_path(), &books));

        // 不存在的目录不能成为主页；清除后主页键重新不可用。
        assert!(!state.set_home_path(Some(dir.path().join("missing"))));
        assert!(state.is_home());
        assert!(state.set_home_path(None));
        assert!(state.home_path().is_none());
        assert!(!state.go_home());
    }

    #[test]
    fn date_sort_uses_mtime_and_random_sort_is_stable_between_snapshots() {
        let dir = tempdir().unwrap();
        for (name, mtime) in [("a.cbz", 30u64), ("b.cbz", 10), ("c.cbz", 20)] {
            let path = dir.path().join(name);
            touch(&path);
            set_mtime(&path, mtime);
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();

        state.set_sort(SortField::Date, SortOrder::Ascending);
        assert_eq!(entry_names(&state), ["b.cbz", "c.cbz", "a.cbz"]);
        state.set_sort(SortField::Date, SortOrder::Descending);
        assert_eq!(entry_names(&state), ["a.cbz", "c.cbz", "b.cbz"]);

        let by_name = {
            state.set_sort(SortField::Name, SortOrder::Ascending);
            entry_names(&state)
        };
        assert_eq!(by_name, ["a.cbz", "b.cbz", "c.cbz"]);

        // 切进随机：重新掷种子，并且同一快照序列内顺序不跳动。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        let seed = state.settings().shuffle_seed;
        assert_ne!(seed, 0);
        let shuffled = entry_names(&state);
        assert_eq!(shuffled, entry_names(&state));
        let mut permutation = shuffled.clone();
        permutation.sort();
        assert_eq!(permutation, by_name);

        // 在随机字段上只换方向不重掷种子，顺序就是同一个洗牌的倒序。
        state.set_sort(SortField::Random, SortOrder::Descending);
        assert_eq!(state.settings().shuffle_seed, seed);
        let mut reversed = entry_names(&state);
        reversed.reverse();
        assert_eq!(reversed, shuffled);

        // 刷新才重新洗牌。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        assert_eq!(entry_names(&state), shuffled);
        state.refresh();
        assert_ne!(state.settings().shuffle_seed, seed);
        let mut reshuffled = entry_names(&state);
        reshuffled.sort();
        assert_eq!(reshuffled, by_name);
    }

    #[test]
    fn fixed_shuffle_seed_does_not_degenerate_into_name_order() {
        // 洗牌键必须是名称的函数，且真的会打乱名称序，否则「随机」只是换个说法。
        assert_eq!(shuffle_key(7, "a.cbz"), shuffle_key(7, "a.cbz"));
        assert_ne!(shuffle_key(7, "a.cbz"), shuffle_key(8, "a.cbz"));
        assert_ne!(shuffle_key(7, "a.cbz"), shuffle_key(7, "b.cbz"));

        let dir = tempdir().unwrap();
        for name in ["a.cbz", "b.cbz", "c.cbz", "d.cbz", "e.cbz"] {
            touch(&dir.path().join(name));
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_sort(SortField::Name, SortOrder::Ascending);
        let by_name = entry_names(&state);
        state.set_sort(SortField::Random, SortOrder::Ascending);
        state.tabs[state.active_tab].settings.shuffle_seed = 0x1234_5678;
        let fixed = entry_names(&state);
        let mut permutation = fixed.clone();
        permutation.sort();
        assert_eq!(permutation, by_name);
        assert_ne!(fixed, by_name);
    }

    #[test]
    fn temporary_sort_keeps_the_locked_directory_sort() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let key = crate::settings_db::view_state_key(&books);
        assert!(!state.sort_temporary());
        assert!(state.can_sort_preference());

        // 锁定：降序写进本目录的视图状态。
        state.set_sort(SortField::Name, SortOrder::Descending);
        assert_eq!(state.view_states()[&key].sort_order, SortOrder::Descending);

        // 临时：画面变升序，但目录偏好仍是降序。
        state.set_sort_temporary(true);
        assert!(state.sort_temporary());
        let generation = state.generation();
        state.set_sort_temporary(true);
        assert_eq!(state.generation(), generation);
        state.set_sort(SortField::Name, SortOrder::Ascending);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
        assert_eq!(state.view_states()[&key].sort_order, SortOrder::Descending);

        // 离开再回来：恢复的是锁定的降序，临时排序没有漏进偏好。
        state.navigate(&other).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
        state.navigate(&books).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Descending);

        // 关闭临时排序＝把当前排序锁定下来。
        state.set_sort_temporary(false);
        assert!(!state.sort_temporary());
        state.set_sort(SortField::Name, SortOrder::Ascending);
        state.navigate(&other).unwrap();
        state.navigate(&books).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
    }

    #[test]
    fn every_view_setting_is_captured_and_round_trips_without_loss() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let key = crate::settings_db::view_state_key(&books);

        // 六种视图模式里挑三种只存在于文件管理器的：经 reader 那套两档映射往返
        // 会被塌成「详细信息」，这里必须逐字记住。
        for mode in [
            ViewMode::CoverList,
            ViewMode::MosaicList,
            ViewMode::MosaicGrid,
        ] {
            state.set_view_mode(mode);
            assert_eq!(state.view_states()[&key].view_mode, mode);
        }
        state.set_entry_filter(EntryFilter::Images);
        assert_eq!(state.view_states()[&key].entry_filter, EntryFilter::Images);
        state.set_directories_first(false);
        assert!(!state.view_states()[&key].directories_first);
        state.set_show_hidden_files(true);
        assert!(state.view_states()[&key].show_hidden_files);

        // 这些偏好必须能越过 JSON 边界：会话层就是靠它落盘的。
        let before = state.view_states()[&key].clone();
        let json = serde_json::to_string(&before).unwrap();
        let after: FileManagerViewState = serde_json::from_str(&json).unwrap();
        assert_eq!(before, after);

        // 换个会话把它 hydrate 回来：视图、筛选、隐藏项与目录优先都要还原。
        let mut restored = FileManagerState::new(Some(books.clone())).unwrap();
        restored.hydrate_view_states(state.view_states().clone());
        assert_eq!(restored.settings().view_mode, ViewMode::MosaicGrid);
        assert_eq!(restored.settings().entry_filter, EntryFilter::Images);
        assert!(!restored.settings().directories_first);
        assert!(restored.settings().show_hidden_files);
    }

    #[test]
    fn dirty_view_states_only_report_real_changes() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let books_key = crate::settings_db::view_state_key(&books);
        let other_key = crate::settings_db::view_state_key(&other);

        // 新建会话本身没有待写入的改动。
        assert!(state.take_dirty_view_states().is_empty());

        state.set_view_mode(ViewMode::Details);
        let dirty = state.take_dirty_view_states();
        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.view_mode, ViewMode::Details);
        // 取出即清空。
        assert!(state.take_dirty_view_states().is_empty());

        // 同一值重复写入不产生脏记录（否则每次导航都会重写一遍数据库）。
        state.set_view_mode(ViewMode::Details);
        assert!(state.take_dirty_view_states().is_empty());

        // 临时排序只活在画面里：改了排序也不该产生待写入的目录偏好。
        state.set_sort_temporary(true);
        state.set_sort(SortField::Size, SortOrder::Descending);
        assert!(state.take_dirty_view_states().is_empty());
        state.set_sort_temporary(false);
        let _ = state.take_dirty_view_states();

        // 离开目录时的写回收口：`refresh()` 重掷的种子不经过 capture，
        // 要等离开这个目录才落进它的偏好。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        let _ = state.take_dirty_view_states();
        state.tabs[state.active_tab].settings.shuffle_seed = 0xBEEF;
        assert!(state.take_dirty_view_states().is_empty());

        state.navigate(&other).unwrap();
        let dirty = state.take_dirty_view_states();
        assert_eq!(dirty.len(), 1, "只应该带回离开的那个目录: {dirty:?}");
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.shuffle_seed, 0xBEEF);
        assert_ne!(dirty[0].0, other_key);
    }

    #[test]
    fn hydrate_never_marks_rows_dirty_and_remember_off_stops_capture() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let books_key = crate::settings_db::view_state_key(&books);

        let mut source = FileManagerState::new(Some(books.clone())).unwrap();
        source.set_view_mode(ViewMode::CoverGrid);
        let saved = source.view_states().clone();

        // hydrate 进来的数据来自磁盘，不是待写入的改动。
        let mut restored = FileManagerState::new(Some(books.clone())).unwrap();
        restored.hydrate_view_states(saved);
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(restored.settings().view_mode, ViewMode::CoverGrid);

        // 关掉记忆：视图照样生效，但不再产生目录偏好。
        restored.set_remember_view_state(false);
        assert!(!restored.can_sort_preference());
        restored.set_view_mode(ViewMode::Compact);
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(
            restored.view_states()[&books_key].view_mode,
            ViewMode::CoverGrid
        );
        // 关着的时候换目录也不留下新记录。
        restored.navigate(&other).unwrap();
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(restored.settings().view_mode, ViewMode::Compact);

        // 重新打开：从这一刻起继续记，且不会把关着期间的临时值写回旧目录。
        restored.set_remember_view_state(true);
        restored.navigate(&books).unwrap();
        assert_eq!(restored.settings().view_mode, ViewMode::CoverGrid);
        restored.set_view_mode(ViewMode::Details);
        let dirty = restored.take_dirty_view_states();
        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.view_mode, ViewMode::Details);
    }
}
