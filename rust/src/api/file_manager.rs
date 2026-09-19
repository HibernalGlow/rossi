//! 跨 UI 的本地文件管理器会话。
//!
//! 这里是 Flutter 之外的唯一状态入口：页签、导航历史、穿透策略和子文件名投影都由
//! `rossi_local_core::FileManagerState` 维护。Flutter/桌面边栏只收到不可变快照并转发
//! 用户动作，因此未来换成 Tauri、egui 或 CLI 时不需要复制一套业务状态机。
//!
//! 目录级视图状态（每个目录的视图模式与排序）的落盘也收口在这里：核心只回答
//! 「哪些目录的偏好变了」（`take_dirty_view_states`），由这一层决定什么时候写进
//! 设置库。核心因此不需要认识 SQLite，也不需要在单元测试里摆一个数据库。

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Error, anyhow};
use dashmap::DashMap;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use rossi_local_core::{
    EntryFilter, FileManagerEntry as CoreEntry, FileManagerState, FolderPaneState,
    FolderPaneTreeKey, InternalItemsMode, OpenEntryResult, SettingsDb, SortField, SortOrder,
    ViewMode, folder_label, folder_tree::path_eq as pane_path_eq,
    settings::SortOrder as PaneSortOrder,
};

use super::local::LocalRootLocation;

