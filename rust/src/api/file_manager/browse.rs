//! 会话建立、目录导航与页签操作的 FRB 端点。

use std::path::PathBuf;
use std::sync::atomic::Ordering;

use anyhow::{Error, anyhow};
use flutter_rust_bridge::frb;
use rossi_local_core::FileManagerState;

use super::types::FileManagerSnapshot;
use super::{
    FILE_MANAGER_SESSIONS, NEXT_FILE_MANAGER_ID, attached_store, hydrate_view_states_from,
    seed_home_path, snapshot_for, with_session,
};

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
