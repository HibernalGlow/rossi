// 从 file_manager.rs 整块原样搬出；除补必要的可见性前缀外未改一个字符。
use super::*;

/// 一个 UI 无关的文件浏览状态。
#[derive(Clone)]
pub struct FileManagerState {
    pub(super) tabs: Vec<FileManagerTab>,
    pub(super) active_tab: usize,
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
