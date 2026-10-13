//! 递归搜索：搜索条件设置、遍历执行与取消、搜索历史。

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use anyhow::Error;
use flutter_rust_bridge::frb;
use rossi_local_core::SettingsDb;

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

/// 一次在跑的递归遍历的把手。
///
/// `cancel` 管「停」：取消、以及新搜索让旧的停下。`scanned` 是给界面看的实时读数
/// （慢盘上一次整库遍历要几十秒，没有这个数就只能给用户一个不动的转圈）。两者放进同一条
/// 记录，是为了让「读数只属于当前那一次遍历」在结构上成立：旧把手被换掉之后，
/// 界面再问也只会问到新那一次的数。
pub(crate) struct FileManagerSearchHandle {
    pub(crate) cancel: Arc<AtomicBool>,
    pub(crate) scanned: Arc<AtomicUsize>,
}

impl FileManagerSearchHandle {
    fn new() -> Self {
        Self {
            cancel: Arc::new(AtomicBool::new(false)),
            scanned: Arc::new(AtomicUsize::new(0)),
        }
    }
}

/// 递归搜索的取消守卫。
///
/// 放进 `Drop` 而不是写在正常返回路径上，为的是覆盖**非正常**那条：Dart 侧
/// 丢掉这个 Future（卡片被销毁、页面切走）时，遍历还在阻塞线程上跑，没有这个
/// 守卫它会一路扫到底。正常完成时置位无害 —— 那时遍历已经结束了。
struct FileManagerSearchGuard {
    id: u64,
    handle: Arc<FileManagerSearchHandle>,
}

impl Drop for FileManagerSearchGuard {
    fn drop(&mut self) {
        self.handle.cancel.store(true, Ordering::Relaxed);
        // 只摘自己那一份：期间用户可能又搜了一次，把手已经换成新的了。
        FILE_MANAGER_SEARCHES.remove_if(&self.id, |_, handle| Arc::ptr_eq(handle, &self.handle));
    }
}

/// 按当前生效的搜索条件跑一次递归搜索。
///
/// 遍历**不**在 `with_session` 里跑：那个闭包握着会话的写锁，一次整库扫描会把
/// 其它卡片动作全部堵住。所以先取一份请求值（根路径 + 设置快照），再在阻塞线程
/// 上离线遍历。代价是遍历期间用户改设置不生效 —— 那本来就该由下一次搜索回答。
#[frb]
pub async fn file_manager_search(id: u64) -> Result<FileManagerSnapshot, Error> {
    // 先看上一批命中能不能就地回答这次的查询：用户只是接着打字时不必再扫一遍盘
    // （整库遍历在外挂盘上实测 5–12 秒，而搜索框每停一下就发一次请求）。
    let request = with_session(id, move |state| {
        if state.try_refine_search_listing() {
            Ok(None)
        } else {
            Ok(Some((state.active_tab_id(), state.search_request())))
        }
    })
    .await?;
    let Some((tab_id, request)) = request else {
        // 捷径成立：还在跑的那一次遍历就该停下，它的结果已经被这批命中取代了。
        cancel_registered_search(id);
        return with_session(id, move |state| snapshot_for(id, state)).await;
    };
    let handle = begin_search(id);
    let guard = FileManagerSearchGuard {
        id,
        handle: handle.clone(),
    };
    let expected = request.clone();
    let outcome = rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            rossi_local_core::file_manager::search_entries_with_progress(
                &request,
                &handle.cancel,
                &handle.scanned,
            )
        })
        .await?;
    let listing = outcome.into_listing();
    drop(guard);
    with_session(id, move |state| {
        // 回声判定放在写入这一刻：遍历跑在别的线程上，期间用户可能已经改了词、
        // 切了页签或换了筛选条件。条件已经不是这一次的了就直接丢掉，让更新的那一次
        // 去写（它必然排在后面）。
        let mut current = state.search_request();
        // 布局、条目样式与旧辅助面板开关不参与搜索范围；遍历期间切换这些不丢结果。
        current.settings.layout_mode = expected.settings.layout_mode;
        current.settings.view_mode = expected.settings.view_mode;
        current.settings.directory_columns_enabled = expected.settings.directory_columns_enabled;
        if state.active_tab_id() == tab_id && current == expected {
            state.set_search_listing(listing);
        }
        snapshot_for(id, state)
    })
    .await
}

