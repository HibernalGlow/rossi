//! 批量执行（多选的落点）及其汇总结果。

use super::*;

// ─────────────────────────────────────────────────────────────────────────────
// 批量执行（多选的落点）
// ─────────────────────────────────────────────────────────────────────────────

/// 一条操作的结果。对应 neoview `FileOperationResult`。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileOperationResult {
    pub index: usize,
    pub operation: FileMutation,
    /// `succeeded` / `failed` / `cancelled`
    pub status: &'static str,
    pub error_code: Option<&'static str>,
    pub error: Option<String>,
}

impl FileOperationResult {
    pub fn is_succeeded(&self) -> bool {
        self.status == "succeeded"
    }
}

/// 一批操作的结果。对应 neoview `FileOperationBatchResult`。
#[derive(Clone, Debug, Default)]
pub struct FileOperationBatchResult {
    pub results: Vec<FileOperationResult>,
    pub succeeded: usize,
    pub failed: usize,
    pub cancelled: usize,
    /// 生成了回执、可以撤销的条数。
    pub undoable: usize,
    /// 撤销这些条目的回执（按发生顺序）。
    pub undo_receipts: Vec<FileUndoReceipt>,
}

impl FileOperationBatchResult {
    /// UI 摘要，例如「已复制 3 项，1 项失败」。上游也是把 `succeeded` / `failed`
    /// 交给文案层拼，不在数据层写句子。
    pub fn summary(&self, verb: &str) -> String {
        if self.failed == 0 && self.cancelled == 0 {
            return format!("{verb} {} 项", self.succeeded);
        }
        let mut parts = vec![format!("{verb} {} 项", self.succeeded)];
        if self.failed > 0 {
            parts.push(format!("{} 项失败", self.failed));
        }
        if self.cancelled > 0 {
            parts.push(format!("{} 项已取消", self.cancelled));
        }
        parts.join("，")
    }
}

/// 逐条执行一批变更。
///
/// 与上游 `FileOperationService` 的差别只有并发：上游用 `p-map(concurrency: 4)` 且
/// `stopOnError: true`。这里**串行**执行，理由是这批操作通常面向同一个目录
/// （同一个卷、同一份 inode 缓存），四条并发带来的收益抵不过「部分成功之后
/// 哪几条成功了」的推理成本；而 `stopOnError` 那条语义保留了 —— 一旦某条失败，
/// 后面的条目标成 `cancelled` 而不是继续硬做。
///
/// `cancel` 由调用方持有，为 `true` 时**不再开始下一条**（正在跑的那一条会跑完，
/// 因为文件操作没有安全的半途中断点）。
pub fn run_batch(
    mutations: &[FileMutation],
    backend: &dyn TrashBackend,
    cancel: &AtomicBool,
) -> FileOperationBatchResult {
    let mut batch = FileOperationBatchResult::default();
    let mut stopped = false;

    for (index, mutation) in mutations.iter().enumerate() {
        if stopped || cancel.load(Ordering::Relaxed) {
            batch.cancelled += 1;
            batch.results.push(FileOperationResult {
                index,
                operation: mutation.clone(),
                status: "cancelled",
                error_code: None,
                error: None,
            });
            continue;
        }

        match execute_mutation(mutation, backend, true) {
            Ok(receipt) => {
                batch.succeeded += 1;
                if let Some(receipt) = receipt {
                    batch.undoable += 1;
                    batch.undo_receipts.push(receipt);
                }
                batch.results.push(FileOperationResult {
                    index,
                    operation: mutation.clone(),
                    status: "succeeded",
                    error_code: None,
                    error: None,
                });
            }
            Err(error) => {
                batch.failed += 1;
                batch.results.push(FileOperationResult {
                    index,
                    operation: mutation.clone(),
                    status: "failed",
                    error_code: Some(error.code),
                    error: Some(error.message),
                });
                // 上游 `stopOnError: true`：一条失败就停，后面的标 cancelled。
                // 这比「继续做完剩下的」更安全：批量删除遇到第一条失败时，
                // 用户看到的应该是一个需要他重新判断的局面，而不是半批已删。
                stopped = true;
            }
        }
    }

    batch
}

/// 撤销一整批。逐条独立撤销，一条失败不影响其余（撤销比执行更该「能做多少做多少」）。
pub fn undo_batch(
    receipts: &[FileUndoReceipt],
    backend: &dyn TrashBackend,
) -> FileOperationBatchResult {
    let mut batch = FileOperationBatchResult::default();
    for (index, receipt) in receipts.iter().enumerate() {
        match undo_mutation(receipt, backend) {
            Ok(()) => {
                batch.succeeded += 1;
                batch.results.push(FileOperationResult {
                    index,
                    operation: receipt.original.clone(),
                    status: "succeeded",
                    error_code: None,
                    error: None,
                });
            }
            Err(error) => {
                batch.failed += 1;
                batch.results.push(FileOperationResult {
                    index,
                    operation: receipt.original.clone(),
                    status: "failed",
                    error_code: Some(error.code),
                    error: Some(error.message),
                });
            }
        }
    }
    batch
}
