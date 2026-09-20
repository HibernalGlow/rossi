//! 文件操作的 FRB 桥：**多选状态** + **写操作的入口**。
//!
//! 核心实现全在 `rossi_local_core::file_ops`（多选模型 / 跨平台执行 / 剪贴板）。
//! 这一层只做三件核心里做不了的事：
//!
//! 1. **持有会话态的选中集合与剪贴板**。它们必须活在同一个地方、与文件列表同一个
//!    generation —— 选中是按**列表下标**表达的，下标只在某一份 `entries()` 上有意义。
//!    所以这里直接读 `file_manager` 的会话真本（`FILE_MANAGER_SESSIONS`），
//!    而不是自己再列一遍目录（那会让两边各有各的时序，选中项指到别的条目上）。
//! 2. **把报告摊平成可序列化的形状**（逐条结果 + 聚合计数 + 一句摘要）。
//! 3. **在写操作之后把列表刷新一次**。用户改完盘上的东西，卡片上的列表必须跟着变；
//!    让 Dart 侧自己记得「删完要刷新」迟早会漏（当前有七八个改目录的入口）。
//!
//! ## 撤销日志上限
//!
//! 50 条，与 neoview 的 `FileOperationService` 一致。超出就丢最老的：
//! 撤销是「刚删错了」的补救，不是历史记录 —— 一小时前那次删除不该还能一键回滚，
//! 因为这中间用户很可能已经往那个名字上放了新东西（守卫会拦，但拦住时用户会困惑）。
//!
//! ## 回收站的可撤销性是能力，不是开关
//!
//! `trash` crate 在 macOS 上没有程序化的恢复接口（见 `file_ops::execute` 的模块注释）。
//! 所以 [`FileOpsSnapshot::trash_restore_supported`] 会被如实报给 UI，
//! **菜单与提示条要按它决定「撤销」这一项出不出来**，而不是假设到处都能恢复。

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Error, anyhow};
use dashmap::DashMap;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use rossi_local_core::file_ops::{
    ClipboardMode, ConflictPolicy, DirectoryClipboard, DirectorySelectionModel, FileMutation,
    FileOperationBatchResult, FileUndoReceipt, SystemTrashBackend, TrashBackend,
    chain_directory_selection, create_directory_selection, invert_directory_selection,
    rebase_directory_selection, replace_directory_selection_path, run_batch,
    select_all_directory_entries, select_directory_single, toggle_directory_selection, undo_batch,
    validate_paste,
};

use super::file_manager::FILE_MANAGER_SESSIONS;

/// 撤销日志上限（对齐 neoview 的 `FileOperationService.undoLimit`）。
const MAX_UNDO_HISTORY: usize = 50;

lazy_static! {
    /// 与文件管理器会话同 id 的写侧状态。
    ///
    /// 为什么不挂在 `FileManagerState` 上：那个结构每次用户动作前要 `clone` 一份做
    /// 事务回滚，而撤销日志里揣着 `PathBuf` 快照，逐次深拷是白花的钱；
    /// 更要紧的是**选中集合不该参与导航事务** —— 用户翻个目录再回来，
    /// 选中态该按 rebase 的规则降级，而不是跟着回滚成上一个目录的样子。
    static ref FILE_OPS_SESSIONS: Mutex<std::collections::HashMap<u64, FileOpsSession>> =
        Mutex::new(std::collections::HashMap::new());
    /// 每个会话当前这一批的取消旗子。
    ///
    /// 单独放一张表（而不是塞进上面的 Mutex）是必须的：批量删除要能被打断，
    /// 而打断它的那一次调用拿不到被 `Mutex` 占着的会话。
    static ref FILE_OPS_CANCEL: DashMap<u64, Arc<AtomicBool>> = DashMap::new();
}

struct FileOpsSession {
    selection: DirectorySelectionModel,
    clipboard: DirectoryClipboard,
    undo: Vec<FileUndoReceipt>,
}

