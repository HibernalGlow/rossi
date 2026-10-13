//! 新页签起手选项；继承的是浏览设置，查询、选中、结果与历史始终独立。
use super::*;

impl FileManagerState {
    pub fn configure_new_tabs(&mut self, policy: NewTabPolicy, defaults: FileManagerSettings) {
        self.search_subfolders_default = defaults.search_include_subfolders;
        self.tab_policy = policy;
        self.tab_defaults = defaults;
    }

    /// 首个页签没有可继承来源，先用预设；会话随后仍可叠加已保存的目录条目样式。
    pub fn initialize_tab_defaults(&mut self) {
        let defaults = self.tab_defaults.clone();
        let tab = &mut self.tabs[self.active_tab];
        tab.settings = defaults.clone();
        tab.common_settings = defaults;
        self.bump_generation();
    }

    pub fn new_tab_settings(&self, trigger: u64) -> FileManagerSettings {
        let mut settings = match self.tab_policy {
            NewTabPolicy::Defaults => self.tab_defaults.clone(),
            NewTabPolicy::Recent => self.settings().clone(),
            NewTabPolicy::Triggering => self
                .tabs
                .iter()
                .find(|tab| tab.id == trigger)
                .map(|tab| tab.settings.clone())
                .unwrap_or_else(|| self.tab_defaults.clone()),
        };
        settings.search_query.clear();
        settings.sort_temporary = false;
        if self.tab_policy == NewTabPolicy::Defaults {
            settings.search_include_subfolders = self.search_subfolders_default;
        }
        settings
    }

    pub fn new_tab(&mut self, path: Option<PathBuf>) -> Result<u64> {
        self.new_tab_from(path, self.active_tab_id())
    }

    pub fn new_tab_from(&mut self, path: Option<PathBuf>, trigger: u64) -> Result<u64> {
        if !self.can_create_tab() {
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
        let settings = self.new_tab_settings(trigger);
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        let mut tab = FileManagerTab::new(id, target);
        tab.settings = settings.clone();
        tab.common_settings = settings;
        self.tabs.push(tab);
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(id)
    }
}
