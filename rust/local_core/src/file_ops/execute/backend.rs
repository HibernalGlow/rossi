//! 平台后端的收口点：回收站这一件事没法用 `std::fs` 表达。
//!
//! 拆分自 `execute.rs` 的「平台后端」段（原文件名一度叫 `trash`，与 crate 同名，
//! 见 [`SystemTrashBackend`] 上的说明）。

use super::*;

// ─────────────────────────────────────────────────────────────────────────────
// 平台后端
// ─────────────────────────────────────────────────────────────────────────────

/// 回收站后端。
///
/// 抽成 trait 有两个理由，都不是为了「可测试」来凑的：
/// 1. 回收站是**唯一不能靠 `std::fs` 表达的**动作（macOS 走 `NSFileManager`
///    / Finder、Windows 走 `IFileOperation`、Linux 走 Freedesktop 规范），
///    因此它是平台差异的收口点；
/// 2. 它的可撤销性是运行时能力（见模块注释），需要能问。
pub trait TrashBackend: Send + Sync {
    /// 把一项移进回收站。
    fn trash(&self, path: &Path) -> FileOpResult<TrashItemReceipt>;

    /// 这个平台上能不能程序化恢复。macOS 为 `false`。
    fn supports_restore(&self) -> bool {
        false
    }

    /// 恢复一项。`supports_restore()` 为假时不该被调用。
    fn restore(&self, item: &TrashItemReceipt) -> FileOpResult<()> {
        let _ = item;
        Err(FileOpError::unsupported("这个平台上没有程序化的回收站恢复"))
    }

    /// 列出回收站内容。`supports_restore()` 为假时不必实现。
    fn list(&self) -> FileOpResult<Vec<TrashItemReceipt>> {
        Err(FileOpError::unsupported("这个平台上列不了回收站"))
    }
}

/// 真正调用操作系统的回收站。
///
/// 本文件里访问那个 crate 一律写 `::trash::…`（**带前导 `::`**），不是洁癖：
/// 父模块 `execute` 用 `use super::*` 做 glob 引入，只要它下面出现过一个叫
/// `trash` 的子模块，那个名字就会**盖住同名的 extern crate** —— `trash::TrashContext`
/// 于是解析成「本模块自己」，报
/// `E0433 could not find TrashContext in trash` / `E0425` / `E0659 trash is ambiguous`。
/// 2026-09-22 拆 `execute.rs` 时这个子模块确实短暂叫过 `trash`，后改名 `backend`。
/// 前导 `::` 走 extern prelude，与本地模块名无关，以后再怎么拆、怎么改名都不会复发。
pub struct SystemTrashBackend {
    context: ::trash::TrashContext,
}

impl SystemTrashBackend {
    pub fn new() -> Self {
        #[allow(unused_mut)]
        let mut context = ::trash::TrashContext::new();
        #[cfg(target_os = "macos")]
        {
            use ::trash::macos::{DeleteMethod, TrashContextExtMacos};
            // **别用 crate 的默认值（`DeleteMethod::Finder`）。** 它靠 `osascript` 让
            // Finder 去删，于是要先拿到「自动化 Finder」的 TCC 授权；没授权时系统直接
            // 拦成权限违例，实测 `osascript` 的 stderr 是
            // `execution error: "Finder"遇到一个错误：发生权限违例。(-10004)` ——
            // 用户看到的会是「删除失败」，而真正的原因藏在一个他从没听说过的授权里。
            //
            // `NsFileManager`（`trashItemAtURL`）**不需要额外权限**，crate 自己的对照表
            // 也这么写。代价是部分 macOS 版本上 Finder 右键的「放回原处」会消失
            // （crate 注明这是 macOS 的已知 bug）—— 但「删不掉」比「少一个右键项」严重得多。
            context.set_delete_method(DeleteMethod::NsFileManager);
        }
        Self { context }
    }
}

impl Default for SystemTrashBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Debug for SystemTrashBackend {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("SystemTrashBackend")
    }
}