impl FileOpsSession {
    fn new(generation: u64) -> Self {
        Self {
            selection: create_directory_selection(generation),
            clipboard: DirectoryClipboard::new(ClipboardMode::Copy, Vec::new(), generation),
            undo: Vec::new(),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 投影给 Dart 的形状
// ─────────────────────────────────────────────────────────────────────────────

/// 剪贴板模式。`cut` 而不是 `move`：`move` 是 Rust 关键字，而且**剪贴板这一侧
/// 的语义本来就叫「剪切」** —— `move` 是它落到盘上的动作，不是用户做的选择。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileOpsClipboardMode {
    Copy,
    Cut,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileOpsItemStatus {
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone)]
pub struct FileOpsItemResult {
    pub path: String,
    pub status: FileOpsItemStatus,
    pub error_code: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FileOpsReport {
    /// `copy` / `move` / `rename` / `delete` / `trash` / `create-directory`。
    pub kind: String,
    pub succeeded: u32,
    pub failed: u32,
    pub cancelled: u32,
    /// 生成了回执、可以撤销的条数。
    pub undoable: u32,
    /// 一句给提示条用的摘要，例如「已移到回收站 3 项，1 项失败」。
    pub summary: String,
    /// 逐条结果。UI 用它把失败项标回列表里的那一行。
    pub items: Vec<FileOpsItemResult>,
    /// 刷新过列表之后的新快照，省掉一次往返。
    pub snapshot: FileOpsSnapshot,
}

#[derive(Debug, Clone)]
pub struct FileOpsSnapshot {
    pub session_id: u64,
    /// 这份选中态对应的列表版本号。
    pub generation: u64,
    pub total: u32,
    pub selected_count: u32,
    pub all_selected: bool,
    /// 当前选中的**路径**（已按下标 + 路径双轨解析，见核心 `selection` 模块）。
    pub selected_paths: Vec<String>,
    /// 这些选中项里有没有目录（决定「粘贴进选中项」这类动作可不可用）。
    pub selection_has_directory: bool,
    /// 剪贴板非空且当前目录可粘贴。
    pub can_paste: bool,
    pub clipboard_mode: Option<FileOpsClipboardMode>,
    pub clipboard_count: u32,
    pub can_undo: bool,
    pub undo_count: u32,
    /// 这个平台上「移到回收站」能不能撤销。**macOS 为 false**。
    pub trash_restore_supported: bool,
}

// ─────────────────────────────────────────────────────────────────────────────
// 内部：读列表真本 / 跑一批
// ─────────────────────────────────────────────────────────────────────────────

/// 一次操作要用的列表快照。在拿 `FILE_OPS_SESSIONS` 锁**之前**从会话里读出来，
/// 免得两个锁叠在一起形成锁序问题（`with_pane` 当初也是为这个拆开的）。
struct ListingSnapshot {
    generation: u64,
    active_path: PathBuf,
    paths: Vec<String>,
    directories: Vec<bool>,
}

fn read_listing(id: u64) -> Result<ListingSnapshot, Error> {
    // 先把要读的读干净再放掉会话引用：`entries()` 要枚举目录，是这一段里唯一会
    // 阻塞的调用，握着 `DashMap` 的分片锁做它会把同一张卡片的其它动作全堵住。
    let state = FILE_MANAGER_SESSIONS
        .get(&id)
        .ok_or_else(|| anyhow!("文件管理器会话不存在或已关闭: id={id}"))?;
    let entries = state.entries()?;
    let generation = state.generation();
    let active_path = state.active_path().to_path_buf();
    drop(state);
    Ok(ListingSnapshot {
        generation,
        active_path,
        paths: entries
            .iter()
            .map(|entry| entry.node.path.clone())
            .collect(),
        directories: entries.iter().map(|entry| entry.node.is_dir).collect(),
    })
}

fn with_ops<R>(id: u64, operation: impl FnOnce(&mut FileOpsSession) -> R) -> Result<R, Error> {
    let mut sessions = FILE_OPS_SESSIONS
        .lock()
        .map_err(|_| anyhow!("文件操作会话的锁已中毒"))?;
    let session = sessions.entry(id).or_insert_with(|| FileOpsSession::new(0));
    Ok(operation(session))
}

fn cancel_flag(id: u64) -> Arc<AtomicBool> {
    FILE_OPS_CANCEL
        .entry(id)
        .or_insert_with(|| Arc::new(AtomicBool::new(false)))
        .clone()
}

/// 写完之后让文件管理器的列表跟上。
///
/// `refresh()` 只是把 generation 加一并让缓存失效，真正的枚举发生在下一次
/// `entries()`。于是这里紧接着取一次快照（`read_listing` 顺带就枚举了），
/// 拿到的是**刷新后**的列表 —— UI 拿到报告时看到的已经是新状态。
fn refresh_listing(id: u64) -> Result<ListingSnapshot, Error> {
    {
        let mut state = FILE_MANAGER_SESSIONS
            .get_mut(&id)
            .ok_or_else(|| anyhow!("文件管理器会话不存在或已关闭: id={id}"))?;
        state.refresh();
    }
    read_listing(id)
}

fn project_items(batch: &FileOperationBatchResult) -> Vec<FileOpsItemResult> {
    batch
        .results
        .iter()
        .map(|result| FileOpsItemResult {
            path: result
                .operation
                .source_path()
                .map(|path| path.to_string_lossy().into_owned())
                // 新建目录没有源路径，用目标路径当身份 —— UI 要标回列表里的那一行。
                .or_else(|| match &result.operation {
                    FileMutation::CreateDirectory { destination_path } => {
                        Some(destination_path.to_string_lossy().into_owned())
                    }
                    _ => None,
                })
                .unwrap_or_default(),
            status: match result.status {
                "succeeded" => FileOpsItemStatus::Succeeded,
                "cancelled" => FileOpsItemStatus::Cancelled,
                _ => FileOpsItemStatus::Failed,
            },
            error_code: result.error_code.map(str::to_string),
            error: result.error.clone(),
        })
        .collect()
}

/// 一次写操作的收尾：刷新列表 → 按操作类型收敛选中态 → 接上撤销日志。
///
/// 选中态为什么要按类型分别处理：**删除之后那些路径已经不存在了**。
/// 留着它们在选中集合里，界面上会显示「已选 3 项」而列表里只有 1 行 ——
/// 用户会以为程序坏了。neoview 的做法同样是「成功后收敛为单选/清空」。
fn finish_write(
    id: u64,
    kind: &str,
    batch: &FileOperationBatchResult,
    mutations: &[FileMutation],
) -> Result<FileOpsSnapshot, Error> {
    let listing = refresh_listing(id)?;

    with_ops(id, |session| {
        // 先按「列表换代」降级一次，再把成功的条目按类型搬到新位置。
        let mut selection = rebase_directory_selection(&session.selection, listing.generation);
        let mut clear = false;
        for (index, mutation) in mutations.iter().enumerate() {
            let succeeded = batch
                .results
                .iter()
                .find(|result| result.index == index)
                .map(|result| result.is_succeeded())
                .unwrap_or(false);
            if !succeeded {
                continue;
            }
            match mutation {
                // 路径没了：留着就是幽灵选中项。
                FileMutation::Trash { .. } | FileMutation::Delete { .. } => clear = true,
                FileMutation::Move {
                    source_path,
                    destination_path,
                    ..
                }
                | FileMutation::Rename {
                    source_path,
                    destination_path,
                    ..
                } => {
                    selection = replace_directory_selection_path(
                        &selection,
                        &source_path.to_string_lossy(),
                        &destination_path.to_string_lossy(),
                    );
                }
                FileMutation::Copy { .. } | FileMutation::CreateDirectory { .. } => {}
            }
        }
        if clear {
            selection = create_directory_selection(listing.generation);
        }
        session.selection = selection;

        // 剪切粘完就清空剪贴板；复制留着，好连着粘到几个目录。
        if kind == "move" {
            session.clipboard.clear_if_move();
        }

        if batch.undoable > 0 {
            session.undo.extend(batch.undo_receipts.iter().cloned());
            let overflow = session.undo.len().saturating_sub(MAX_UNDO_HISTORY);
            if overflow > 0 {
                session.undo.drain(0..overflow);
            }
        }
    })?;

    snapshot_for(id)
}

/// 把一批变更跑在核心上。取消旗子在开跑前重置，跑完再复位。
fn execute_batch(
    id: u64,
    mutations: Vec<FileMutation>,
) -> Result<(FileOperationBatchResult, String), Error> {
    let kind = mutations
        .first()
        .map(|mutation| mutation.kind().to_string())
        .unwrap_or_else(|| "unknown".to_string());
    let cancel = cancel_flag(id);
    cancel.store(false, Ordering::Relaxed);
    let backend = SystemTrashBackend::new();
    let batch = run_batch(&mutations, &backend, &cancel);
    Ok((batch, kind))
}

fn summary_for(kind: &str, batch: &FileOperationBatchResult) -> String {
    let verb = match kind {
        "copy" => "已复制",
        "move" => "已移动",
        "rename" => "已重命名",
        "trash" => "已移到回收站",
        "delete" => "已永久删除",
        "create-directory" => "已新建",
        _ => "已完成",
    };
    batch.summary(verb)
}

fn snapshot_for(id: u64) -> Result<FileOpsSnapshot, Error> {
    let listing = read_listing(id)?;
    with_ops(id, |session| {
        // 顺手对齐一次 generation：读快照本身不该改状态，但**报出去的选中数
        // 必须与报出去的列表是同一代**，否则 UI 会拿旧代的下标去标新代的行走。
        let selection = if session.selection.generation == listing.generation {
            session.selection.clone()
        } else {
            rebase_directory_selection(&session.selection, listing.generation)
        };
        let selected_paths = selection.selected_paths(&listing.paths);
        let selection_has_directory = selected_paths.iter().any(|path| {
            listing
                .paths
                .iter()
                .position(|candidate| candidate == path)
                .map(|index| listing.directories[index])
                .unwrap_or(false)
        });
        let can_paste = !session.clipboard.is_empty();
        FileOpsSnapshot {
            session_id: id,
            generation: listing.generation,
            total: listing.paths.len() as u32,
            selected_count: selection.count(listing.paths.len()) as u32,
            all_selected: selection.all_selected,
            selected_paths,
            selection_has_directory,
            can_paste,
            clipboard_mode: if can_paste {
                Some(match session.clipboard.mode() {
                    ClipboardMode::Copy => FileOpsClipboardMode::Copy,
                    ClipboardMode::Move => FileOpsClipboardMode::Cut,
                })
            } else {
                None
            },
            clipboard_count: session.clipboard.len() as u32,
            can_undo: !session.undo.is_empty(),
            undo_count: session.undo.len() as u32,
            trash_restore_supported: SystemTrashBackend::new().supports_restore(),
        }
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// 选中
// ─────────────────────────────────────────────────────────────────────────────

#[frb]
pub async fn file_ops_snapshot(id: u64) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || snapshot_for(id))
        .await?
}

#[frb]
pub async fn file_ops_select_single(
    id: u64,
    path: String,
    index: u32,
) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = select_directory_single(generation, &path, index as usize);
            })?;
            snapshot_for(id)
        })
        .await?
}

