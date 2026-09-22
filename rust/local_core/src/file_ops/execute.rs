//! 跨平台文件操作执行层。
//!
//! **T4 平台等效重写**。上游 mImageViewer 的 `src/delete_worker.rs` 顶部 `use` 只有
//! `std`，但**函数体内有 21 处 Windows API**（`IFileOperation`、`hwnd: Option<isize>`），
//! 属 ADR-0008 的 B2 边界（平台专有）——直接搬会编不过，或把跨平台产品锁死 Windows。
//! 因此这里搬的是**形状**而不是代码：
//!
//! - 「一次请求收多条路径、逐条出结果」的多选语义（上游 `spawn(paths: Vec<PathBuf>, …)`）；
//! - 「分块执行 + 可取消 + 失败重试」的调度形状（上游 `DeletePending` / `recycle_chunk_with_retry`）；
//! - 「回收站 vs 永久删除」两种语义分开（上游 `recycle_flags()` 里 `FOF_WANTNUKEWARNING`）。
//!
//! 契约（`FileMutation` / `FileUndoReceipt` / `FileOperationResult` 的字段与取值）
//! 逐条对齐 neoview 的 `packages/file-operations/src/types.ts` 与 `platform.ts`，
//! 这样「同一条命令在两侧的行为」可以逐项对照。平台差异只落在**实现**上：
//!
//! | 动作 | neoview | 这里 |
//! |---|---|---|
//! | 回收站 | `@xiranite/czkawka-native` 的 `trashPath`（trash-rs） | `trash` crate 5（同一族实现） |
//! | 永久删除 | `node:fs/promises.rm` | `std::fs` |
//! | 复制 | `cp(recursive, errorOnExist)` | `std::fs` 递归 + 符号链接按链接复制 |
//! | 移动 / 改名 | `move-file` | `std::fs::rename`，跨卷退回复制+删除 |
//!
//! ## 两条与上游的登记偏离
//!
//! 1. **`ConflictPolicy` 多两档**。上游只有 `overwrite: false`（撞名即 `EEXIST`）。
//!    这里加了 `Overwrite` 与 `KeepBoth`（顺延成 `名字 (2).ext`，见 [`unique_destination`]），
//!    因为漫画库里「解压到已有目录」「新建同名文件夹」都很常见。
//!    **默认仍是 `ConflictPolicy::Fail`，与上游一致**；`CreateDirectory` 固定走这一档
//!    （上游 `mkdir(recursive: false)` 撞名直接抛），要顺延的调用方自己先过
//!    [`unique_destination`]。
//! 2. **`ctime` 在 Windows 上取的是创建时间**。`std` 在 Windows 上不暴露
//!    POSIX 意义的 `ctime`，`device` / `inode` 也恒为 0。守卫比对的字段因此少两个，
//!    「目标被改过」的判定在 Windows 上略松 —— 这是可接受的方向（宁可多允许一次撤销，
//!    也不要因为取不到字段就把合法撤销判成 `ESTALE`）。
//!
//! ## 回收站的可撤销性是**平台能力**，不是常量
//!
//! `trash` crate 的 `list` / `restore_all` / `purge_all` 只对 Windows 与 Freedesktop
//! 有效（crate 里 `os_limited` 模块的 `cfg`）—— **macOS 上没有程序化恢复**。
//! 这与 neoview 的 `getTrashCapabilities().restore` 是同一件事，所以
//! [`FileMutationProvider::supports_restore`] 是运行时查询而不是 `cfg!` 常量：
//! UI 要靠它决定「撤销」这一项该不该出现。

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

mod backend;
mod batch;
mod copy;
mod error;
mod mutation;

pub use backend::*;
pub use batch::*;
pub use copy::*;
pub use error::*;
pub use mutation::*;

// ─────────────────────────────────────────────────────────────────────────────
// 命令与回执（对应 neoview types.ts 的 `FileMutation` / `FileUndoReceipt`）
// ─────────────────────────────────────────────────────────────────────────────

