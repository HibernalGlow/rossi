//! 跨 UI 的本地文件管理器会话。
//!
//! 这里是 Flutter 之外的唯一状态入口：页签、导航历史、穿透策略和子文件名投影都由
//! `rossi_local_core::FileManagerState` 维护。Flutter/桌面边栏只收到不可变快照并转发
//! 用户动作，因此未来换成 Tauri、egui 或 CLI 时不需要复制一套业务状态机。

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Error, anyhow};
use dashmap::DashMap;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use rossi_local_core::{
    FileManagerEntry as CoreEntry, FileManagerState, InternalItemsMode, OpenEntryResult, ViewMode,
};

use super::local::LocalRootLocation;

lazy_static! {
    static ref FILE_MANAGER_SESSIONS: DashMap<u64, FileManagerState> = DashMap::new();
    static ref NEXT_FILE_MANAGER_ID: AtomicU64 = AtomicU64::new(1);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerInternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerViewMode {
    List,
    Grid,
}

#[derive(Debug, Clone)]
pub struct FileManagerTab {
    pub id: u64,
    pub title: String,
    pub path: String,
    pub can_go_back: bool,
    pub can_go_forward: bool,
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
    pub has_children: bool,
    /// NeoView 的「显示内部条目」投影。它不改变父目录列表，只为 UI 提供一小段
    /// 可点击的上下文提示。
    pub child_names: Vec<FileManagerChild>,
}

#[derive(Debug, Clone)]
pub struct FileManagerSnapshot {
    pub session_id: u64,
    pub generation: u64,
    pub active_tab_id: u64,
    pub active_path: String,
    pub tabs: Vec<FileManagerTab>,
    pub entries: Vec<FileManagerEntry>,
    pub roots: Vec<LocalRootLocation>,
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: FileManagerInternalItemsMode,
    pub max_depth: u8,
    pub view_mode: FileManagerViewMode,
}

#[derive(Debug, Clone)]
pub struct FileManagerActionResult {
    pub snapshot: FileManagerSnapshot,
    /// 非空时表示 UI 应该把该路径交给 Reader；浏览器自身仍停留在原目录。
    pub opened_path: Option<String>,
}

#[frb]
pub async fn file_manager_create(initial_path: Option<String>) -> Result<u64, Error> {
    let path = initial_path.map(PathBuf::from);
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let state = FileManagerState::new(path)?;
            let id = NEXT_FILE_MANAGER_ID.fetch_add(1, Ordering::Relaxed);
            FILE_MANAGER_SESSIONS.insert(id, state);
            Ok(id)
        })
        .await?
}

#[frb]
pub async fn file_manager_snapshot(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| snapshot_for(id, state)).await
}