#[frb]
pub async fn file_ops_select_toggle(
    id: u64,
    path: String,
    index: u32,
) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = toggle_directory_selection(
                    &session.selection,
                    generation,
                    &path,
                    index as usize,
                );
            })?;
            snapshot_for(id)
        })
        .await?
}

/// Shift 连选：从锚点连到 [end_index]。
#[frb]
pub async fn file_ops_select_chain(
    id: u64,
    end_index: u32,
    anchor_index: Option<u32>,
    end_path: String,
) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = chain_directory_selection(
                    &session.selection,
                    generation,
                    end_index as usize,
                    rossi_local_core::file_ops::ChainOptions {
                        anchor_index: anchor_index.map(|index| index as usize),
                        anchor_path: None,
                        end_path: &end_path,
                    },
                );
            })?;
            snapshot_for(id)
        })
        .await?
}

#[frb]
pub async fn file_ops_select_all(id: u64) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = select_all_directory_entries(generation);
            })?;
            snapshot_for(id)
        })
        .await?
}

#[frb]
pub async fn file_ops_invert_selection(id: u64) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = invert_directory_selection(&session.selection, generation);
            })?;
            snapshot_for(id)
        })
        .await?
}

#[frb]
pub async fn file_ops_clear_selection(id: u64) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let generation = read_listing(id)?.generation;
            with_ops(id, |session| {
                session.selection = create_directory_selection(generation);
            })?;
            snapshot_for(id)
        })
        .await?
}