/// 冲突策略。默认 [`ConflictPolicy::Fail`]（= 上游的 `overwrite: false`）。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ConflictPolicy {
    /// 目标已存在就报 `EEXIST`，不动任何一边。**这是默认值，与上游一致。**
    #[default]
    Fail,
    /// 覆盖目标。
    Overwrite,
    /// 顺延到不撞名的名字（`名字 (2).ext`）。本项目的登记偏离。
    KeepBoth,
}

impl ConflictPolicy {
    pub fn overwrites(self) -> bool {
        matches!(self, Self::Overwrite)
    }
}

/// 一条文件变更。字段名与 neoview `FileMutation` 一一对应。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FileMutation {
    Copy {
        source_path: PathBuf,
        destination_path: PathBuf,
        conflict: ConflictPolicy,
    },
    Move {
        source_path: PathBuf,
        destination_path: PathBuf,
        conflict: ConflictPolicy,
    },
    /// 改名。上游要求**同目录**，否则报 `EXDEV`。
    Rename {
        source_path: PathBuf,
        destination_path: PathBuf,
        conflict: ConflictPolicy,
    },
    Delete {
        source_path: PathBuf,
    },
    Trash {
        source_path: PathBuf,
    },
    CreateDirectory {
        destination_path: PathBuf,
    },
}

impl FileMutation {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Copy { .. } => "copy",
            Self::Move { .. } => "move",
            Self::Rename { .. } => "rename",
            Self::Delete { .. } => "delete",
            Self::Trash { .. } => "trash",
            Self::CreateDirectory { .. } => "create-directory",
        }
    }

    pub fn source_path(&self) -> Option<&Path> {
        match self {
            Self::Copy { source_path, .. }
            | Self::Move { source_path, .. }
            | Self::Rename { source_path, .. }
            | Self::Delete { source_path }
            | Self::Trash { source_path } => Some(source_path),
            Self::CreateDirectory { .. } => None,
        }
    }
}

/// 撤销前的守卫快照。对应 neoview `FileMutationGuard`。
///
/// 撤销前必须重取一次快照并逐字段比对：中途被别的程序改过就不许撤销（`ESTALE`），
/// 否则「撤销」会变成一个会吃掉别人数据的操作。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileMutationGuard {
    pub path: PathBuf,
    /// `file` / `directory` / `symbolic-link` / `other`
    pub kind: &'static str,
    pub size: u64,
    pub mtime_ms: i64,
    pub ctime_ms: i64,
    /// Windows 上 `std` 不暴露卷号/文件号，恒为 0（登记偏离，见模块注释）。
    pub device: u64,
    pub inode: u64,
}

/// 回收站条目的回执。对应 neoview `RustTrashItemReceipt`。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrashItemReceipt {
    /// 平台专有标识。macOS 上列不了回收站，因此为 `None`。
    pub id: Option<String>,
    pub name: String,
    pub original_parent: PathBuf,
    pub time_deleted: i64,
}

/// 撤销回执。对应 neoview `FileUndoReceipt`。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileUndoReceipt {
    pub original: FileMutation,
    /// 逆操作。回收站那条走 [`TrashProviderData`] 而不是逆操作。
    pub inverse: FileMutation,
    pub guard: FileMutationGuard,
    pub trash_item: Option<TrashItemReceipt>,
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0)
}

// ─────────────────────────────────────────────────────────────────────────────
// 执行
// ─────────────────────────────────────────────────────────────────────────────

/// 路径存在与否（对应上游 `pathExists`）。只有 `ENOENT` 算「不存在」，
/// 其余 I/O 错误照原样抛出 —— 把 `EACCES` 当成「不存在」会导致误覆盖。
fn path_exists(path: &Path) -> FileOpResult<bool> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(FileOpError::from_io(error, path)),
    }
}

/// 取守卫快照。
pub fn snapshot(path: &Path) -> FileOpResult<FileMutationGuard> {
    let metadata = fs::symlink_metadata(path).map_err(|error| FileOpError::from_io(error, path))?;
    let file_type = metadata.file_type();
    let kind = if file_type.is_symlink() {
        "symbolic-link"
    } else if file_type.is_dir() {
        "directory"
    } else if file_type.is_file() {
        "file"
    } else {
        "other"
    };
    let (mtime_ms, ctime_ms) = times_ms(&metadata);
    let (device, inode) = device_inode(&metadata);
    Ok(FileMutationGuard {
        path: path.to_path_buf(),
        kind,
        size: metadata.len(),
        mtime_ms,
        ctime_ms,
        device,
        inode,
    })
}

