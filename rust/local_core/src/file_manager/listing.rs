// 从 file_manager.rs 整块原样搬出；除补必要的可见性前缀外未改一个字符。
use super::*;

pub(super) fn resolve_penetration_inner(
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
    judge_penetration(path, &entries, depth, max_depth, show_hidden_files, visited)
}

/// 拿着「已经列好的这一层」判决穿透。与 [`resolve_penetration_inner`] 同一套规则，
/// 只是目录内容现成传入 —— `describe_children` 本来就要读这一层，父目录该不该被
/// 穿透（UI 用它决定双击有没有意义）于是不用多开一次盘。
///
/// 层数闸门在这里重复一遍是有意的：`resolve_penetration_inner` 在**读盘之前**就要它，
/// 好让走到上限的那条链不去枚举最后一层；这里再要一次，是为了单独调用本函数的人也
/// 拿到同一个判决，而不必先自己判。
pub(super) fn judge_penetration(
    path: &Path,
    entries: &[FileTreeNode],
    depth: usize,
    max_depth: usize,
    show_hidden_files: bool,
    visited: &mut HashSet<String>,
) -> PenetrationResult {
    if depth > max_depth || depth >= MAX_PENETRATION_DEPTH {
        return PenetrationResult::Blocked;
    }
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

pub(super) fn describe_children(
    path: &Path,
    settings: &FileManagerSettings,
) -> (bool, Vec<FileManagerChild>) {
    let Ok(entries) = list_directory_with_hidden(path, settings.show_hidden_files) else {
        return (false, Vec::new());
    };
    // 这一层的判决要在**截断之前**用整份列表算：`internal_items_mode = Single` 只截
    // 要展示的条数，「只有一个归档」这种判据看的是全部。
    let penetratable = settings.penetration_enabled
        && matches!(
            judge_penetration(
                path,
                &entries,
                0,
                settings.max_depth.min(MAX_PENETRATION_DEPTH),
                settings.show_hidden_files,
                &mut HashSet::new(),
            ),
            PenetrationResult::Terminal(_)
        );
    let limit = match settings.internal_items_mode {
        InternalItemsMode::Single => 1,
        InternalItemsMode::All => entries.len(),
    };
    let children: Vec<FileManagerChild> = entries
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
        .collect();
    (penetratable, children)
}

impl FileManagerState {
    pub fn entries(&self) -> Result<Vec<FileManagerEntry>> {
        // 搜索结果页签：列表就是上一次遍历交出的命中，不再枚举当前目录。
        // 「列表只有一份真本」是这里的目的 —— UI 不再自己揣一份结果数组。
        if let Some(search) = &self.tabs[self.active_tab].search {
            return Ok(search.entries.clone());
        }
        self.entries_in_directory(self.active_path())
    }

    /// 树和分栏复用当前会话的枚举、筛选、排序和条目描述，不改变路径或导航历史。
    pub fn entries_in_directory(&self, root: &Path) -> Result<Vec<FileManagerEntry>> {
        self.layout_entries_in_directory(root, false)
    }

    /// 目录节点承担层级导航，按文件类型筛选时仍保留它们；文件沿用同一筛选规则。
    pub fn hierarchy_entries_in_directory(&self, root: &Path) -> Result<Vec<FileManagerEntry>> {
        self.layout_entries_in_directory(root, true)
    }

    fn layout_entries_in_directory(
        &self,
        root: &Path,
        keep_directories: bool,
    ) -> Result<Vec<FileManagerEntry>> {
        let settings = self.settings();
        // 词元在整份列表上复用，只在解析查询时 lowercase 一次；逐条目再解析会把
        // O(条目) 变成 O(条目 × 查询长度) 的分配。
        let tokens = crate::search_query::parse(&settings.search_query);
        let mut nodes = list_directory_with_hidden(root, settings.show_hidden_files)?;
        nodes.retain(|node| {
            (keep_directories && node.is_dir) || matches_entry(settings, node, &tokens, root)
        });
        nodes.sort_by(|left, right| compare_entries(settings, left, right));
        Ok(nodes
            .into_iter()
            .map(|node| {
                // 「这一行的单击会不会被穿透劫走」和子文件名共用同一次列目录（见
                // `describe_children`）。UI 需要它才敢给文件夹行挂双击：挂上就要为
                // 每一次单击付一个 kDoubleTapTimeout，所以只该挂在**真的**有两种含义
                // 的那些行上。
                let (penetratable, children) = if node.is_dir && settings.penetration_enabled {
                    let (penetratable, listed) = describe_children(Path::new(&node.path), settings);
                    (
                        penetratable,
                        if settings.show_child_names {
                            listed
                        } else {
                            Vec::new()
                        },
                    )
                } else {
                    (false, Vec::new())
                };
                FileManagerEntry {
                    node,
                    penetratable,
                    children,
                }
            })
            .collect())
    }
}
