//! 文件操作：**对用户数据做修改**的那一半。
//!
//! 这是 `local_core` 里唯一会写用户路径的模块。它之前不存在，于是文件管理器
//! 只能「看」不能「动」—— 缺口核对把这一类归成「写不出去」
//! （见 `docs/mimageviewer-gap-audit.md` §7.3）。
//!
//! ## 三层，各自的来源
//!
//! | 模块 | 做什么 | 来源 |
//! |---|---|---|
//! | [`selection`] | 多选状态的压缩表示与四则运算 | T3 逐行翻译 neoview `DirectorySelection.ts` |
//! | [`execute`] | 一条变更的落地、逐条结果、批量与取消 | T4 平台等效重写（上游 `delete_worker.rs` 撞 B2，搬形状不搬代码） |
//! | [`clipboard`] | 两步式剪切/复制 → 粘贴 | T3 对齐 neoview `FolderClipboard` + `prepareDirectoryClipboard` 契约 |
//!
//! ## 为什么多选和文件操作必须在同一个模块里
//!
//! 上游 mImageViewer 的 `delete_worker::spawn(paths: Vec<PathBuf>, …)` **原生收多路径**，
//! 而 Rossi 的文件卡片原先没有任何选中集合。两者分开做会做出「只能删当前光标那一项」
//! 的形态 —— 那不是缺一个功能，是把文件管理器的下限做低了。
//! 所以选中模型与操作执行在这里一起落地，`selection` 的产出（一串路径）
//! 就是 `execute` 的输入。
//!
//! ## 边界（不该放进来什么）
//!
//! - **不做 UI**。撤销提示条、确认对话框、进度条都在 Flutter 侧，
//!   这里只给「能不能撤销」「几项失败」这种可判定的数据。
//! - **不做目录监听**（上游 G-31）。那是另一件事：它是**读**侧的外部变化通知。
//! - **不落盘状态**。选中的是哪个目录、剪贴板里有什么，都活在会话里。

pub mod clipboard;
pub mod execute;
pub mod selection;

pub use clipboard::{
    ClipboardMode, DirectoryClipboard, DirectoryClipboardSnapshot, is_under, validate_paste,
};
pub use execute::{
    ConflictPolicy, FileMutation, FileMutationGuard, FileOpError, FileOpResult,
    FileOperationBatchResult, FileOperationResult, FileUndoReceipt, SystemTrashBackend,
    TrashBackend, TrashItemReceipt, copy_tree, error_code_of, execute_mutation, move_entry,
    remove_at, run_batch, snapshot, undo_batch, undo_mutation, unique_destination,
};
pub use selection::{
    ChainOptions, DirectorySelectionDescriptor, DirectorySelectionModel, DirectorySelectionRange,
    ExtendOptions, chain_directory_selection, create_directory_selection,
    directory_selection_count, directory_selection_descriptor, extend_directory_selection,
    invert_directory_selection, is_directory_index_selected, rebase_directory_selection,
    replace_directory_selection_path, select_all_directory_entries, select_directory_single,
    toggle_directory_selection,
};