fn times_ms(metadata: &fs::Metadata) -> (i64, i64) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        (metadata.mtime() * 1000, metadata.ctime() * 1000)
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        // 先转 i64 再做减法：文件系统不支持时间时 FILETIME 为 0，按 u64 减常量会下溢。
        let mtime = metadata.last_write_time() as i64 / 10_000 - 11_644_473_600_000;
        let ctime = metadata.creation_time() as i64 / 10_000 - 11_644_473_600_000;
        (mtime, ctime)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = metadata;
        (0, 0)
    }
}

fn device_inode(metadata: &fs::Metadata) -> (u64, u64) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        (metadata.dev(), metadata.ino())
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        (0, 0)
    }
}

fn same_guard(left: &FileMutationGuard, right: &FileMutationGuard) -> bool {
    left.kind == right.kind
        && left.size == right.size
        && left.mtime_ms == right.mtime_ms
        && left.ctime_ms == right.ctime_ms
        && left.device == right.device
        && left.inode == right.inode
}

/// 删掉一个路径，不管它是文件、目录还是符号链接。
///
/// **符号链接必须先判**：`symlink_metadata` 对链接本身报的是链接，
/// 而 `remove_dir_all` 会顺着链接把目标目录里的东西删掉。
pub fn remove_at(path: &Path) -> FileOpResult<()> {
    let metadata = fs::symlink_metadata(path).map_err(|error| FileOpError::from_io(error, path))?;
    let outcome = if metadata.file_type().is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    };
    outcome.map_err(|error| FileOpError::from_io(error, path))
}

/// Windows 上「只改大小写」的改名。
///
/// 上游 `isWindowsCaseOnlyRename` 特判它，因为此时目标「已存在」是假象
/// （大小写不敏感的文件系统认得的还是同一个条目），走存在性检查会把合法改名判成 `EEXIST`。
fn is_windows_case_only_rename(source: &Path, destination: &Path) -> bool {
    if !cfg!(windows) {
        return false;
    }
    let source = normalize_for_compare(source);
    let destination = normalize_for_compare(destination);
    source != destination && source.to_lowercase() == destination.to_lowercase()
}

