//! 可迁移的文件管理器状态机。
//!
//! 这一层只依赖 `std::fs` 和本 crate 已有的目录枚举器，不依赖 Flutter、egui 或
//! 任何具体 UI。Rossi 的泳道卡片、桌面边栏以及后续的 Tauri / WASM 外壳都应该只
//! 负责把这里的快照画出来并转发动作。
//!
//! 目录枚举与自然排序沿用 `file_tree`（其过滤、排序规则对应 mImageViewer 的
//! `folder_tree` / `filename_sort`），状态机则把 NeoView 的多页签、穿透和子文件名
//! 投影收拢到一个可测试的 Rust API 中。

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};

use crate::file_tree::{FileTreeNode, list_directory_with_hidden};

/// NeoView 文件卡片默认的页签上限。上限属于核心状态，而不是 Dart 的布局常量，
/// 这样其它 UI 不会因为自己的按钮实现而出现不同的行为。
pub const MAX_FILE_MANAGER_TABS: usize = 8;
pub const MAX_RECENTLY_CLOSED_TABS: usize = 16;
pub const MAX_PENETRATION_DEPTH: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortOrder {
    Ascending,
    Descending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryFilter {
    All,
    Folders,
    Archives,
    Images,
    Video,
    Audio,
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
    pub fn apply_favorite_view_state(&mut self, state: &crate::settings::FavoriteViewState) {
        match state.grid_view_mode {
            crate::settings::GridViewMode::Thumbnail => self.view_mode = ViewMode::CoverGrid,
            crate::settings::GridViewMode::Details => self.view_mode = ViewMode::Details,
        }
        match state.sort_order {
            crate::settings::SortOrder::FileName
            | crate::settings::SortOrder::NameAsc
            | crate::settings::SortOrder::Numeric => {
                self.sort_field = SortField::Name;
                self.sort_order = SortOrder::Ascending;
            }
            crate::settings::SortOrder::NameDesc => {
                self.sort_field = SortField::Name;
                self.sort_order = SortOrder::Descending;
            }
            crate::settings::SortOrder::DateAsc => {
                self.sort_field = SortField::Name;
                self.sort_order = SortOrder::Ascending;
            }
            crate::settings::SortOrder::DateDesc => {
                self.sort_field = SortField::Name;
                self.sort_order = SortOrder::Descending;
            }
        }
    }

    pub fn to_favorite_view_state(
        &self,
        base: &crate::settings::FavoriteViewState,
    ) -> crate::settings::FavoriteViewState {
        let mut state = base.clone();
        state.grid_view_mode = match self.view_mode {
            ViewMode::CoverGrid | ViewMode::MosaicGrid => {
                crate::settings::GridViewMode::Thumbnail
            }
            _ => crate::settings::GridViewMode::Details,
        };
        state.sort_order = match (self.sort_field, self.sort_order) {
            (SortField::Name, SortOrder::Ascending) => crate::settings::SortOrder::NameAsc,
            (SortField::Name, SortOrder::Descending) => crate::settings::SortOrder::NameDesc,
            _ => base.sort_order,
        };
        state
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
}

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
        }
    }

    pub fn title(&self) -> String {
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
    view_states: std::collections::HashMap<String, crate::settings::FavoriteViewState>,
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
            let base = self.view_states.get(&id).cloned().unwrap_or_else(|| {
                crate::settings::FavoriteViewState::from_settings(&crate::settings::Settings::default())
            });
            let updated = view_state_from_settings(&tab.settings, &base);
            self.view_states.insert(id, updated);
        }

        // 2. 核心规则：切换位置时先干净回退到 common 公共值正本
        tab.settings.view_mode = tab.common_settings.view_mode;
        tab.settings.sort_field = tab.common_settings.sort_field;
        tab.settings.sort_order = tab.common_settings.sort_order;

        // 3. 寻找新路径的最长匹配并套用 overlay
        if let Some((id, state)) =
            crate::settings_db::resolve_view_state_for_path(target_path, &self.view_states)
        {
            tab.active_view_state_id = Some(id);
            tab.settings.apply_favorite_view_state(&state);
        }
    }

    fn capture_active_view_state(&mut self) {
        if !self.remember_view_state {
            return;
        }
        let tab = &mut self.tabs[self.active_tab];
        let path_str = tab.path.to_string_lossy().into_owned();
        tab.active_view_state_id = Some(path_str.clone());
        let base = self.view_states.get(&path_str).cloned().unwrap_or_else(|| {
            crate::settings::FavoriteViewState::from_settings(&crate::settings::Settings::default())
        });
        let updated = view_state_from_settings(&tab.settings, &base);
        self.view_states.insert(path_str, updated);
    }

    pub fn hydrate_view_states(
        &mut self,
        states: std::collections::HashMap<String, crate::settings::FavoriteViewState>,
    ) {
        self.view_states = states;
        let current_path = self.active_path().to_path_buf();
        self.transition_view_state_for_path(&current_path);
    }

    pub fn view_states(&self) -> &std::collections::HashMap<String, crate::settings::FavoriteViewState> {
        &self.view_states
    }

    pub fn set_remember_view_state(&mut self, enabled: bool) {
        self.remember_view_state = enabled;
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
            self.bump_generation();
        }
    }

    pub fn set_search_query(&mut self, query: impl Into<String>) {
        let query = query.into().trim().to_owned();
        if self.tabs[self.active_tab].settings.search_query != query {
            self.tabs[self.active_tab].settings.search_query = query;
            self.bump_generation();
        }
    }

    pub fn set_entry_filter(&mut self, filter: EntryFilter) {
        if self.tabs[self.active_tab].settings.entry_filter != filter {
            self.tabs[self.active_tab].settings.entry_filter = filter;
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
            if !crate::file_tree::is_comic_archive_path(path)
                && !crate::folder_tree::is_recognized_image_ext(&extension)
            {
                return Err(anyhow!("当前 Reader 暂不支持直接打开 {}", path.display()));
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
        let mut nodes = list_directory_with_hidden(
            self.active_path(),
            self.tabs[self.active_tab].settings.show_hidden_files,
        )?;
        nodes.retain(|node| self.matches_entry(node));
        nodes.sort_by(|left, right| self.compare_entries(left, right));
        Ok(nodes
            .into_iter()
            .map(|node| {
                let children = if node.is_dir
                    && self.tabs[self.active_tab].settings.penetration_enabled
                    && self.tabs[self.active_tab].settings.show_child_names
                {
                    describe_children(Path::new(&node.path), &self.tabs[self.active_tab].settings)
                } else {
                    Vec::new()
                };
                FileManagerEntry { node, children }
            })
            .collect())
    }

    fn matches_entry(&self, node: &FileTreeNode) -> bool {
        let query = self.tabs[self.active_tab]
            .settings
            .search_query
            .to_lowercase();
        if !query.is_empty() && !node.name.to_lowercase().contains(&query) {
            return false;
        }
        match self.tabs[self.active_tab].settings.entry_filter {
            EntryFilter::All => true,
            EntryFilter::Folders => node.is_dir,
            EntryFilter::Archives => node.is_archive,
            EntryFilter::Images => node.is_image,
            EntryFilter::Video => node.is_video,
            EntryFilter::Audio => node.is_audio,
        }
    }

    fn compare_entries(&self, left: &FileTreeNode, right: &FileTreeNode) -> std::cmp::Ordering {
        use std::cmp::Ordering;

        let rank = |node: &FileTreeNode| !node.is_dir;
        let directories = self.tabs[self.active_tab]
            .settings
            .directories_first
            .then(|| rank(left).cmp(&rank(right)));
        let field_order = match self.tabs[self.active_tab].settings.sort_field {
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
                let seed = self.tabs[self.active_tab].settings.shuffle_seed;
                // 名称兜底让比较器保持全序；同一目录内名称唯一，实际不会触发。
                shuffle_key(seed, &left.name)
                    .cmp(&shuffle_key(seed, &right.name))
                    .then_with(|| natural_name_cmp(&left.name, &right.name))
            }
        };
        let order = if self.tabs[self.active_tab].settings.sort_order == SortOrder::Descending {
            field_order.reverse()
        } else {
            field_order
        };
        directories.unwrap_or(Ordering::Equal).then(order)
    }

    fn bump_generation(&mut self) {
        self.generation = self.generation.wrapping_add(1).max(1);
    }
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

/// 目录视图状态的唯一写入口。
///
/// 「临时排序」只应该活在当前画面里，所以置位时把上一次锁定的排序盖回去，避免它在
/// 离开目录（`transition_view_state_for_path`）或另一次 capture 时顺带落进目录偏好。
fn view_state_from_settings(
    settings: &FileManagerSettings,
    base: &crate::settings::FavoriteViewState,
) -> crate::settings::FavoriteViewState {
    let mut state = settings.to_favorite_view_state(base);
    if settings.sort_temporary {
        state.sort_order = base.sort_order;
    }
    state
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
                        is_video: crate::folder_tree::SUPPORTED_VIDEO_EXTENSIONS
                            .contains(&extension.as_str()),
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
        let key = books.to_string_lossy().into_owned();
        assert!(!state.sort_temporary());
        assert!(state.can_sort_preference());

        // 锁定：降序写进本目录的视图状态。
        state.set_sort(SortField::Name, SortOrder::Descending);
        assert_eq!(
            state.view_states()[&key].sort_order,
            crate::settings::SortOrder::NameDesc
        );

        // 临时：画面变升序，但目录偏好仍是降序。
        state.set_sort_temporary(true);
        assert!(state.sort_temporary());
        let generation = state.generation();
        state.set_sort_temporary(true);
        assert_eq!(state.generation(), generation);
        state.set_sort(SortField::Name, SortOrder::Ascending);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
        assert_eq!(
            state.view_states()[&key].sort_order,
            crate::settings::SortOrder::NameDesc
        );

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
}
