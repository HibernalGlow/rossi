//! 将已有目录展开投影与普通条目枚举合并；这里不管理另一份树状态。
use std::collections::HashMap;
use std::path::Path;

use rossi_local_core::FileManagerState;

use super::{
    map_entry,
    types::{FileManagerTreeRow, FileManagerTreeSnapshot},
};

pub(super) fn integrate_tree_content(
    state: &FileManagerState,
    tree: FileManagerTreeSnapshot,
) -> FileManagerTreeSnapshot {
    let known: HashMap<_, _> = tree
        .rows
        .iter()
        .map(|row| (row.path.clone(), row.clone()))
        .collect();
    let mut rows = Vec::new();
    fn append(
        state: &FileManagerState,
        mut row: FileManagerTreeRow,
        known: &HashMap<String, FileManagerTreeRow>,
        rows: &mut Vec<FileManagerTreeRow>,
    ) {
        if !row.expanded || row.depth >= 64 {
            rows.push(row);
            return;
        }
        match state.hierarchy_entries_in_directory(Path::new(&row.path)) {
            Ok(entries) => {
                // 目录树原来只知道子目录，含文件的目录也必须保留展开箭头。
                row.may_have_children = !entries.is_empty() || row.loading;
                let depth = row.depth + 1;
                rows.push(row);
                for entry in entries {
                    let mut child = known.get(&entry.node.path).cloned().unwrap_or_else(|| {
                        FileManagerTreeRow {
                            path: entry.node.path.clone(),
                            name: entry.node.name.clone(),
                            depth,
                            entry: None,
                            expanded: false,
                            loading: false,
                            may_have_children: entry.node.is_dir && entry.node.has_children,
                            is_active: Path::new(&entry.node.path) == state.active_path(),
                            error: None,
                        }
                    });
                    child.depth = depth;
                    child.may_have_children |= entry.node.is_dir && entry.node.has_children;
                    child.entry = Some(map_entry(entry));
                    append(state, child, known, rows);
                }
            }
            Err(error) => {
                row.error = Some(error.to_string());
                rows.push(row);
            }
        }
    }
    for row in tree.rows.iter().filter(|row| row.depth == 0) {
        append(state, row.clone(), &known, &mut rows);
    }
    FileManagerTreeSnapshot {
        rows,
        has_pending: tree.has_pending,
    }
}