// ─────────────────────────────────────────────────────────────────────────────
// 剪贴板
// ─────────────────────────────────────────────────────────────────────────────

/// 把当前选中项放进剪贴板。[cut] 为真时是剪切（粘贴时走 move）。
#[frb]
pub async fn file_ops_copy_to_clipboard(id: u64, cut: bool) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let listing = read_listing(id)?;
            with_ops(id, |session| {
                let selection = if session.selection.generation == listing.generation {
                    session.selection.clone()
                } else {
                    rebase_directory_selection(&session.selection, listing.generation)
                };
                let sources = selection
                    .selected_paths(&listing.paths)
                    .into_iter()
                    .map(PathBuf::from)
                    .collect::<Vec<_>>();
                session.clipboard = DirectoryClipboard::new(
                    if cut {
                        ClipboardMode::Move
                    } else {
                        ClipboardMode::Copy
                    },
                    sources,
                    listing.generation,
                );
            })?;
            snapshot_for(id)
        })
        .await?
}

#[frb]
pub async fn file_ops_clear_clipboard(id: u64) -> Result<FileOpsSnapshot, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            with_ops(id, |session| session.clipboard.clear())?;
            snapshot_for(id)
        })
        .await?
}

/// 粘贴。[destination] 为空 = 粘到当前目录；给了路径 = 粘到**那一项**里
/// （右键菜单的「粘贴到这一项」走这条，落点就是被右键的那个文件夹）。
#[frb]
pub async fn file_ops_paste(id: u64, destination: Option<String>) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let listing = read_listing(id)?;
            // 先确认落点**确实是个目录**。让 `paste_mutations` 去算的话，它会老实
            // 算出一堆「<文件路径>/名字」形式的落点，然后在复制那一步才失败 ——
            // 报出来的是「复制失败」而不是「你把它粘到一个文件上了」。
            let target = match destination {
                Some(path) => {
                    let target = PathBuf::from(&path);
                    if !target.is_dir() {
                        return Err(anyhow!("粘贴的落点不是目录: {path}"));
                    }
                    target
                }
                None => listing.active_path.clone(),
            };
            // 闭包只回传「算好的变更」，不回传 kind：`kind` 由 `execute_batch`
            // 从第一条变更自己认（`copy` / `move`），这里再算一份是第二个真本，
            // 而且校验失败那一支根本走不到 `execute_batch`（错误直接向上抛）。
            let mutations = with_ops(id, |session| {
                let sources = session.clipboard.sources().to_vec();
                let mode = session.clipboard.mode();
                if let Err(error) = validate_paste(&sources, &target, mode) {
                    session.clipboard.clear();
                    return Err(error);
                }
                Ok(session
                    .clipboard
                    .paste_mutations(&target, ConflictPolicy::Fail))
            })?;
            let mutations = mutations.map_err(|error| anyhow!(error.to_string()))?;

            let (batch, kind) = execute_batch(id, mutations.clone())?;
            let snapshot = finish_write(id, &kind, &batch, &mutations)?;
            Ok(FileOpsReport {
                kind: kind.clone(),
                succeeded: batch.succeeded as u32,
                failed: batch.failed as u32,
                cancelled: batch.cancelled as u32,
                undoable: batch.undoable as u32,
                summary: summary_for(&kind, &batch),
                items: project_items(&batch),
                snapshot,
            })
        })
        .await?
}

