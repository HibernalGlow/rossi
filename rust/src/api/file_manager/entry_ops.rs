//! 条目打开、归档打开与上下本导航的 FRB 端点。

use std::path::{Path, PathBuf};

use anyhow::Error;
use flutter_rust_bridge::frb;
use rossi_local_core::OpenEntryResult;

use super::types::FileManagerActionResult;
use super::{snapshot_for, with_session};

#[frb]
pub async fn file_manager_open_entry(
    id: u64,
    path: String,
    force_enter: bool,
) -> Result<FileManagerActionResult, Error> {
    with_session(id, move |state| {
        let activated = PathBuf::from(path);
        let opened_path = match state.open_entry(&activated, force_enter)? {
            OpenEntryResult::Entered(_) => None,
            OpenEntryResult::Opened(path) => Some(path.to_string_lossy().into_owned()),
        };
        let book_navigation_json = opened_path
            .as_ref()
            .map(|source| {
                rossi_local_core::book_navigation::BookNavigation::from_browser(
                    state,
                    &activated,
                    Path::new(source),
                )
                .and_then(|navigation| Ok(serde_json::to_string(&navigation)?))
            })
            .transpose()?;
        Ok(FileManagerActionResult {
            snapshot: snapshot_for(id, state)?,
            opened_path,
            book_navigation_json,
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
        let navigation = rossi_local_core::book_navigation::BookNavigation::from_browser(
            state,
            Path::new(&opened_path),
            Path::new(&opened_path),
        )?;
        Ok(FileManagerActionResult {
            snapshot: snapshot_for(id, state)?,
            opened_path: Some(opened_path),
            book_navigation_json: Some(serde_json::to_string(&navigation)?),
        })
    })
    .await
}

#[derive(Debug, Clone)]
pub struct LocalBookNavigationTarget {
    pub path: String,
    pub navigation_json: String,
}

/// 按打开时的列表与目录栈查找上下本；不依赖仍在挂载的文件管理器。
#[frb]
pub async fn local_book_adjacent(
    path: String,
    navigation_json: Option<String>,
    forward: bool,
) -> Result<Option<LocalBookNavigationTarget>, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            use rossi_local_core::book_navigation::BookNavigation;
            let source = Path::new(&path);
            let navigation = match navigation_json {
                Some(json) => serde_json::from_str::<BookNavigation>(&json)?,
                None => BookNavigation::standalone(source),
            };
            navigation
                .adjacent(source, forward)?
                .map(|next| {
                    Ok(LocalBookNavigationTarget {
                        path: next.source().to_string_lossy().into_owned(),
                        navigation_json: serde_json::to_string(&next)?,
                    })
                })
                .transpose()
        })
        .await?
}