fn normalize_for_compare(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn same_parent(source: &Path, destination: &Path) -> bool {
    match (source.parent(), destination.parent()) {
        (Some(left), Some(right)) => left == right,
        (None, None) => true,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// 假的回收站：把「被扔掉」的项记在内存里，并把它们从原位置挪进一个影子目录。
    ///
    /// 真的回收站不能用在这里：它会往**用户的回收站**里写东西，而单元测试
    /// 不该有那种副作用。真后端的行为由 `system_trash_backend_really_removes_the_path`
    /// 单独验（那条会自己清理）。
    struct FakeTrashBackend {
        session: tempfile::TempDir,
        items: Mutex<Vec<(TrashItemReceipt, PathBuf)>>,
    }

    impl FakeTrashBackend {
        fn new() -> Self {
            Self {
                session: tempfile::TempDir::new().unwrap(),
                items: Mutex::new(Vec::new()),
            }
        }
    }

    impl TrashBackend for FakeTrashBackend {
        fn trash(&self, path: &Path) -> FileOpResult<TrashItemReceipt> {
            let name = path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default();
            let held = self
                .session
                .path()
                .join(format!("held-{}", self.items.lock().unwrap().len()));
            fs::rename(path, &held).map_err(|error| FileOpError::from_io(error, path))?;
            let item = TrashItemReceipt {
                id: Some(format!("fake:{name}")),
                name: name.clone(),
                original_parent: path.parent().map(Path::to_path_buf).unwrap_or_default(),
                time_deleted: now_secs(),
            };
            self.items.lock().unwrap().push((item.clone(), held));
            Ok(item)
        }

        fn supports_restore(&self) -> bool {
            true
        }

        fn restore(&self, item: &TrashItemReceipt) -> FileOpResult<()> {
            let mut items = self.items.lock().unwrap();
            let position = items
                .iter()
                .position(|(candidate, _)| candidate.id == item.id)
                .ok_or_else(|| FileOpError::new("ENOENT", "假的回收站里没有这一项"))?;
            let (_, held) = items.remove(position);
            let original = item.original_parent.join(&item.name);
            fs::rename(&held, &original).map_err(|error| FileOpError::from_io(error, &original))
        }

        fn list(&self) -> FileOpResult<Vec<TrashItemReceipt>> {
            Ok(self
                .items
                .lock()
                .unwrap()
                .iter()
                .map(|(item, _)| item.clone())
                .collect())
        }
    }

    struct Fixture {
        temp: tempfile::TempDir,
        backend: FakeTrashBackend,
    }

    impl Fixture {
        fn new() -> Self {
            Self {
                temp: tempfile::TempDir::new().unwrap(),
                backend: FakeTrashBackend::new(),
            }
        }

        fn path(&self, name: &str) -> PathBuf {
            self.temp.path().join(name)
        }

        fn write(&self, name: &str, content: &str) -> PathBuf {
            let path = self.path(name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(&path, content).unwrap();
            path
        }

        fn dir(&self, name: &str) -> PathBuf {
            let path = self.path(name);
            fs::create_dir_all(&path).unwrap();
            path
        }

        fn copy(
            &self,
            source: &Path,
            destination: &Path,
            conflict: ConflictPolicy,
        ) -> FileOpResult<Option<FileUndoReceipt>> {
            execute_mutation(
                &FileMutation::Copy {
                    source_path: source.to_path_buf(),
                    destination_path: destination.to_path_buf(),
                    conflict,
                },
                &self.backend,
                true,
            )
        }
    }

    fn read(path: &Path) -> String {
        fs::read_to_string(path).unwrap()
    }

    #[test]
    fn copy_fails_with_eexist_and_leaves_both_sides_untouched() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "new");
        let destination = fixture.write("b.txt", "old");

        let error = fixture
            .copy(&source, &destination, ConflictPolicy::Fail)
            .unwrap_err();
        assert_eq!(error.code, "EEXIST");
        // 负例的重点：失败之后**两边都必须还是原样**，不能出现「覆盖了一半」。
        assert_eq!(read(&source), "new");
        assert_eq!(read(&destination), "old");
    }

    #[test]
    fn copy_with_overwrite_replaces_and_reports_no_undo() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "new");
        let destination = fixture.write("b.txt", "old");

        let receipt = fixture
            .copy(&source, &destination, ConflictPolicy::Overwrite)
            .unwrap();
        assert_eq!(read(&destination), "new");
        // 覆盖掉别人的文件之后不许再生成回执：撤销它等于删掉用户原有的东西。
        assert!(receipt.is_none(), "覆盖场景不该给出撤销回执");
    }

    #[test]
    fn copy_with_keep_both_renames_the_newcomer() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "new");
        let destination = fixture.write("b.txt", "old");

        fixture
            .copy(&source, &destination, ConflictPolicy::KeepBoth)
            .unwrap();
        assert_eq!(read(&destination), "old");
        assert_eq!(read(&fixture.path("b (2).txt")), "new");
    }

    #[test]
    fn copy_directory_is_recursive_and_preserves_the_tree() {
        let fixture = Fixture::new();
        let source = fixture.dir("comic");
        fs::create_dir_all(source.join("chapter-1")).unwrap();
        fs::write(source.join("chapter-1/001.png"), b"png-1").unwrap();
        fs::write(source.join("cover.png"), b"png-cover").unwrap();

        let destination = fixture.path("copy");
        fixture
            .copy(&source, &destination, ConflictPolicy::Fail)
            .unwrap();

        assert_eq!(
            fs::read(destination.join("chapter-1/001.png")).unwrap(),
            b"png-1"
        );
        assert_eq!(
            fs::read(destination.join("cover.png")).unwrap(),
            b"png-cover"
        );
    }

    #[test]
    fn move_across_the_same_volume_removes_the_source() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "body");
        let destination = fixture.path("b.txt");

        execute_mutation(
            &FileMutation::Move {
                source_path: source.clone(),
                destination_path: destination.clone(),
                conflict: ConflictPolicy::Fail,
            },
            &fixture.backend,
            true,
        )
        .unwrap();

        assert!(!source.exists());
        assert_eq!(read(&destination), "body");
    }

    #[test]
    fn rename_requires_the_same_directory() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "x");
        let destination = fixture.path("other/a.txt");

        let error = execute_mutation(
            &FileMutation::Rename {
                source_path: source,
                destination_path: destination,
                conflict: ConflictPolicy::Fail,
            },
            &fixture.backend,
            true,
        )
        .unwrap_err();
        assert_eq!(error.code, "EXDEV");
    }

    #[test]
    fn create_directory_refuses_an_existing_name_and_keep_both_advances() {
        let fixture = Fixture::new();
        let destination = fixture.dir("新建文件夹");

        let error = execute_mutation(
            &FileMutation::CreateDirectory {
                destination_path: destination.clone(),
            },
            &fixture.backend,
            true,
        )
        .unwrap_err();
        assert_eq!(error.code, "EEXIST");

        // `unique_destination` 是登记偏离的落点：上游这里只有「撞名即失败」，
        // 而漫画库里「新建文件夹」连点两次非常常见，顺延比报错合理。
        // 注意顺延由**调用方**决定，`FileMutation::CreateDirectory` 本身固定按 Fail 走。
        let unique = unique_destination(&destination);
        assert_eq!(unique, fixture.path("新建文件夹 (2)"));
        fs::create_dir(&unique).unwrap();
        assert!(unique.is_dir());
    }

    #[test]
    fn trash_and_permanent_delete_are_not_the_same_operation() {
        let fixture = Fixture::new();
        let trashed = fixture.write("trash-me.txt", "x");
        let deleted = fixture.write("delete-me.txt", "x");

        let receipt = execute_mutation(
            &FileMutation::Trash {
                source_path: trashed.clone(),
            },
            &fixture.backend,
            true,
        )
        .unwrap();

        // 回收站：两个路径都不在原位置了，但**留下了回执**。
        assert!(!trashed.exists());
        let receipt = receipt.expect("回收站必须给回执");
        assert!(receipt.trash_item.is_some());
        assert_eq!(fixture.backend.list().unwrap().len(), 1);

        // 永久删除：同样消失，但**没有回执、回收站里也不多东西**。
        let permanent = execute_mutation(
            &FileMutation::Delete {
                source_path: deleted.clone(),
            },
            &fixture.backend,
            true,
        )
        .unwrap();
        assert!(!deleted.exists());
        assert!(permanent.is_none());
        assert_eq!(
            fixture.backend.list().unwrap().len(),
            1,
            "永久删除不该往回收站里放东西"
        );
    }

    #[test]
    fn undo_restores_a_trashed_file() {
        let fixture = Fixture::new();
        let source = fixture.write("book.cbz", "pages");
        let receipt = execute_mutation(
            &FileMutation::Trash {
                source_path: source.clone(),
            },
            &fixture.backend,
            true,
        )
        .unwrap()
        .unwrap();
        assert!(!source.exists());

        undo_mutation(&receipt, &fixture.backend).unwrap();
        assert_eq!(read(&source), "pages");
        assert!(fixture.backend.list().unwrap().is_empty());
    }

    /// 守卫的意义：撤销目标在中途被改过就不许撤销，否则「撤销」会吃掉别人的数据。
    #[test]
    fn undo_refuses_when_the_target_changed_since_the_operation() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "body");
        let destination = fixture.path("b.txt");
        let receipt = fixture
            .copy(&source, &destination, ConflictPolicy::Fail)
            .unwrap()
            .unwrap();

        // 别人在这之后动了目标文件。
        fs::write(&destination, "somebody else's longer body").unwrap();

        let error = undo_mutation(&receipt, &fixture.backend).unwrap_err();
        assert_eq!(error.code, "ESTALE");
        assert_eq!(read(&destination), "somebody else's longer body");
    }

    #[test]
    fn undo_moves_a_moved_file_back() {
        let fixture = Fixture::new();
        let source = fixture.write("a.txt", "body");
        let destination = fixture.path("b.txt");
        let receipt = execute_mutation(
            &FileMutation::Move {
                source_path: source.clone(),
                destination_path: destination.clone(),
                conflict: ConflictPolicy::Fail,
            },
            &fixture.backend,
            true,
        )
        .unwrap()
        .unwrap();

        undo_mutation(&receipt, &fixture.backend).unwrap();
        assert_eq!(read(&source), "body");
        assert!(!destination.exists());
    }

    #[test]
    fn batch_stops_at_the_first_failure_and_marks_the_rest_cancelled() {
        let fixture = Fixture::new();
        let first = fixture.write("one.txt", "1");
        let second = fixture.write("two.txt", "2");

        let mutations = vec![
            FileMutation::Trash {
                source_path: first.clone(),
            },
            // 这一条必然失败：源不存在。
            FileMutation::Trash {
                source_path: fixture.path("missing.txt"),
            },
            FileMutation::Trash {
                source_path: second.clone(),
            },
        ];
        let batch = run_batch(&mutations, &fixture.backend, &AtomicBool::new(false));

        assert_eq!(batch.succeeded, 1);
        assert_eq!(batch.failed, 1);
        assert_eq!(
            batch.cancelled, 1,
            "失败之后的条目要标 cancelled，不是继续硬做"
        );
        assert!(!first.exists());
        assert!(
            second.exists(),
            "第三条必须**原样还在**：半批已删是验收里最不能接受的形态"
        );
    }

    #[test]
    fn batch_honours_cancellation_before_starting_the_next_item() {
        let fixture = Fixture::new();
        let mut mutations = Vec::new();
        for index in 0..5 {
            mutations.push(FileMutation::Trash {
                source_path: fixture.write(&format!("f{index}.txt"), "x"),
            });
        }

        // 头一条之前就取消 ⇒ 一条都不该动。
        let cancelled = AtomicBool::new(true);
        let batch = run_batch(&mutations, &fixture.backend, &cancelled);
        assert_eq!(batch.succeeded, 0);
        assert_eq!(batch.cancelled, 5);
        for mutation in &mutations {
            assert!(mutation.source_path().unwrap().exists());
        }
    }

    #[test]
    fn batch_undo_returns_every_thrashed_path() {
        let fixture = Fixture::new();
        let sources: Vec<PathBuf> = (0..3)
            .map(|index| fixture.write(&format!("f{index}.txt"), "body"))
            .collect();
        let mutations: Vec<FileMutation> = sources
            .iter()
            .map(|source| FileMutation::Trash {
                source_path: source.clone(),
            })
            .collect();

        let batch = run_batch(&mutations, &fixture.backend, &AtomicBool::new(false));
        assert_eq!(batch.succeeded, 3);
        assert_eq!(batch.undoable, 3);

        let undo = undo_batch(&batch.undo_receipts, &fixture.backend);
        assert_eq!(undo.succeeded, 3);
        for source in &sources {
            assert_eq!(read(source), "body");
        }
    }

    #[test]
    fn summary_says_how_many_failed_not_only_how_many_succeeded() {
        let batch = FileOperationBatchResult {
            succeeded: 3,
            failed: 1,
            cancelled: 2,
            ..Default::default()
        };
        assert_eq!(batch.summary("已复制"), "已复制 3 项，1 项失败，2 项已取消");

        let clean = FileOperationBatchResult {
            succeeded: 4,
            ..Default::default()
        };
        assert_eq!(clean.summary("已删除"), "已删除 4 项");
    }

    #[test]
    fn error_codes_map_from_io_kinds() {
        assert_eq!(
            error_code_of(&io::Error::new(io::ErrorKind::NotFound, "x")),
            "ENOENT"
        );
        assert_eq!(
            error_code_of(&io::Error::new(io::ErrorKind::AlreadyExists, "x")),
            "EEXIST"
        );
        assert_eq!(
            error_code_of(&io::Error::new(io::ErrorKind::PermissionDenied, "x")),
            "EACCES"
        );
        assert_eq!(
            error_code_of(&io::Error::new(io::ErrorKind::CrossesDevices, "x")),
            "EXDEV"
        );
    }

    #[test]
    fn guard_snapshot_tracks_size_and_kind() {
        let fixture = Fixture::new();
        let file = fixture.write("a.txt", "12345");
        let directory = fixture.dir("book");

        let file_guard = snapshot(&file).unwrap();
        assert_eq!(file_guard.kind, "file");
        assert_eq!(file_guard.size, 5);
        assert_eq!(file_guard.path, file);

        let dir_guard = snapshot(&directory).unwrap();
        assert_eq!(dir_guard.kind, "directory");

        let error = snapshot(&fixture.path("nope")).unwrap_err();
        assert_eq!(error.code, "ENOENT");
    }

    #[test]
    fn destination_resolution_prefers_fail_by_default() {
        assert_eq!(ConflictPolicy::default(), ConflictPolicy::Fail);
        assert!(!ConflictPolicy::Fail.overwrites());
        assert!(ConflictPolicy::Overwrite.overwrites());
    }

    /// 真的回收站后端。**会往用户回收站里写东西**，所以自己收尾：
    /// 验完立刻按平台能力清掉（macOS 用 `std::fs` 直删刚进去的那一项）。
    #[test]
    fn system_trash_backend_really_removes_the_path() {
        let temp = tempfile::TempDir::new().unwrap();
        // 名字带进程号与随机后缀，便于在回收站里精确找回并清理。
        let name = format!("rossi-trash-probe-{}-{}", std::process::id(), now_secs());
        let path = temp.path().join(&name);
        fs::write(&path, "probe").unwrap();

        let backend = SystemTrashBackend::new();
        let item = backend.trash(&path).expect("移入回收站应成功");

        // 正向断言：原路径真的没了（只断言「没报错」是空转）。
        assert!(!path.exists(), "移入回收站后原路径必须消失");
        assert_eq!(item.name, name);
        assert_eq!(
            item.original_parent.file_name(),
            temp.path().file_name(),
            "回收站回执要记得它原来在哪个目录下"
        );

        // 收尾：能程序化恢复的平台直接恢复；不能的（macOS）从回收站目录里删掉。
        if backend.supports_restore() {
            backend.restore(&item).expect("恢复应成功");
            assert!(path.exists(), "恢复之后原路径必须回来");
        } else {
            let _ = cleanup_probe_in_system_trash(&name);
        }

        // 无论走哪条路，临时目录都不该留下这个文件。
        assert!(!path.exists());
    }

    /// 在常见回收站目录里找一个探针文件并删掉。找不到就返回 `false`（不算失败：
    /// 有的平台会把回收站放在别处，测试不该因此判红）。
    fn cleanup_probe_in_system_trash(name: &str) -> bool {
        let mut roots: Vec<PathBuf> = Vec::new();
        if let Some(home) = std::env::var_os("HOME") {
            let home = PathBuf::from(home);
            roots.push(home.join(".Trash")); // macOS
            roots.push(home.join(".local/share/Trash/files")); // Freedesktop
        }
        if let Some(data_home) = std::env::var_os("XDG_DATA_HOME") {
            roots.push(PathBuf::from(data_home).join("Trash/files"));
        }
        for root in roots {
            let candidate = root.join(name);
            if candidate.exists() {
                let _ = remove_at(&candidate);
                return true;
            }
        }
        false
    }

    /// 顺序稳定性：`run_batch` 的 `results` 下标必须与输入一一对应，
    /// UI 要靠它把失败项映射回列表里的那一行。
    #[test]
    fn batch_results_keep_the_input_order() {
        let fixture = Fixture::new();
        let mutations: Vec<FileMutation> = (0..4)
            .map(|index| FileMutation::Trash {
                source_path: fixture.write(&format!("f{index}.txt"), "x"),
            })
            .collect();
        let batch = run_batch(&mutations, &fixture.backend, &AtomicBool::new(false));
        let indices: Vec<usize> = batch.results.iter().map(|result| result.index).collect();
        assert_eq!(indices, vec![0, 1, 2, 3]);
        assert!(batch.results.iter().all(FileOperationResult::is_succeeded));
    }
}