#[frb]
pub async fn file_manager_refresh(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.refresh();
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_navigate(id: u64, path: String) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.navigate(PathBuf::from(path))?;
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_go_back(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.go_back();
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_go_forward(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.go_forward();
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_go_up(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.go_up();
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_new_tab(
    id: u64,
    path: Option<String>,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.new_tab(path.map(PathBuf::from))?;
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_activate_tab(id: u64, tab_id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.activate_tab(tab_id) {
            return Err(anyhow!("页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_close_tab(id: u64, tab_id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.close_tab(tab_id) {
            return Err(anyhow!("最后一个页签不能关闭，或页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_open_entry(
    id: u64,
    path: String,
    force_enter: bool,
) -> Result<FileManagerActionResult, Error> {
    with_session(id, move |state| {
        let opened_path = match state.open_entry(PathBuf::from(path), force_enter)? {
            OpenEntryResult::Entered(_) => None,
            OpenEntryResult::Opened(path) => Some(path.to_string_lossy().into_owned()),
        };
        Ok(FileManagerActionResult {
            snapshot: snapshot_for(id, state)?,
            opened_path,
        })
    })
    .await
}

/// Open an archive from a double-click without changing the browser location.
///
/// The core validates the path with mImageViewer's archive predicates, so every
/// UI gets the same ZIP/CBZ/RAR/7z/LZH handling and cannot accidentally route a
/// normal file through the archive gesture.
#[frb]
pub async fn file_manager_open_archive(
    id: u64,
    path: String,
) -> Result<FileManagerActionResult, Error> {
    with_session(id, move |state| {
        let opened_path = state
            .open_archive(PathBuf::from(path))?
            .to_string_lossy()
            .into_owned();
        Ok(FileManagerActionResult {
            snapshot: snapshot_for(id, state)?,
            opened_path: Some(opened_path),
        })
    })
    .await
}

#[frb]
pub async fn file_manager_set_penetration(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_penetration_enabled(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_show_child_names(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_show_child_names(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_internal_items_mode(
    id: u64,
    mode: FileManagerInternalItemsMode,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_internal_items_mode(match mode {
            FileManagerInternalItemsMode::Single => InternalItemsMode::Single,
            FileManagerInternalItemsMode::All => InternalItemsMode::All,
        });
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_max_depth(id: u64, depth: u8) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_max_depth(depth as usize);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_view_mode(
    id: u64,
    mode: FileManagerViewMode,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_view_mode(match mode {
            FileManagerViewMode::List => ViewMode::List,
            FileManagerViewMode::Grid => ViewMode::Grid,
        });
        snapshot_for(id, state)
    })
    .await
}

#[frb(sync)]
pub fn file_manager_close(id: u64) -> bool {
    FILE_MANAGER_SESSIONS.remove(&id).is_some()
}

async fn with_session<R, F>(id: u64, operation: F) -> Result<R, Error>
where
    R: Send + 'static,
    F: FnOnce(&mut FileManagerState) -> Result<R, Error> + Send + 'static,
{
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let mut state = FILE_MANAGER_SESSIONS
                .get_mut(&id)
                .ok_or_else(|| anyhow!("文件管理器会话不存在或已关闭: id={id}"))?;
            operation(&mut state)
        })
        .await?
}

fn snapshot_for(id: u64, state: &mut FileManagerState) -> Result<FileManagerSnapshot, Error> {
    let entries = state.entries()?.into_iter().map(map_entry).collect();
    let tabs = state
        .tabs()
        .iter()
        .map(|tab| FileManagerTab {
            id: tab.id,
            title: tab.title(),
            path: tab.path.to_string_lossy().into_owned(),
            can_go_back: tab.can_go_back(),
            can_go_forward: tab.can_go_forward(),
        })
        .collect();
    let roots = rossi_local_core::get_available_roots()
        .into_iter()
        .map(|root| LocalRootLocation {
            label: root.label,
            path: root.path,
        })
        .collect();
    let settings = state.settings();
    Ok(FileManagerSnapshot {
        session_id: id,
        generation: state.generation(),
        active_tab_id: state.active_tab_id(),
        active_path: state.active_path().to_string_lossy().into_owned(),
        tabs,
        entries,
        roots,
        penetration_enabled: settings.penetration_enabled,
        show_child_names: settings.show_child_names,
        internal_items_mode: match settings.internal_items_mode {
            InternalItemsMode::Single => FileManagerInternalItemsMode::Single,
            InternalItemsMode::All => FileManagerInternalItemsMode::All,
        },
        max_depth: settings.max_depth as u8,
        view_mode: match settings.view_mode {
            ViewMode::List => FileManagerViewMode::List,
            ViewMode::Grid => FileManagerViewMode::Grid,
        },
    })
}

fn map_entry(entry: CoreEntry) -> FileManagerEntry {
    FileManagerEntry {
        path: entry.node.path,
        name: entry.node.name,
        is_dir: entry.node.is_dir,
        is_archive: entry.node.is_archive,
        is_image: entry.node.is_image,
        is_video: entry.node.is_video,
        is_audio: entry.node.is_audio,
        size: entry.node.size,
        has_children: entry.node.has_children,
        child_names: entry
            .children
            .into_iter()
            .map(|child| FileManagerChild {
                path: child.path.to_string_lossy().into_owned(),
                name: child.name,
                is_dir: child.is_dir,
                is_archive: child.is_archive,
                is_image: child.is_image,
                is_video: child.is_video,
                is_audio: child.is_audio,
            })
            .collect(),
    }
}