// ─────────────────────────────────────────────────────────────────────────────
// 写操作
// ─────────────────────────────────────────────────────────────────────────────

fn selection_mutations(id: u64) -> Result<Vec<PathBuf>, Error> {
    let listing = read_listing(id)?;
    let paths = with_ops(id, |session| {
        let selection = if session.selection.generation == listing.generation {
            session.selection.clone()
        } else {
            rebase_directory_selection(&session.selection, listing.generation)
        };
        selection.selected_paths(&listing.paths)
    })?;
    Ok(paths.into_iter().map(PathBuf::from).collect())
}

#[frb]
pub async fn file_ops_trash_selection(id: u64) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let mutations: Vec<FileMutation> = selection_mutations(id)?
                .into_iter()
                .map(|source_path| FileMutation::Trash { source_path })
                .collect();
            report_for(id, mutations)
        })
        .await?
}

#[frb]
pub async fn file_ops_delete_selection(id: u64) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let mutations: Vec<FileMutation> = selection_mutations(id)?
                .into_iter()
                .map(|source_path| FileMutation::Delete { source_path })
                .collect();
            report_for(id, mutations)
        })
        .await?
}

fn report_for(id: u64, mutations: Vec<FileMutation>) -> Result<FileOpsReport, Error> {
    if mutations.is_empty() {
        let snapshot = snapshot_for(id)?;
        return Ok(FileOpsReport {
            kind: "none".to_string(),
            succeeded: 0,
            failed: 0,
            cancelled: 0,
            undoable: 0,
            summary: "没有选中任何条目".to_string(),
            items: Vec::new(),
            snapshot,
        });
    }
    let (batch, kind) = execute_batch(id, mutations.clone())?;
    let snapshot = finish_write(id, &kind, &batch, &mutations)?;
    Ok(FileOpsReport {
        kind: kind.clone(),
        succeeded: batch.succeeded as u32,
        failed: batch.failed as u32,
        cancelled: batch.cancelled as u32,
        undoable: batch.undoable as u32,
        summary: summary_for(&kind, &batch),
        items: project_items(&batch),
        snapshot,
    })
}

