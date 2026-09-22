//! 递归搜索：搜索条件设置、遍历执行与取消、搜索历史。

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use anyhow::Error;
use flutter_rust_bridge::frb;
use rossi_local_core::{FileManagerEntry as CoreEntry, SettingsDb};

use super::types::FileManagerSnapshot;
use super::{FILE_MANAGER_SEARCHES, current_store, snapshot_for, with_session};

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
pub async fn file_manager_set_search_in_path(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_search_in_path(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_search_or_mode(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_search_or_mode(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_search_include_subfolders(
    id: u64,
    enabled: bool,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_search_include_subfolders(enabled);
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_set_search_max_depth(
    id: u64,
    depth: u8,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.set_search_max_depth(depth as usize);
        snapshot_for(id, state)
    })
    .await
}

/// 递归搜索的取消守卫。
///
/// 放进 `Drop` 而不是写在正常返回路径上，为的是覆盖**非正常**那条：Dart 侧
/// 丢掉这个 Future（卡片被销毁、页面切走）时，遍历还在阻塞线程上跑，没有这个
/// 守卫它会一路扫到底。正常完成时置位无害 —— 那时遍历已经结束了。
struct FileManagerSearchGuard {
    id: u64,
    cancel: Arc<AtomicBool>,
}

impl Drop for FileManagerSearchGuard {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
        // 只摘自己这颗旗子：期间用户可能又搜了一次，旗子已经换成新的了。
        FILE_MANAGER_SEARCHES.remove_if(&self.id, |_, flag| Arc::ptr_eq(flag, &self.cancel));
    }
}

/// 按当前生效的搜索条件跑一次递归搜索。
///
/// 遍历**不**在 `with_session` 里跑：那个闭包握着会话的写锁，一次整库扫描会把
/// 其它卡片动作全部堵住。所以先取一份请求值（根路径 + 设置快照），再在阻塞线程
/// 上离线遍历。代价是遍历期间用户改设置不生效 —— 那本来就该由下一次搜索回答。
#[frb]
pub async fn file_manager_search(id: u64) -> Result<FileManagerSnapshot, Error> {
    let request = with_session(id, move |state| Ok(state.search_request())).await?;
    let cancel = Arc::new(AtomicBool::new(false));
    // 新搜索直接作废上一次还在跑的那一次：同一张卡片只有最新的结果有意义。
    FILE_MANAGER_SEARCHES.insert(id, cancel.clone());
    let guard = FileManagerSearchGuard {
        id,
        cancel: cancel.clone(),
    };
    let expected = request.clone();
    let outcome = rquickjs_playground::global_handle()
        .spawn_blocking(move || rossi_local_core::file_manager::search_entries(&request, &cancel))
        .await?;
    let listing = map_search_outcome(outcome);
    drop(guard);
    with_session(id, move |state| {
        // 回声判定放在写入这一刻：遍历跑在别的线程上，期间用户可能已经改了词、
        // 切了页签或换了筛选条件。条件已经不是这一次的了就直接丢掉，让更新的那一次
        // 去写（它必然排在后面）。
        if state.search_request() == expected {
            state.set_search_listing(listing);
        }
        snapshot_for(id, state)
    })
    .await
}

/// 把当前搜索结果另存成一个页签（NeoView 的「保存搜索到页签」）。
#[frb]
pub async fn file_manager_save_search_as_tab(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.save_search_as_tab()?;
        snapshot_for(id, state)
    })
    .await
}

/// 退出搜索结果视图，回到页签自己那一层目录（不清空搜索词）。
#[frb]
pub async fn file_manager_clear_search(id: u64) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.clear_search_listing();
        snapshot_for(id, state)
    })
    .await
}

/// 请求中止本会话正在跑的搜索。没有搜索在跑时是空操作。
#[frb]
pub async fn file_manager_cancel_search(id: u64) -> Result<bool, Error> {
    let Some(flag) = FILE_MANAGER_SEARCHES.get(&id).map(|entry| entry.clone()) else {
        return Ok(false);
    };
    flag.store(true, Ordering::Relaxed);
    Ok(true)
}

/// 记一次搜索到历史里，并回给最新的列表（省得 Dart 再问一次）。
///
/// 设置库没打开时返回空列表而**不是**报错：历史是辅助信息，一次 SQLite 不可用
/// 不该让搜索框冒红。真正的搜索早已独立完成。
#[frb]
pub async fn file_manager_record_search_history(query: String) -> Result<Vec<String>, Error> {
    let trimmed = query.trim().to_owned();
    let Some(store) = current_store() else {
        return Ok(Vec::new());
    };
    if trimmed.is_empty() {
        return load_search_history(store.as_ref(), SEARCH_HISTORY_DEFAULT_LIMIT);
    }
    store
        .record_file_manager_search(&trimmed, now_secs())
        .map_err(Error::from)?;
    load_search_history(store.as_ref(), SEARCH_HISTORY_DEFAULT_LIMIT)
}

#[frb]
pub async fn file_manager_search_history(limit: u8) -> Result<Vec<String>, Error> {
    let Some(store) = current_store() else {
        return Ok(Vec::new());
    };
    load_search_history(store.as_ref(), limit.max(1))
}

#[frb]
pub async fn file_manager_clear_search_history() -> Result<u32, Error> {
    let Some(store) = current_store() else {
        return Ok(0);
    };
    Ok(store
        .clear_file_manager_search_history()
        .map_err(Error::from)? as u32)
}

const SEARCH_HISTORY_DEFAULT_LIMIT: u8 = 8;

fn load_search_history(store: &SettingsDb, limit: u8) -> Result<Vec<String>, Error> {
    Ok(store.load_file_manager_search_history(limit as u32)?)
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0)
}

/// 把核心的一次遍历结果变成页签上的搜索列表。
///
/// 命中不带子文件名投影：那需要逐条目录再读一次盘，而结果页要的是「哪些条目命中了」，
/// 不是每本的完整上下文。
fn map_search_outcome(
    outcome: rossi_local_core::file_manager::FileManagerSearchOutcome,
) -> rossi_local_core::file_manager::FileManagerSearchListing {
    rossi_local_core::file_manager::FileManagerSearchListing {
        root: outcome.root,
        query: outcome.query,
        entries: outcome
            .hits
            .into_iter()
            .map(|node| CoreEntry {
                node,
                children: Vec::new(),
            })
            .collect(),
        scanned: outcome.scanned,
        matched: outcome.matched,
        truncated: outcome.truncated,
        cancelled: outcome.cancelled,
    }
}
