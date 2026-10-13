//! 搜索层级只是命中集合的投影：祖先补齐不触发任何文件系统访问。
use super::*;
use std::collections::HashMap;

pub struct SearchHierarchyRow {
    pub path: PathBuf,
    pub name: String,
    pub depth: usize,
    pub entry: Option<FileManagerEntry>,
    pub expanded: bool,
    pub has_children: bool,
}

struct Node {
    path: PathBuf,
    entry: Option<FileManagerEntry>,
    children: Vec<usize>,
}

impl FileManagerState {
    /// 查询确认时复制页签设置，源页签退出预览，新的搜索页签独立拥有结果。
    pub fn search_in_new_tab(&mut self, query: String) -> Result<u64> {
        if !self.can_create_tab() {
            return Err(anyhow!("页签数量已达到上限 ({MAX_FILE_MANAGER_TABS})"));
        }
        if query.trim().is_empty() {
            return Err(anyhow!("请输入搜索词"));
        }
        let mut copy = self.active_tab().clone();
        copy.settings = self.new_tab_settings(copy.id);
        copy.common_settings = copy.settings.clone();
        copy.id = self.next_tab_id;
        self.next_tab_id = self.next_tab_id.saturating_add(1);
        copy.pinned = false;
        copy.back.clear();
        copy.forward.clear();
        copy.settings.search_query = query.trim().to_owned();
        copy.search = None;
        copy.detached_search = true;
        copy.search_tree_collapsed.clear();
        copy.search_column_path = None;
        let source = &mut self.tabs[self.active_tab];
        if source.detached_search {
            if let Some(listing) = &source.search {
                source.settings.search_query = listing.query.clone();
            }
        } else {
            source.settings.search_query.clear();
            source.search = None;
            source.search_tree_collapsed.clear();
            source.search_column_path = None;
        }
        let id = copy.id;
        self.tabs.push(copy);
        self.active_tab = self.tabs.len() - 1;
        self.bump_generation();
        Ok(id)
    }

    pub fn toggle_search_tree(&mut self, path: &Path) {
        if !self
            .search_hierarchy_all()
            .iter()
            .any(|row| row.path == path && row.has_children)
        {
            return;
        }
        let collapsed = &mut self.tabs[self.active_tab].search_tree_collapsed;
        if !collapsed.remove(path) {
            collapsed.insert(path.to_path_buf());
        }
        // 展开状态不改变命中列表与 generation，避免无意义地重新搜索或重绑选中。
    }

    pub fn search_hierarchy(&self) -> Vec<SearchHierarchyRow> {
        self.build_search_hierarchy(false)
    }
    fn search_hierarchy_all(&self) -> Vec<SearchHierarchyRow> {
        self.build_search_hierarchy(true)
    }

    fn build_search_hierarchy(&self, include_collapsed: bool) -> Vec<SearchHierarchyRow> {
        let Some(listing) = self.search_listing() else {
            return Vec::new();
        };
        let mut nodes = vec![Node {
            path: listing.root.clone(),
            entry: None,
            children: Vec::new(),
        }];
        let mut indices = HashMap::from([(listing.root.clone(), 0)]);
        for entry in &listing.entries {
            let path = PathBuf::from(&entry.node.path);
            if !path.starts_with(&listing.root) || path == listing.root {
                continue;
            }
            let mut chain: Vec<_> = path
                .ancestors()
                .take_while(|p| *p != listing.root)
                .collect();
            chain.reverse();
            let mut parent = 0;
            for component in chain {
                let index = *indices.entry(component.to_path_buf()).or_insert_with(|| {
                    let index = nodes.len();
                    nodes.push(Node {
                        path: component.to_path_buf(),
                        entry: None,
                        children: Vec::new(),
                    });
                    nodes[parent].children.push(index);
                    index
                });
                parent = index;
            }
            nodes[parent].entry = Some(entry.clone());
        }
        fn walk(
            nodes: &[Node],
            index: usize,
            depth: usize,
            collapsed: &HashSet<PathBuf>,
            all: bool,
            rows: &mut Vec<SearchHierarchyRow>,
        ) {
            let node = &nodes[index];
            let has_children = !node.children.is_empty();
            let expanded = has_children && !collapsed.contains(&node.path);
            rows.push(SearchHierarchyRow {
                path: node.path.clone(),
                name: directory_title(&node.path),
                depth,
                entry: node.entry.clone(),
                expanded,
                has_children,
            });
            if expanded || all {
                for &child in &node.children {
                    walk(nodes, child, depth + 1, collapsed, all, rows);
                }
            }
        }
        let mut rows = Vec::new();
        walk(
            &nodes,
            0,
            0,
            &self.active_tab().search_tree_collapsed,
            include_collapsed,
            &mut rows,
        );
        rows
    }

    pub fn select_search_directory(&mut self, path: PathBuf) -> Result<()> {
        let rows = self.search_hierarchy_all();
        if !rows
            .iter()
            .any(|row| row.path == path && (row.entry.as_ref().is_none_or(|e| e.node.is_dir)))
        {
            return Err(anyhow!("不是搜索结果中的目录"));
        }
        self.tabs[self.active_tab].search_column_path = Some(path);
        self.bump_generation();
        Ok(())
    }

    pub fn search_directory_columns(&self) -> Vec<FileManagerDirectoryColumn> {
        let Some(listing) = self.search_listing() else {
            return Vec::new();
        };
        let rows = self.search_hierarchy_all();
        let cursor = self
            .active_tab()
            .search_column_path
            .as_deref()
            .filter(|p| rows.iter().any(|r| r.path == *p))
            .unwrap_or(&listing.root);
        let mut chain: Vec<_> = cursor
            .ancestors()
            .take_while(|p| p.starts_with(&listing.root))
            .collect();
        chain.reverse();
        chain
            .iter()
            .map(|&path| FileManagerDirectoryColumn {
                path: path.to_path_buf(),
                name: directory_title(path),
                error: None,
                entries: rows
                    .iter()
                    .filter(|row| row.path.parent() == Some(path))
                    .map(|row| FileManagerDirectoryChoice {
                        entry: row.entry.clone(),
                        path: row.path.clone(),
                        name: row.name.clone(),
                        selected: chain.contains(&row.path.as_path()),
                    })
                    .collect(),
            })
            .collect()
    }
}