/// 重命名一个条目。[new_name] 是新的**名字**，不是路径 —— 与上游一样要求同目录。
#[frb]
pub async fn file_ops_rename_entry(
    id: u64,
    path: String,
    new_name: String,
) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let source = PathBuf::from(&path);
            let parent = source
                .parent()
                .ok_or_else(|| anyhow!("这一项没有父目录，不能改名: {path}"))?;
            let destination = parent.join(&new_name);
            let mutations = vec![FileMutation::Rename {
                source_path: source,
                destination_path: destination,
                conflict: ConflictPolicy::Fail,
            }];
            let (batch, kind) = execute_batch(id, mutations.clone())?;
            let snapshot = finish_write(id, &kind, &batch, &mutations)?;
            Ok(FileOpsReport {
                kind: kind.clone(),
                succeeded: batch.succeeded as u32,
                failed: batch.failed as u32,
                cancelled: batch.cancelled as u32,
                undoable: batch.undoable as u32,
                summary: summary_for(&kind, &batch),
                items: project_items(&batch),
                snapshot,
            })
        })
        .await?
}

/// 新建一个文件夹。[parent] 为空 = 建在当前目录；给了路径 = 建在**那一项**
/// （目录）里（右键菜单的「新建文件夹」走这条）。撞名时顺延成 `名字 (2)`
/// （见核心的 `unique_destination`）。
#[frb]
pub async fn file_ops_create_directory(
    id: u64,
    name: String,
    parent: Option<String>,
) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let listing = read_listing(id)?;
            let parent = match parent {
                Some(path) => {
                    let parent = PathBuf::from(&path);
                    if !parent.is_dir() {
                        return Err(anyhow!("新建文件夹的落点不是目录: {path}"));
                    }
                    parent
                }
                None => listing.active_path.clone(),
            };
            let mut destination = parent.join(&name);
            if destination.exists() {
                destination = rossi_local_core::file_ops::unique_destination(&destination);
            }
            let mutations = vec![FileMutation::CreateDirectory {
                destination_path: destination,
            }];
            let (batch, kind) = execute_batch(id, mutations.clone())?;
            let snapshot = finish_write(id, &kind, &batch, &mutations)?;
            Ok(FileOpsReport {
                kind: kind.clone(),
                succeeded: batch.succeeded as u32,
                failed: batch.failed as u32,
                cancelled: batch.cancelled as u32,
                undoable: batch.undoable as u32,
                summary: summary_for(&kind, &batch),
                items: project_items(&batch),
                snapshot,
            })
        })
        .await?
}

