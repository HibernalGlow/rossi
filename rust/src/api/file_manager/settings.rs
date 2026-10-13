//! 浏览设置（穿透、内部条目、视图、隐藏、筛选与排序）及卡片关闭的 FRB 端点。

use anyhow::Error;
use flutter_rust_bridge::frb;
use rossi_local_core::{
    EntryFilter, InternalItemsMode, LayoutMode, SortField, SortOrder, ViewMode,
};

use super::types::{
    FileManagerEntryFilter, FileManagerInternalItemsMode, FileManagerLayoutMode,
    FileManagerNewTabOptions, FileManagerNewTabPolicy, FileManagerSnapshot, FileManagerSortField,
    FileManagerSortOrder, FileManagerViewMode,
};
use super::{FILE_MANAGER_PANES, FILE_MANAGER_SESSIONS, snapshot_for, with_session};

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
pub async fn file_manager_set_layout_mode(
    id: u64,
    mode: FileManagerLayoutMode,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_layout_mode(match mode {
            FileManagerLayoutMode::Content => LayoutMode::Content,
            FileManagerLayoutMode::Tree => LayoutMode::Tree,
            FileManagerLayoutMode::Columns => LayoutMode::Columns,
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

/// 只更新未来页签的创建策略，不修改当前页签。
#[frb]
pub async fn file_manager_configure_new_tabs(
    id: u64,
    options: FileManagerNewTabOptions,
) -> Result<(), Error> {
    with_session(id, move |state| {
        configure_new_tab_options(state, options);
        Ok(())
    })
    .await
}

/// 创建会话和调整未来页签策略共用同一份映射。
pub(super) fn configure_new_tab_options(
    state: &mut rossi_local_core::FileManagerState,
    options: FileManagerNewTabOptions,
) {
    let mut defaults = rossi_local_core::file_manager::FileManagerSettings::default();
    defaults.view_mode = match options.view_mode {
        FileManagerViewMode::Compact => ViewMode::Compact,
        FileManagerViewMode::CoverList => ViewMode::CoverList,
        FileManagerViewMode::MosaicList => ViewMode::MosaicList,
        FileManagerViewMode::Details => ViewMode::Details,
        FileManagerViewMode::CoverGrid => ViewMode::CoverGrid,
        FileManagerViewMode::MosaicGrid => ViewMode::MosaicGrid,
    };
    defaults.layout_mode = match options.layout_mode {
        FileManagerLayoutMode::Content => LayoutMode::Content,
        FileManagerLayoutMode::Tree => LayoutMode::Tree,
        FileManagerLayoutMode::Columns => LayoutMode::Columns,
    };
    defaults.penetration_enabled = options.penetration_enabled;
    defaults.show_hidden_files = options.show_hidden_files;
    defaults.show_child_names = options.show_child_names;
    defaults.search_include_subfolders = options.search_include_subfolders;
    state.configure_new_tabs(
        match options.policy {
            FileManagerNewTabPolicy::Defaults => {
                rossi_local_core::file_manager::NewTabPolicy::Defaults
            }
            FileManagerNewTabPolicy::Recent => rossi_local_core::file_manager::NewTabPolicy::Recent,
            FileManagerNewTabPolicy::Triggering => {
                rossi_local_core::file_manager::NewTabPolicy::Triggering
            }
        },
        defaults,
    );
}

#[frb(sync)]
pub fn file_manager_close(id: u64) -> bool {
    // 先摘面板：它的 `Drop` 会取消还在跑的目录枚举线程，晚一步就白扫一轮。
    if let Ok(mut panes) = FILE_MANAGER_PANES.lock() {
        panes.remove(&id);
    }
    FILE_MANAGER_SESSIONS.remove(&id).is_some()
}