/// 回车搜索：先原子创建独立页签，保留源页签的目录与布局。
#[frb]
pub async fn file_manager_search_in_new_tab(
    id: u64,
    query: String,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.search_in_new_tab(query)?;
        snapshot_for(id, state)
    })
    .await
}

#[frb]
pub async fn file_manager_select_search_directory(
    id: u64,
    path: String,
) -> Result<FileManagerSnapshot, Error> {
    with_session(id, move |state| {
        state.select_search_directory(PathBuf::from(path))?;
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

/// 登记本次遍历的把手，并把**上一次**那一次真的停下来，返回新的把手。
///
/// 只把登记项换掉是不够的：旧遍历手里是自己那份 `Arc`，登记项被换掉并不影响它，于是它会
/// 一路扫到底，结果再被下面的回声判定丢掉 —— 白烧一遍磁盘，还把同一块盘的行进顺序搅乱。
fn begin_search(id: u64) -> Arc<FileManagerSearchHandle> {
    let handle = Arc::new(FileManagerSearchHandle::new());
    if let Some(previous) = FILE_MANAGER_SEARCHES.insert(id, handle.clone()) {
        previous.cancel.store(true, Ordering::Relaxed);
    }
    handle
}

/// 中止当前登记的那一次遍历。没有搜索在跑时返回 `false`。
fn cancel_registered_search(id: u64) -> bool {
    let Some(handle) = FILE_MANAGER_SEARCHES.get(&id).map(|entry| entry.clone()) else {
        return false;
    };
    handle.cancel.store(true, Ordering::Relaxed);
    true
}

/// 当前那一次遍历已经检视过多少条。没有搜索在跑时是 0。
fn registered_progress(id: u64) -> u32 {
    FILE_MANAGER_SEARCHES
        .get(&id)
        .map(|handle| handle.scanned.load(Ordering::Relaxed) as u32)
        .unwrap_or(0)
}

/// 本会话正在跑的那一次遍历的进度读数（已检视的条目数）。
///
/// 纯读数，不参与任何判决：结果仍由 `file_manager_search` 的返回值交回。界面在遍历
/// 期间每隔几百毫秒问它一次 —— 慢盘上一次整库遍历要几十秒，一个不动的转圈会让人
/// 以为搜索坏了。
#[frb]
pub async fn file_manager_search_progress(id: u64) -> Result<u32, Error> {
    Ok(registered_progress(id))
}

/// 请求中止本会话正在跑的搜索。没有搜索在跑时是空操作。
#[frb]
pub async fn file_manager_cancel_search(id: u64) -> Result<bool, Error> {
    Ok(cancel_registered_search(id))
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

#[cfg(test)]
mod tests {
    use super::*;

    /// 新搜索必须让上一次那一次遍历停下来 —— 换掉登记项不等于取消。
    #[test]
    fn a_new_search_cancels_the_previous_traversal() {
        let id = u64::MAX - 1;
        FILE_MANAGER_SEARCHES.remove(&id);

        let first = begin_search(id);
        assert!(
            !first.cancel.load(Ordering::Relaxed),
            "第一次登记不该动自己"
        );

        let second = begin_search(id);
        assert!(
            first.cancel.load(Ordering::Relaxed),
            "新搜索必须把上一次那一次停下"
        );
        assert!(!second.cancel.load(Ordering::Relaxed), "本次不许被自己取消");

        // 进度读数只属于**当前**那一次：旧把手被换掉之后，它的计数不再是这个会话的答案。
        first.scanned.store(41, Ordering::Relaxed);
        second.scanned.store(7, Ordering::Relaxed);
        assert_eq!(registered_progress(id), 7);
        // 中止不改读数：数由遍历自己写，界面读到的就是它真正扫过的量。
        assert!(cancel_registered_search(id));
        assert!(second.cancel.load(Ordering::Relaxed));
        assert_eq!(registered_progress(id), 7);

        // 摘干净，别把把手留给同进程里的其它测试。
        FILE_MANAGER_SEARCHES.remove(&id);
        assert!(
            !cancel_registered_search(id),
            "没有搜索在跑时必须报「没中止任何东西」"
        );
        assert_eq!(registered_progress(id), 0, "没有搜索在跑时读数是 0");
    }
}