/// 撤销最近一批。整份撤销日志一起回滚（对齐 neoview 的 `undo`：
/// 一次删除带来的那几条要一起回来，只回滚一半等于留下一个说不清的局面）。
#[frb]
pub async fn file_ops_undo(id: u64) -> Result<FileOpsReport, Error> {
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            let receipts = with_ops(id, |session| std::mem::take(&mut session.undo))?;
            if receipts.is_empty() {
                let snapshot = snapshot_for(id)?;
                return Ok(FileOpsReport {
                    kind: "undo".to_string(),
                    succeeded: 0,
                    failed: 0,
                    cancelled: 0,
                    undoable: 0,
                    summary: "没有可撤销的操作".to_string(),
                    items: Vec::new(),
                    snapshot,
                });
            }
            let backend = SystemTrashBackend::new();
            let batch = undo_batch(&receipts, &backend);
            // 撤销不回填日志：撤销完再撤销自己会让状态绕回不明。
            let listing = refresh_listing(id)?;
            with_ops(id, |session| {
                session.selection = create_directory_selection(listing.generation);
            })?;
            let snapshot = snapshot_for(id)?;
            Ok(FileOpsReport {
                kind: "undo".to_string(),
                succeeded: batch.succeeded as u32,
                failed: batch.failed as u32,
                cancelled: batch.cancelled as u32,
                undoable: 0,
                summary: if batch.failed == 0 {
                    format!("已撤销 {} 项", batch.succeeded)
                } else {
                    format!("已撤销 {} 项，{} 项失败", batch.succeeded, batch.failed)
                },
                items: project_items(&batch),
                snapshot,
            })
        })
        .await?
}

/// 打断正在跑的那一批。**不会**中断正在落地的那一条 —— 文件操作没有安全的
/// 半途中断点；能让它停在条目边界，就已经避免了「后面几十项也照做」。
#[frb]
pub fn file_ops_cancel(id: u64) -> bool {
    match FILE_OPS_CANCEL.get(&id) {
        Some(flag) => {
            flag.store(true, Ordering::Relaxed);
            true
        }
        None => false,
    }
}

/// 卡片关闭时回收。与 `file_manager_close` 成对调用。
#[frb]
pub fn file_ops_close(id: u64) -> bool {
    FILE_OPS_CANCEL.remove(&id);
    let removed = FILE_OPS_SESSIONS
        .lock()
        .map(|mut sessions| sessions.remove(&id).is_some())
        .unwrap_or(false);
    removed
}

/// 给判据用：这个平台能不能撤销回收站操作。UI 靠 [`FileOpsSnapshot`] 的同名字段，
/// 这里只是把一个纯查询也暴露出来，免得 Dart 侧为了问一句去开一个会话。
#[frb]
pub fn file_ops_trash_restore_supported() -> bool {
    SystemTrashBackend::new().supports_restore()
}
