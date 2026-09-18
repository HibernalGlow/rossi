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

use crate::file_tree::{FileTreeNode, list_directory};

/// NeoView 文件卡片默认的页签上限。上限属于核心状态，而不是 Dart 的布局常量，
/// 这样其它 UI 不会因为自己的按钮实现而出现不同的行为。
pub const MAX_FILE_MANAGER_TABS: usize = 8;
pub const MAX_PENETRATION_DEPTH: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewMode {
    List,
    Grid,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSettings {
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: InternalItemsMode,
    pub max_depth: usize,
    pub view_mode: ViewMode,
}

impl Default for FileManagerSettings {
    fn default() -> Self {
        Self {
            penetration_enabled: false,
            show_child_names: true,
            internal_items_mode: InternalItemsMode::Single,
            max_depth: 3,
            view_mode: ViewMode::List,
        }
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
pub struct FileManagerTab {
    pub id: u64,
    pub path: PathBuf,
    pub back: Vec<PathBuf>,
    pub forward: Vec<PathBuf>,
}

impl FileManagerTab {
    fn new(id: u64, path: PathBuf) -> Self {
        Self {
            id,
            path,
            back: Vec::new(),
            forward: Vec::new(),
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
pub struct FileManagerState {
    tabs: Vec<FileManagerTab>,
    active_tab: usize,
    next_tab_id: u64,
    generation: u64,
    settings: FileManagerSettings,
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
            generation: 1,
            settings: FileManagerSettings::default(),
        })
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn settings(&self) -> &FileManagerSettings {
        &self.settings
    }

    pub fn tabs(&self) -> &[FileManagerTab] {
        &self.tabs
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

    pub fn set_penetration_enabled(&mut self, enabled: bool) {
        if self.settings.penetration_enabled != enabled {
            self.settings.penetration_enabled = enabled;
            self.bump_generation();
        }
    }

    pub fn set_show_child_names(&mut self, enabled: bool) {
        if self.settings.show_child_names != enabled {
            self.settings.show_child_names = enabled;
            self.bump_generation();
        }
    }

    pub fn set_internal_items_mode(&mut self, mode: InternalItemsMode) {
        if self.settings.internal_items_mode != mode {
            self.settings.internal_items_mode = mode;
            self.bump_generation();
        }
    }

    pub fn set_max_depth(&mut self, depth: usize) {
        let depth = depth.clamp(1, MAX_PENETRATION_DEPTH);
        if self.settings.max_depth != depth {
            self.settings.max_depth = depth;
            self.bump_generation();
        }
    }

    pub fn set_view_mode(&mut self, mode: ViewMode) {
        if self.settings.view_mode != mode {
            self.settings.view_mode = mode;
            self.bump_generation();
        }
    }

    pub fn navigate(&mut self, path: impl Into<PathBuf>) -> Result<()> {
        let path = path.into();
        if !path.is_dir() {
            return Err(anyhow!("路径不是有效目录: {}", path.display()));
        }
        let tab = &mut self.tabs[self.active_tab];
        if same_path(&tab.path, &path) {
            return Ok(());
        }
        let previous = std::mem::replace(&mut tab.path, path);
        tab.back.push(previous);
        tab.forward.clear();
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
        if self.tabs.len() <= 1 {
            return false;
        }
        let Some(index) = self.tabs.iter().position(|tab| tab.id == id) else {
            return false;
        };
        self.tabs.remove(index);
        if self.active_tab > index {
            self.active_tab -= 1;
        } else if self.active_tab == index {
            self.active_tab = self.active_tab.min(self.tabs.len() - 1);
        }
        self.bump_generation();
        true
    }

    pub fn open_entry(
        &mut self,
        path: impl AsRef<Path>,
        force_enter: bool,
    ) -> Result<OpenEntryResult> {
        let path = path.as_ref();
        if path.is_dir() {
            if !force_enter && self.settings.penetration_enabled {
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
            self.settings.max_depth.min(MAX_PENETRATION_DEPTH),
            &mut visited,
        )
    }

    pub fn entries(&self) -> Result<Vec<FileManagerEntry>> {
        let nodes = list_directory(self.active_path())?;
        Ok(nodes
            .into_iter()
            .map(|node| {
                let children = if node.is_dir
                    && self.settings.penetration_enabled
                    && self.settings.show_child_names
                {
                    describe_children(Path::new(&node.path), &self.settings)
                } else {
                    Vec::new()
                };
                FileManagerEntry { node, children }
            })
            .collect())
    }

    fn bump_generation(&mut self) {
        self.generation = self.generation.wrapping_add(1).max(1);
    }
}

fn normalize_initial_directory(path: PathBuf) -> Option<PathBuf> {
    if path.is_dir() {
        return Some(path);
    }
    if path.is_file() {
        return path.parent().map(Path::to_path_buf);
    }
    None
}

fn default_directory() -> Option<PathBuf> {
    crate::file_tree::get_available_roots()
        .into_iter()
        .find_map(|root| normalize_initial_directory(PathBuf::from(root.path)))
}

fn same_path(a: &Path, b: &Path) -> bool {
    crate::folder_tree::path_eq(a, b)
}

fn visit_key(path: &Path) -> String {
    crate::fs_entry::directory_visit_key(path)
}

fn resolve_penetration_inner(
    path: &Path,
    depth: usize,
    max_depth: usize,
    visited: &mut HashSet<String>,
) -> PenetrationResult {
    if depth > max_depth || depth >= MAX_PENETRATION_DEPTH {
        return PenetrationResult::Blocked;
    }
    if !visited.insert(visit_key(path)) {
        return PenetrationResult::Blocked;
    }
    let entries = match list_directory(path) {
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
            visited,
        );
    }
    PenetrationResult::Branch
}

fn describe_children(path: &Path, settings: &FileManagerSettings) -> Vec<FileManagerChild> {
    let Ok(entries) = list_directory(path) else {
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
                    return FileManagerChild {
                        path: target,
                        name,
                        is_dir: false,
                        is_archive: target_is_archive,
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
}