lazy_static! {
    static ref FILE_MANAGER_SESSIONS: DashMap<u64, FileManagerState> = DashMap::new();
    static ref NEXT_FILE_MANAGER_ID: AtomicU64 = AtomicU64::new(1);
    /// 已打开的目录视图状态库。同一进程里所有文件管理器卡片共用一个连接；
    /// 路径变了（换数据目录、测试）就重开。
    static ref FILE_MANAGER_STORE: Mutex<Option<(PathBuf, Arc<SettingsDb>)>> = Mutex::new(None);
    /// 文件树面板的状态，与页签会话共用同一个 id。
    ///
    /// 有意**不**挂在 `FileManagerState` 上：那个结构每次用户动作前都要 `clone` 一份做
    /// 事务回滚，而面板里揣着扫描线程的 `mpsc::Receiver`，既不可克隆也不可 `Sync`。
    /// 面板也不参与事务 —— 它是当前目录的一份投影，读失败顶多少几行，不该让浏览停下。
    static ref FILE_MANAGER_PANES: Mutex<HashMap<u64, FolderPaneState>> =
        Mutex::new(HashMap::new());
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerInternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerViewMode {
    Compact,
    CoverList,
    MosaicList,
    Details,
    CoverGrid,
    MosaicGrid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerSortField {
    Name,
    Type,
    Size,
    Date,
    Random,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerSortOrder {
    Ascending,
    Descending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileManagerEntryFilter {
    All,
    Folders,
    Archives,
    Images,
    Video,
    Audio,
}

#[derive(Debug, Clone)]
pub struct FileManagerTab {
    pub id: u64,
    pub title: String,
    pub path: String,
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub pinned: bool,
    pub can_close: bool,
    pub can_close_others: bool,
    pub can_close_left: bool,
    pub can_close_right: bool,
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
    pub modified_secs: i64,
    pub has_children: bool,
    /// NeoView 的「显示内部条目」投影。它不改变父目录列表，只为 UI 提供一小段
    /// 可点击的上下文提示。
    pub child_names: Vec<FileManagerChild>,
}

#[derive(Debug, Clone)]
pub struct FileManagerBreadcrumb {
    pub path: String,
    pub name: String,
    pub is_root: bool,
    pub is_current: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerDirectoryChoice {
    pub path: String,
    pub name: String,
    pub selected: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerDirectoryColumn {
    pub path: String,
    pub name: String,
    pub entries: Vec<FileManagerDirectoryChoice>,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileManagerSnapshot {
    pub session_id: u64,
    pub max_tabs: u8,
    pub can_create_tab: bool,
    pub generation: u64,
    pub active_tab_id: u64,
    pub active_path: String,
    pub can_go_up: bool,
    pub breadcrumbs: Vec<FileManagerBreadcrumb>,
    pub directory_columns_enabled: bool,
    pub directory_columns: Vec<FileManagerDirectoryColumn>,
    pub tabs: Vec<FileManagerTab>,
    pub recently_closed: Vec<FileManagerTab>,
    pub entries: Vec<FileManagerEntry>,
    pub roots: Vec<LocalRootLocation>,
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: FileManagerInternalItemsMode,
    pub max_depth: u8,
    pub view_mode: FileManagerViewMode,
    pub show_hidden_files: bool,
    pub search_query: String,
    pub entry_filter: FileManagerEntryFilter,
    pub sort_field: FileManagerSortField,
    pub sort_order: FileManagerSortOrder,
    pub directories_first: bool,
    /// 用户指定的主页；`None` 时工具栏的主页键应禁用。
    pub home_path: Option<String>,
    pub is_home: bool,
    pub can_set_home: bool,
    /// 「临时排序」：排序变更不写回当前目录的视图状态。
    pub sort_temporary: bool,
    /// 目录级排序偏好是否可用（`remember_view_state`）。
    pub can_sort_preference: bool,
    /// 「记住每个目录的视图与排序」总开关的当前值。关闭时本会话不读不写目录偏好。
    pub remember_view_state: bool,
}

#[derive(Debug, Clone)]
pub struct FileManagerActionResult {
    pub snapshot: FileManagerSnapshot,
    /// 非空时表示 UI 应该把该路径交给 Reader；浏览器自身仍停留在原目录。
    pub opened_path: Option<String>,
}

/// 文件树的一行：核心 `FolderPaneRow` 的字符串投影。
#[derive(Debug, Clone)]
pub struct FileManagerTreeRow {
    pub path: String,
    pub name: String,
    pub depth: u32,
    pub expanded: bool,
    /// 子目录正在后台枚举：这一行的箭头该转圈。
    pub loading: bool,
    /// 「有子目录，或者还没查过」。确认是空目录时 UI 才收起箭头。
    pub may_have_children: bool,
    pub is_active: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileManagerTreeSnapshot {
    pub rows: Vec<FileManagerTreeRow>,
    /// 仍有目录在枚举中。UI 据此决定要不要隔一会儿再问一次。
    pub has_pending: bool,
}

/// 把持久化的主页注入新建会话。
///
/// 主页是全局设置里的一个路径，可能指向已被删除或拔出的卷。核心的
/// `set_home_path` 只接受真实存在的目录，因此失效路径在这里被静默忽略：
/// 会话保持「未设主页」，UI 用「持久化值非空但 `snapshot.home_path` 为空」
/// 判定主页失效并提示用户重新选择，而不是把一个不存在的目录塞进导航。
fn seed_home_path(state: &mut FileManagerState, home_path: Option<PathBuf>) {
    let Some(home) = home_path else {
        return;
    };
    state.set_home_path(Some(home));
}

/// 打开（或复用）目录视图状态库。
///
/// 路径由 Dart 侧传入（`getDbPath()` 下的 `settings.db`）：Rust 不该猜 Flutter 的
/// 目录策略（Windows 便携版、Android 的 AppSupport 回退都不一样）。
fn store_for(path: &Path) -> Result<Arc<SettingsDb>, Error> {
    let mut slot = FILE_MANAGER_STORE
        .lock()
        .map_err(|_| anyhow!("目录视图状态库的锁已中毒"))?;
    if let Some((opened, db)) = slot.as_ref()
        && opened == path
    {
        return Ok(Arc::clone(db));
    }
    let db = Arc::new(SettingsDb::open(path)?);
    *slot = Some((path.to_path_buf(), Arc::clone(&db)));
    Ok(db)
}

/// 会话要用哪个设置库。没有路径或打不开时返回 `None`，调用方按「不记忆」继续。
///
/// 持久化是增量能力：设置库建不起来（目录不可写、磁盘满）不该让文件管理器打不开。
fn attached_store(db_path: Option<&Path>) -> Option<Arc<SettingsDb>> {
    let db_path = db_path?;
    match store_for(db_path) {
        Ok(db) => Some(db),
        Err(error) => {
            tracing::warn!("打开设置库失败，本次会话不记忆目录视图: {error}");
            None
        }
    }
}

fn current_store() -> Option<Arc<SettingsDb>> {
    FILE_MANAGER_STORE
        .lock()
        .ok()
        .and_then(|slot| slot.as_ref().map(|(_, db)| Arc::clone(db)))
}

/// 把盘上的目录视图状态装进会话。当前目录若在表里，会立刻套用它。
fn hydrate_view_states_from(store: Option<&SettingsDb>, state: &mut FileManagerState) {
    let Some(store) = store else {
        return;
    };
    match store.load_all_file_manager_view_states() {
        Ok(states) => state.hydrate_view_states(states),
        Err(error) => tracing::warn!("读取目录视图状态失败，本次按默认视图打开: {error}"),
    }
}

/// 把这一步操作产生的目录偏好写进设置库。
///
/// 每次用户动作之后落盘（而不是攒到退出时）：文件浏览器没有稳定的「帧循环」可以
/// 挂防抖定时器，而这些写都是离散的用户动作触发的，一次最多一行。mImageViewer
/// 那边需要 500ms 防抖是因为它的视图状态会被逐帧的高频变更反复写。
fn persist_dirty_view_states_into(store: Option<&SettingsDb>, state: &mut FileManagerState) {
    let Some(store) = store else {
        return;
    };
    for (key, view_state) in state.take_dirty_view_states() {
        if let Err(error) = store.set_file_manager_view_state(&key, &view_state) {
            // 不因为落盘失败回滚用户刚做的切换：内存正本已经生效，
            // 同一目录的下一次变更会重试。
            tracing::warn!("写入选项目录视图状态失败 key={key}: {error}");
        }
    }
}

#[frb]
pub async fn file_manager_create(
    initial_path: Option<String>,
    home_path: Option<String>,
    settings_db_path: Option<String>,
    remember_view_state: bool,
) -> Result<u64, Error> {
    let path = initial_path.map(PathBuf::from);
    let home = home_path.map(PathBuf::from);
    let db_path = settings_db_path.map(PathBuf::from);
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let mut state = FileManagerState::new(path)?;
            state.set_remember_view_state(remember_view_state);
            seed_home_path(&mut state, home);
            let store = attached_store(db_path.as_deref());
            hydrate_view_states_from(store.as_deref(), &mut state);
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
pub async fn file_manager_navigate_text(
    id: u64,
    text: String,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.navigate_text(&text)?;
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_directory_columns(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_directory_columns_enabled(enabled);
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

/// 跳回用户指定的主页。主页就是普通目录，因此同样进入页签的后退栈。
#[frb]
pub async fn file_manager_go_home(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.go_home();
        snapshot_for(id, state)
    })
    .await
}

/// 写入主页（`None` 清除）。核心只接受存在的目录，非法路径保持原值。
#[frb]
pub async fn file_manager_set_home_path(
    id: u64,
    path: Option<String>,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_home_path(path.map(PathBuf::from));
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
pub async fn file_manager_duplicate_tab(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.duplicate_tab(tab_id)?;
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_toggle_tab_pinned(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.toggle_tab_pinned(tab_id) {
            return Err(anyhow!("页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_close_other_tabs(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.close_other_tabs(tab_id) {
            return Err(anyhow!("没有可关闭的其它页签，或页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_close_tabs_left(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.close_tabs_left(tab_id) {
            return Err(anyhow!("左侧没有可关闭的页签，或页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_close_tabs_right(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        if !state.close_tabs_right(tab_id) {
            return Err(anyhow!("右侧没有可关闭的页签，或页签不存在: {tab_id}"));
        }
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_reopen_closed_tab(
    id: u64,
    tab_id: u64,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.reopen_closed_tab(tab_id)?;
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
            FileManagerViewMode::Compact => ViewMode::Compact,
            FileManagerViewMode::CoverList => ViewMode::CoverList,
            FileManagerViewMode::MosaicList => ViewMode::MosaicList,
            FileManagerViewMode::Details => ViewMode::Details,
            FileManagerViewMode::CoverGrid => ViewMode::CoverGrid,
            FileManagerViewMode::MosaicGrid => ViewMode::MosaicGrid,
        });
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_show_hidden_files(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_show_hidden_files(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_search_query(
    id: u64,
    query: String,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_search_query(query);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_entry_filter(
    id: u64,
    filter: FileManagerEntryFilter,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_entry_filter(match filter {
            FileManagerEntryFilter::All => EntryFilter::All,
            FileManagerEntryFilter::Folders => EntryFilter::Folders,
            FileManagerEntryFilter::Archives => EntryFilter::Archives,
            FileManagerEntryFilter::Images => EntryFilter::Images,
            FileManagerEntryFilter::Video => EntryFilter::Video,
            FileManagerEntryFilter::Audio => EntryFilter::Audio,
        });
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_sort(
    id: u64,
    field: FileManagerSortField,
    order: FileManagerSortOrder,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_sort(
            match field {
                FileManagerSortField::Name => SortField::Name,
                FileManagerSortField::Type => SortField::Type,
                FileManagerSortField::Size => SortField::Size,
                FileManagerSortField::Date => SortField::Date,
                FileManagerSortField::Random => SortField::Random,
            },
            match order {
                FileManagerSortOrder::Ascending => SortOrder::Ascending,
                FileManagerSortOrder::Descending => SortOrder::Descending,
            },
        );
        snapshot_for(id, state)
    })
    .await
}

/// 工具栏的「锁定当前目录排序／取消临时排序」。
#[frb]
pub async fn file_manager_set_sort_temporary(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_sort_temporary(enabled);
        snapshot_for(id, state)
    })
    .await
}

/// 「记住每个目录的视图与排序」总开关（对应全局设置里那一项）。
///
/// 置为 false 之后本会话既不读也不写目录偏好；已经存下来的行**不删**，
/// 所以重新打开开关就能恢复，与 mImageViewer 的 `remember_favorite_view_state` 同口径。
#[frb]
pub async fn file_manager_set_remember_view_state(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_remember_view_state(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_directories_first(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_directories_first(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb(sync)]
pub fn file_manager_close(id: u64) -> bool {
    // 先摘面板：它的 `Drop` 会取消还在跑的目录枚举线程，晚一步就白扫一轮。
    if let Ok(mut panes) = FILE_MANAGER_PANES.lock() {
        panes.remove(&id);
    }
    FILE_MANAGER_SESSIONS.remove(&id).is_some()
}

// ── 文件树面板 ─────────────────────────────────────────────────────────────
//
// 状态机正本在 `rossi_local_core::folder_pane`（逐字搬自 mImageViewer）。这一层只做三件
// 它自己做不了的事：把会话的当前目录/排序/隐藏项喂给它、把 `PathBuf` 行投影成字符串、
// 以及在卡片关闭时回收它。树的展开状态、后台扫描与取消全在核心那边。

/// 页签的排序方向 → 面板的排序方式。面板只按名字排，因此升降序就够。
fn pane_sort_order(order: SortOrder) -> PaneSortOrder {
    match order {
        SortOrder::Ascending => PaneSortOrder::NameAsc,
        SortOrder::Descending => PaneSortOrder::NameDesc,
    }
}

/// 面板这一次要对齐到哪个目录、按什么排、要不要隐藏项。
fn pane_inputs(state: &FileManagerState) -> (PathBuf, PaneSortOrder, bool) {
    let settings = state.settings();
    (
        state.active_path().to_path_buf(),
        pane_sort_order(settings.sort_order),
        settings.show_hidden_files,
    )
}

/// 在阻塞线程上操作某个会话的面板。
///
/// 每次调用都先 `sync_to_active` 再取行：面板原本按帧驱动（egui 每帧调一次），
/// 这里没有帧循环，于是把「对齐当前目录 + 收一次后台扫描结果」并进每个用户动作里。
/// `sync_to_active` 只在当前目录、排序或隐藏项策略真的变了之后才重建节点，没变时
/// 只是一次带 1.5s 节流的盘符刷新。
async fn with_pane<R, F>(id: u64, operation: F) -> Result<R, Error>
where
    R: Send + 'static,
    F: FnOnce(&mut FolderPaneState, PaneSortOrder) -> Result<R, Error> + Send + 'static,
{
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            // 先读完会话再放掉引用：面板锁和 DashMap 分片锁同时握着就成了锁序问题。
            let (active, sort_order, show_hidden) = {
                let state = FILE_MANAGER_SESSIONS
                    .get(&id)
                    .ok_or_else(|| anyhow!("文件管理器会话不存在或已关闭: id={id}"))?;
                pane_inputs(&state)
            };
            let mut panes = FILE_MANAGER_PANES
                .lock()
                .map_err(|_| anyhow!("文件树面板的锁已中毒"))?;
            let pane = panes.entry(id).or_default();
            pane.sync_to_active(Some(active.as_path()), sort_order, show_hidden);
            pane.poll_pending();
            operation(pane, sort_order)
        })
        .await?
}

fn project_pane(pane: &FolderPaneState) -> FileManagerTreeSnapshot {
    FileManagerTreeSnapshot {
        rows: pane
            .visible_rows()
            .into_iter()
            .map(|row| FileManagerTreeRow {
                path: row.path.to_string_lossy().into_owned(),
                name: folder_label(&row.path),
                depth: row.depth as u32,
                expanded: row.expanded,
                loading: row.loading,
                may_have_children: row.has_children_or_unknown,
                is_active: row.is_active,
                error: row.error,
            })
            .collect(),
        has_pending: pane.has_pending(),
    }
}

#[frb]
pub async fn file_manager_tree_snapshot(id: u64) -> Result<FileManagerTreeSnapshot, Error> {
    with_pane(id, |pane, _| Ok(project_pane(pane))).await
}

/// 展开/收起某一行。核心没有「按路径直接改展开态」的入口，于是把游标挪过去、
/// 再走键盘的左/右键 —— 与用户用方向键操作时是同一条路径，展开状态（`user_expanded`
/// / `user_collapsed`）的记账因此只有一套。
#[frb]
pub async fn file_manager_tree_toggle(
    id: u64,
    path: String,
) -> Result<FileManagerTreeSnapshot, Error> {
    with_pane(id, move |pane, sort_order| {
        let target = PathBuf::from(path);
        pane.set_cursor(target.clone());
        let expanded = pane
            .visible_rows()
            .iter()
            .any(|row| pane_path_eq(&row.path, &target) && row.expanded);
        pane.handle_tree_key(
            if expanded {
                FolderPaneTreeKey::Left
            } else {
                FolderPaneTreeKey::Right
            },
            sort_order,
        );
        Ok(project_pane(pane))
    })
    .await
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
            // 更新和快照作为一次事务：目录读取失败时不提交半完成的导航或页签操作。
            apply_session_operation(&mut state, operation)
        })
        .await?
}

fn apply_session_operation<R>(
    state: &mut FileManagerState,
    operation: impl FnOnce(&mut FileManagerState) -> Result<R, Error>,
) -> Result<R, Error> {
    let mut candidate = state.clone();
    let result = operation(&mut candidate)?;
    *state = candidate;
    // 快照成功 ⇒ 这一步的目录偏好才算数：失败的操作不该留下半套视图状态。
    persist_dirty_view_states_into(current_store().as_deref(), state);
    Ok(result)
}

fn snapshot_for(id: u64, state: &mut FileManagerState) -> Result<FileManagerSnapshot, Error> {
    let entries = state.entries()?.into_iter().map(map_entry).collect();
    let map_tab = |tab: &rossi_local_core::FileManagerTab| FileManagerTab {
        id: tab.id,
        title: tab.title(),
        path: tab.path.to_string_lossy().into_owned(),
        can_go_back: tab.can_go_back(),
        can_go_forward: tab.can_go_forward(),
        pinned: tab.pinned,
        can_close: state.can_close_tab(tab.id),
        can_close_others: state.can_close_other_tabs(tab.id),
        can_close_left: state.can_close_tabs_on_side(tab.id, true),
        can_close_right: state.can_close_tabs_on_side(tab.id, false),
    };
    let tabs = state.tabs().iter().map(map_tab).collect();
    let recently_closed = state.recently_closed().iter().map(map_tab).collect();
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
        max_tabs: rossi_local_core::MAX_FILE_MANAGER_TABS as u8,
        can_create_tab: state.can_create_tab(),
        generation: state.generation(),
        active_tab_id: state.active_tab_id(),
        active_path: state.active_path().to_string_lossy().into_owned(),
        can_go_up: state.can_go_up(),
        breadcrumbs: state
            .breadcrumbs()
            .into_iter()
            .map(|part| FileManagerBreadcrumb {
                path: part.path.to_string_lossy().into_owned(),
                name: part.name,
                is_root: part.is_root,
                is_current: part.is_current,
            })
            .collect(),
        directory_columns_enabled: settings.directory_columns_enabled,
        directory_columns: state
            .directory_columns()
            .into_iter()
            .map(|column| FileManagerDirectoryColumn {
                path: column.path.to_string_lossy().into_owned(),
                name: column.name,
                error: column.error,
                entries: column
                    .entries
                    .into_iter()
                    .map(|entry| FileManagerDirectoryChoice {
                        path: entry.path.to_string_lossy().into_owned(),
                        name: entry.name,
                        selected: entry.selected,
                    })
                    .collect(),
            })
            .collect(),
        tabs,
        recently_closed,
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
            ViewMode::Compact => FileManagerViewMode::Compact,
            ViewMode::CoverList => FileManagerViewMode::CoverList,
            ViewMode::MosaicList => FileManagerViewMode::MosaicList,
            ViewMode::Details => FileManagerViewMode::Details,
            ViewMode::CoverGrid => FileManagerViewMode::CoverGrid,
            ViewMode::MosaicGrid => FileManagerViewMode::MosaicGrid,
        },
        show_hidden_files: settings.show_hidden_files,
        search_query: settings.search_query.clone(),
        entry_filter: match settings.entry_filter {
            EntryFilter::All => FileManagerEntryFilter::All,
            EntryFilter::Folders => FileManagerEntryFilter::Folders,
            EntryFilter::Archives => FileManagerEntryFilter::Archives,
            EntryFilter::Images => FileManagerEntryFilter::Images,
            EntryFilter::Video => FileManagerEntryFilter::Video,
            EntryFilter::Audio => FileManagerEntryFilter::Audio,
        },
        sort_field: match settings.sort_field {
            SortField::Name => FileManagerSortField::Name,
            SortField::Type => FileManagerSortField::Type,
            SortField::Size => FileManagerSortField::Size,
            SortField::Date => FileManagerSortField::Date,
            SortField::Random => FileManagerSortField::Random,
        },
        sort_order: match settings.sort_order {
            SortOrder::Ascending => FileManagerSortOrder::Ascending,
            SortOrder::Descending => FileManagerSortOrder::Descending,
        },
        directories_first: settings.directories_first,
        home_path: state
            .home_path()
            .map(|path| path.to_string_lossy().into_owned()),
        is_home: state.is_home(),
        can_set_home: state.can_set_home(),
        sort_temporary: state.sort_temporary(),
        can_sort_preference: state.can_sort_preference(),
        remember_view_state: state.remember_view_state(),
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
        modified_secs: entry.node.modified_secs,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_projects_home_pad_sort_lock_and_new_sort_fields() {
        let root = tempfile::tempdir().unwrap();
        let home = root.path().join("home");
        std::fs::create_dir(&home).unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();

        // 未设主页：主页键不可用，也不允许「设为主页」写成空操作。
        let snapshot = snapshot_for(9, &mut state).unwrap();
        assert_eq!(snapshot.home_path, None);
        assert!(!snapshot.is_home);
        assert!(snapshot.can_set_home);
        assert!(!snapshot.sort_temporary);
        assert!(snapshot.can_sort_preference);

        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.set_home_path(Some(home.clone()));
            candidate.set_sort(SortField::Date, SortOrder::Descending);
            candidate.set_sort_temporary(true);
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert_eq!(
            snapshot.home_path.as_deref(),
            Some(home.to_string_lossy().as_ref())
        );
        assert!(!snapshot.is_home);
        assert!(snapshot.can_set_home);
        assert_eq!(snapshot.sort_field, FileManagerSortField::Date);
        assert_eq!(snapshot.sort_order, FileManagerSortOrder::Descending);
        assert!(snapshot.sort_temporary);

        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.go_home();
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert!(snapshot.is_home);
        assert!(!snapshot.can_set_home);
        assert_eq!(snapshot.active_path, home.to_string_lossy());
        assert!(snapshot.tabs[0].can_go_back);

        // 随机排序经快照往返后仍是 Random，不会被悄悄降级成名称序。
        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.set_sort_temporary(false);
            candidate.set_sort(SortField::Random, SortOrder::Ascending);
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert_eq!(snapshot.sort_field, FileManagerSortField::Random);
        assert!(!snapshot.sort_temporary);
        assert!(!state.settings().sort_temporary);
    }

    #[test]
    fn set_home_path_rejects_missing_directories_and_clear_is_a_noop_on_empty() {
        let root = tempfile::tempdir().unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        let generation = state.generation();
        assert!(!state.set_home_path(Some(root.path().join("missing"))));
        assert!(!state.set_home_path(None));
        assert_eq!(state.generation(), generation);
        assert_eq!(snapshot_for(9, &mut state).unwrap().home_path, None);

        assert!(state.set_home_path(Some(root.path().to_path_buf())));
        assert_eq!(
            snapshot_for(9, &mut state).unwrap().home_path.as_deref(),
            Some(root.path().to_string_lossy().as_ref())
        );
        assert!(state.set_home_path(None));
        assert_eq!(snapshot_for(9, &mut state).unwrap().home_path, None);
    }

    #[test]
    fn directory_view_state_survives_a_new_session_through_the_settings_db() {
        let root = tempfile::tempdir().unwrap();
        let books = root.path().join("books");
        let other = root.path().join("other");
        std::fs::create_dir(&books).unwrap();
        std::fs::create_dir(&other).unwrap();
        let db = SettingsDb::open_in_memory().unwrap();

        // 第一个会话：在 books 里切封面网格、只看图片、显示隐藏项。
        let mut first = FileManagerState::new(Some(books.clone())).unwrap();
        persist_dirty_view_states_into(Some(&db), &mut first);
        assert!(
            db.load_all_file_manager_view_states().unwrap().is_empty(),
            "新建会话本身不该往库里写任何东西"
        );

        apply_session_operation(&mut first, |candidate| {
            candidate.set_view_mode(ViewMode::CoverGrid);
            candidate.set_entry_filter(EntryFilter::Images);
            candidate.set_show_hidden_files(true);
            Ok(())
        })
        .unwrap();
        // 生产路径由 `apply_session_operation` 自动落盘（这里没有安装进程级设置库），
        // 所以显式落一次，验的是同一套「取脏 → 写库」契约。
        persist_dirty_view_states_into(Some(&db), &mut first);

        // 第二个会话（模拟重启）：起手是默认视图，hydrate 之后必须还原。
        let mut second = FileManagerState::new(Some(books.clone())).unwrap();
        assert_eq!(second.settings().view_mode, ViewMode::Compact);
        hydrate_view_states_from(Some(&db), &mut second);
        assert_eq!(second.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(second.settings().entry_filter, EntryFilter::Images);
        assert!(second.settings().show_hidden_files);

        // 没有记忆的目录仍按默认值打开，不会被 books 的偏好串味。
        second.navigate(&other).unwrap();
        assert_eq!(second.settings().view_mode, ViewMode::Compact);
        assert_eq!(second.settings().entry_filter, EntryFilter::All);
    }

    #[test]
    fn remember_view_state_off_browses_normally_without_recording() {
        let root = tempfile::tempdir().unwrap();
        let db = SettingsDb::open_in_memory().unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();

        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.set_remember_view_state(false);
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert!(!snapshot.remember_view_state);
        // 排序偏好开关跟着关：工具栏的「临时排序」项会因此禁用。
        assert!(!snapshot.can_sort_preference);

        // 视图照样生效，只是不再产生目录偏好。
        state.set_view_mode(ViewMode::CoverGrid);
        state.set_sort(SortField::Size, SortOrder::Descending);
        persist_dirty_view_states_into(Some(&db), &mut state);
        assert!(db.load_all_file_manager_view_states().unwrap().is_empty());
        assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(state.settings().sort_field, SortField::Size);
    }

    #[test]
    fn stores_are_reused_per_path_and_reopened_when_the_path_changes() {
        let dir = tempfile::tempdir().unwrap();
        let first_path = dir.path().join("first.db");
        let second_path = dir.path().join("second.db");

        let first = store_for(&first_path).unwrap();
        assert!(Arc::ptr_eq(&first, &store_for(&first_path).unwrap()));
        let second = store_for(&second_path).unwrap();
        assert!(!Arc::ptr_eq(&first, &second));
        assert!(current_store().is_some());

        // 别把进程级句柄留给后面的测试。
        *FILE_MANAGER_STORE.lock().unwrap() = None;
        assert!(current_store().is_none());
    }

    #[test]
    fn seed_home_path_ignores_stale_persisted_paths() {
        let root = tempfile::tempdir().unwrap();
        let home = root.path().join("home");
        std::fs::create_dir(&home).unwrap();

        // 未持久化主页：会话保持「未设主页」，主页键仍然可点。
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        seed_home_path(&mut state, None);
        assert_eq!(snapshot_for(9, &mut state).unwrap().home_path, None);

        // 持久化路径已失效（目录被删）：同样保持未设，而不是写入一个不存在的目录。
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        seed_home_path(&mut state, Some(root.path().join("gone")));
        let snapshot = snapshot_for(9, &mut state).unwrap();
        assert_eq!(snapshot.home_path, None);
        assert!(snapshot.can_set_home);
        assert!(!state.go_home());

        // 有效路径：注入后主页键可用，且跳转进入后退栈。
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        seed_home_path(&mut state, Some(home.clone()));
        let snapshot = snapshot_for(9, &mut state).unwrap();
        assert_eq!(
            snapshot.home_path.as_deref(),
            Some(home.to_string_lossy().as_ref())
        );
        assert!(!snapshot.is_home);
        assert!(snapshot.can_set_home);
        assert!(state.go_home());
        let snapshot = snapshot_for(9, &mut state).unwrap();
        assert!(snapshot.is_home);
        assert!(!snapshot.can_set_home);
    }

    #[test]
    fn failed_snapshot_rolls_back_tab_activation() {
        let root = tempfile::tempdir().unwrap();
        let gone = root.path().join("gone");
        std::fs::create_dir(&gone).unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        let stale_tab = state.new_tab(Some(gone.clone())).unwrap();
        state.activate_tab(1);
        std::fs::remove_dir(&gone).unwrap();
        let generation = state.generation();
        let result = apply_session_operation(&mut state, |candidate| {
            candidate.activate_tab(stale_tab);
            snapshot_for(9, candidate)
        });
        assert!(result.is_err());
        assert_eq!(state.active_tab_id(), 1);
        assert_eq!(state.generation(), generation);
        assert_eq!(snapshot_for(9, &mut state).unwrap().tabs.len(), 2);
    }

    #[test]
    fn snapshot_exposes_core_capabilities_and_commits_sort_settings() {
        let root = tempfile::tempdir().unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.set_sort(SortField::Size, SortOrder::Descending);
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert_eq!(snapshot.sort_field, FileManagerSortField::Size);
        assert_eq!(snapshot.sort_order, FileManagerSortOrder::Descending);
        assert_eq!(state.settings().sort_field, SortField::Size);
        assert_eq!(
            snapshot.max_tabs as usize,
            rossi_local_core::MAX_FILE_MANAGER_TABS
        );
        assert!(snapshot.can_create_tab);
        assert!(!snapshot.tabs[0].can_close);
        assert!(!snapshot.tabs[0].can_close_others);
        assert!(!snapshot.tabs[0].can_close_left);
        assert!(!snapshot.tabs[0].can_close_right);
    }

    #[test]
    fn snapshot_projects_navigation_and_failed_edit_does_not_commit() {
        let root = tempfile::tempdir().unwrap();
        let child = root.path().join("child");
        std::fs::create_dir(&child).unwrap();
        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        let snapshot = apply_session_operation(&mut state, |candidate| {
            candidate.set_directory_columns_enabled(true);
            candidate.navigate_text("child")?;
            snapshot_for(9, candidate)
        })
        .unwrap();
        assert_eq!(
            snapshot.breadcrumbs.last().unwrap().path,
            child.to_string_lossy()
        );
        assert!(snapshot.breadcrumbs.last().unwrap().is_current);
        assert!(snapshot.can_go_up);
        assert!(snapshot.directory_columns_enabled);
        assert!(snapshot.directory_columns.iter().any(|column| {
            column
                .entries
                .iter()
                .any(|entry| entry.name == "child" && entry.selected)
        }));
        let generation = snapshot.generation;
        assert!(
            apply_session_operation(&mut state, |candidate| {
                candidate.navigate_text("does not exist")?;
                snapshot_for(9, candidate)
            })
            .is_err()
        );
        assert_eq!(state.generation(), generation);
        assert_eq!(state.active_path(), child);
        assert_eq!(state.active_tab().back.len(), 1);
    }

    #[test]
    fn pane_follows_the_session_directory_and_projects_only_directories() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir(root.path().join("series")).unwrap();
        std::fs::write(root.path().join("page.png"), b"x").unwrap();

        let mut state = FileManagerState::new(Some(root.path().into())).unwrap();
        // tempdir 的名字是 `.tmpXXXX`，按面板的隐藏项策略它根本不该出现在树里。
        // 这里显式允许隐藏项，既让祖先链连得到，也顺带验一遍开关真的传下去了。
        state.set_show_hidden_files(true);
        // 一切以会话给出的当前目录为准：核心可能把 tempdir 的 `/var` 规范化成
        // `/private/var`，拿原始路径去比会假失败。
        let (active, sort_order, show_hidden) = pane_inputs(&state);
        assert_eq!(
            sort_order,
            PaneSortOrder::NameAsc,
            "页签的升序要映射成面板的名字升序"
        );
        assert!(show_hidden);

        let mut pane = FolderPaneState::default();
        // 面板只自动展开到当前目录的**祖先**，当前目录自己得点开。
        pane.sync_to_active(Some(active.as_path()), sort_order, show_hidden);
        pane.set_cursor(active.clone());
        pane.handle_tree_key(FolderPaneTreeKey::Right, sort_order);

        // 生产路径上「收一轮后台扫描」发生在下一次 `with_pane` 里；测试自己跑到静。
        let mut rows = project_pane(&pane);
        for _ in 0..200 {
            if !rows.has_pending {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
            pane.poll_pending();
            rows = project_pane(&pane);
        }
        assert!(!rows.has_pending, "目录枚举没能在 2s 内收敛");

        let depth_of = |path: &Path| -> Option<u32> {
            let key = path.to_string_lossy();
            rows.rows.iter().find(|row| row.path == *key).map(|row| row.depth)
        };
        let active_row = rows
            .rows
            .iter()
            .find(|row| row.path == active.to_string_lossy())
            .expect("当前目录应该出现在树里");
        assert!(active_row.is_active, "当前目录那一行要标成激活");
        assert!(active_row.expanded, "点开的目录该展开在自己的行下面");
        assert_eq!(
            depth_of(&active.join("series")),
            Some(active_row.depth + 1),
            "子目录的深度由面板给，Dart 不再自己数"
        );
        assert_eq!(
            depth_of(&active.join("page.png")),
            None,
            "树只放目录，不放文件"
        );
    }
}
