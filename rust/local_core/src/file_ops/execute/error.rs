//! 表示单条操作失败的 `FileOpError`，以及 `FileOpResult` 别名。
//!
//! 配置类型、快照 / 守卫的辅助函数在父 `execute.rs` 里。兄弟模块之间
//! 无法引用彼此的私有项，所以**被调用的一侧保留在父模块**。

use super::*;

// ─────────────────────────────────────────────────────────────────────────────
// 错误
// ─────────────────────────────────────────────────────────────────────────────

/// 逐条操作的失败。
///
/// `code` 用 POSIX 风格的短码（`EEXIST` / `EXDEV` / `ESTALE`…），与 neoview 的
/// `errorCode` 同一套取值 —— UI 要按码给不同提示（「同名已存在」和「跨卷失败」不是一回事）。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileOpError {
    pub code: &'static str,
    pub message: String,
}

impl FileOpError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// 目标已存在。上游 `assertDestinationAbsent` 抛的就是它。
    pub fn exists(path: &Path) -> Self {
        Self::new("EEXIST", format!("目标已存在: {}", path.display()))
    }

    /// 撤销时目标已被改动。上游 `stalePath`。
    pub fn stale(path: &Path) -> Self {
        Self::new(
            "ESTALE",
            format!("撤销目标在操作之后被改动过: {}", path.display()),
        )
    }

    pub fn unsupported(what: &str) -> Self {
        Self::new("ENOTSUP", what.to_string())
    }

    pub fn from_io(error: io::Error, path: &Path) -> Self {
        let code = error_code_of(&error);
        Self::new(
            code,
            format!(
                "{}: {}",
                path.display(),
                error.to_string().trim().to_string()
            ),
        )
    }
}

impl std::fmt::Display for FileOpError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "[{}] {}", self.code, self.message)
    }
}

impl std::error::Error for FileOpError {}

/// `io::Error` → 短码。没把握的一律 `EIO`，绝不把 `EINVAL` 当成兜底
/// （UI 会用 `EINVAL` 表示「路径本身不合法」）。
pub fn error_code_of(error: &io::Error) -> &'static str {
    match error.kind() {
        io::ErrorKind::NotFound => "ENOENT",
        io::ErrorKind::AlreadyExists => "EEXIST",
        io::ErrorKind::PermissionDenied => "EACCES",
        io::ErrorKind::CrossesDevices => "EXDEV",
        io::ErrorKind::InvalidInput | io::ErrorKind::InvalidData => "EINVAL",
        io::ErrorKind::IsADirectory => "EISDIR",
        io::ErrorKind::DirectoryNotEmpty => "ENOTEMPTY",
        io::ErrorKind::StorageFull => "ENOSPC",
        _ => "EIO",
    }
}

pub type FileOpResult<T> = Result<T, FileOpError>;