impl TrashBackend for SystemTrashBackend {
    fn trash(&self, path: &Path) -> FileOpResult<TrashItemReceipt> {
        // `trash` 内部按平台分流（macOS `NSFileManager`、Windows `IFileOperation`、
        // Linux Freedesktop）。这正是 mImageViewer 那份 21 处 Windows API 的等效物，
        // 且是跨平台的。
        self.context.delete(path).map_err(|error| {
            FileOpError::new("EIO", format!("移入回收站失败 {}: {error}", path.display()))
        })?;
        // 删完立刻在回收站里找一遍，好让「撤销」有东西可用。
        // 找得到就带上 id；找不到（macOS）只留原路径，能力查询会如实说不能恢复。
        let item = os_limited_list()
            .unwrap_or_default()
            .into_iter()
            .filter(|candidate| candidate.original_parent.join(&candidate.name) == path)
            .max_by_key(|candidate| candidate.time_deleted);
        Ok(item.unwrap_or_else(|| TrashItemReceipt {
            id: None,
            name: path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default(),
            original_parent: path.parent().map(Path::to_path_buf).unwrap_or_default(),
            time_deleted: now_secs(),
        }))
    }

    fn supports_restore(&self) -> bool {
        os_limited_available()
    }

    fn restore(&self, item: &TrashItemReceipt) -> FileOpResult<()> {
        os_limited_restore(item)
    }

    fn list(&self) -> FileOpResult<Vec<TrashItemReceipt>> {
        os_limited_list()
    }
}

/// 这个平台上 `trash` crate 有没有 `os_limited` 那一套（list / restore / purge）。
///
/// 与 crate 里 `os_limited` 模块的 `cfg` **逐字同条件**：Windows 与 Freedesktop。
/// 改一处必须改另一处，所以两处都写了这句注释。
fn os_limited_available() -> bool {
    cfg!(windows)
        || cfg!(all(
            unix,
            not(target_os = "macos"),
            not(target_os = "ios"),
            not(target_os = "android")
        ))
}

/// 列回收站。**macOS 上这个函数永远返回 `ENOTSUP`** —— 这不是「还没实现」，
/// 是 macOS 没有对外的程序化回收站枚举接口，crate 因此把它整块 cfg 掉了。
#[cfg(any(
    windows,
    all(
        unix,
        not(target_os = "macos"),
        not(target_os = "ios"),
        not(target_os = "android")
    )
))]
fn os_limited_list() -> FileOpResult<Vec<TrashItemReceipt>> {
    let items = ::trash::os_limited::list()
        .map_err(|error| FileOpError::new("EIO", format!("列回收站失败: {error}")))?;
    Ok(items
        .into_iter()
        .map(|item| TrashItemReceipt {
            id: Some(item.id.to_string_lossy().into_owned()),
            name: item.name.to_string_lossy().into_owned(),
            original_parent: item.original_parent,
            time_deleted: item.time_deleted,
        })
        .collect())
}

#[cfg(not(any(
    windows,
    all(
        unix,
        not(target_os = "macos"),
        not(target_os = "ios"),
        not(target_os = "android")
    )
)))]
fn os_limited_list() -> FileOpResult<Vec<TrashItemReceipt>> {
    Err(FileOpError::unsupported(
        "这个平台上列不了回收站（macOS 没有程序化的回收站枚举接口）",
    ))
}

#[cfg(any(
    windows,
    all(
        unix,
        not(target_os = "macos"),
        not(target_os = "ios"),
        not(target_os = "android")
    )
))]
fn os_limited_restore(item: &TrashItemReceipt) -> FileOpResult<()> {
    let target = item.original_parent.join(&item.name);
    // 只列一次：`restore_all` 要的是 crate 自己的 `TrashItem`，而我们对外
    // 只暴露可序列化的 `TrashItemReceipt`，所以这里按 id 把原件找回来。
    let raw = ::trash::os_limited::list()
        .map_err(|error| FileOpError::new("EIO", format!("列回收站失败: {error}")))?;
    let wanted = item.id.as_deref().unwrap_or_default();
    let matched = raw
        .into_iter()
        .find(|candidate| candidate.id.to_string_lossy() == wanted)
        .ok_or_else(|| {
            FileOpError::new(
                "ENOENT",
                format!("回收站里找不到这一项: {}", target.display()),
            )
        })?;
    ::trash::os_limited::restore_all([matched])
        .map_err(|error| FileOpError::new("EIO", format!("从回收站恢复失败: {error}")))
}

#[cfg(not(any(
    windows,
    all(
        unix,
        not(target_os = "macos"),
        not(target_os = "ios"),
        not(target_os = "android")
    )
)))]
fn os_limited_restore(_item: &TrashItemReceipt) -> FileOpResult<()> {
    Err(FileOpError::unsupported(
        "这个平台上没有程序化的回收站恢复（macOS 需在 Finder 里手动放回）",
    ))
}
