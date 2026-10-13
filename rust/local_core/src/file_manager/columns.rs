//! 复用目录枚举与路径导航的分栏投影。
use super::*;

impl FileManagerState {
    /// Neo 列导航只展开当前路径最后三层，关闭时完全不读取列目录。
    /// 枚举/隐藏规则/自然排序继续复用 mImageViewer 适配层；搜索不会隐藏导航目录。
    pub fn directory_columns(&self) -> Vec<FileManagerDirectoryColumn> {
        if self.search_listing().is_some() && self.settings().layout_mode == LayoutMode::Columns {
            return self.search_directory_columns();
        }
        if !self.settings().directory_columns_enabled
            && self.settings().layout_mode != LayoutMode::Columns
        {
            return Vec::new();
        }
        let breadcrumbs = self.breadcrumbs();
        breadcrumbs
            .iter()
            .skip(if self.settings().layout_mode == LayoutMode::Columns {
                0
            } else {
                breadcrumbs.len().saturating_sub(3)
            })
            .map(|segment| {
                let (entries, error) = match self.hierarchy_entries_in_directory(&segment.path) {
                    Ok(nodes) => (
                        nodes
                            .into_iter()
                            .filter(|entry| {
                                self.settings().layout_mode == LayoutMode::Columns
                                    || entry.node.is_dir
                            })
                            .map(|entry| FileManagerDirectoryChoice {
                                path: PathBuf::from(&entry.node.path),
                                name: entry.node.name.clone(),
                                selected: breadcrumbs
                                    .iter()
                                    .any(|part| same_path(&part.path, Path::new(&entry.node.path))),
                                entry: Some(entry),
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
}
