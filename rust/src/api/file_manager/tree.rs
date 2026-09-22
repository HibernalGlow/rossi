//! 文件树面板（目录树侧栏）的 FRB 端点。
//!
//! 状态机正本在 `rossi_local_core::folder_pane`，本文件只把会话的当前目录/排序/
//! 隐藏项喂给它，并把 `PathBuf` 行投影成字符串。

use std::path::PathBuf;

use anyhow::{Error, anyhow};
use flutter_rust_bridge::frb;
use rossi_local_core::{
    FolderPaneState, FolderPaneTreeKey, folder_tree::path_eq as pane_path_eq,
    settings::SortOrder as PaneSortOrder,
};

use super::types::FileManagerTreeSnapshot;
use super::{FILE_MANAGER_PANES, FILE_MANAGER_SESSIONS, pane_inputs, project_pane};

// ── 文件树面板 ─────────────────────────────────────────────────────────────
//
// 状态机正本在 `rossi_local_core::folder_pane`（逐字搬自 mImageViewer）。这一层只做三件
// 它自己做不了的事：把会话的当前目录/排序/隐藏项喂给它、把 `PathBuf` 行投影成字符串、
// 以及在卡片关闭时回收它。树的展开状态、后台扫描与取消全在核心那边。

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
