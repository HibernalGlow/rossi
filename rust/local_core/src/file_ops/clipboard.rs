//! 两步式目录剪贴板：剪切 / 复制 → 粘贴。
//!
//! 逐行对齐 neoview 的 `FolderClipboard.tsx` + `services-contract` 里的
//! `prepareDirectoryClipboard` / `pasteDirectoryClipboard`：
//!
//! - **两步式**，不是「点了就动」。剪切/复制只记下来源与模式，粘贴时才落盘；
//! - `move` 模式粘贴后剪贴板自动清空（`FolderClipboard.tsx:117`），
//!   `copy` 模式保留，好让人连着粘到好几个目录；
//! - 重名**不做自动序号、不做询问、不做覆盖**，就是一条 `EEXIST` 失败项
//!   （上游 `overwrite: false`，且 UI 不传 `overwrite`）。
//!
//! 剪贴板是**会话内**的：与应用生命周期同寿，不落盘。跨重启保留「待粘贴」这种状态
//! 会让「我以为已经粘好了」变成一个无法验证的猜测。

use std::path::{Path, PathBuf};

use super::execute::{ConflictPolicy, FileMutation, FileOpError, FileOpResult};

/// 剪切还是复制。对应上游 `mode: "copy" | "move"`。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClipboardMode {
    Copy,
    Move,
}

impl ClipboardMode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Copy => "copy",
            Self::Move => "move",
        }
    }
}

/// 剪贴板快照，给 UI 决定「粘贴」这一项该不该亮。对应上游
/// `{ available, mode, generation, total, createdAt }`。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DirectoryClipboardSnapshot {
    pub available: bool,
    pub mode: ClipboardMode,
    pub generation: u64,
    pub total: usize,
    pub created_at: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DirectoryClipboard {
    mode: ClipboardMode,
    sources: Vec<PathBuf>,
    generation: u64,
    created_at: i64,
}

impl DirectoryClipboard {
    pub fn new(mode: ClipboardMode, sources: Vec<PathBuf>, generation: u64) -> Self {
        Self {
            mode,
            sources,
            generation,
            created_at: now_secs(),
        }
    }

    pub fn mode(&self) -> ClipboardMode {
        self.mode
    }

    pub fn sources(&self) -> &[PathBuf] {
        &self.sources
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn is_empty(&self) -> bool {
        self.sources.is_empty()
    }

    pub fn len(&self) -> usize {
        self.sources.len()
    }

    pub fn snapshot(&self) -> DirectoryClipboardSnapshot {
        DirectoryClipboardSnapshot {
            available: !self.sources.is_empty(),
            mode: self.mode,
            generation: self.generation,
            total: self.sources.len(),
            created_at: self.created_at,
        }
    }

    pub fn clear(&mut self) {
        self.sources.clear();
    }

    /// `move` 模式粘贴之后清空；`copy` 模式留着。
    pub fn clear_if_move(&mut self) {
        if self.mode == ClipboardMode::Move {
            self.clear();
        }
    }

    /// 把「粘贴到 `destination_dir`」摊成一批变更。
    ///
    /// 只构造不执行 —— 执行与取消由 [`super::execute::run_batch`] 负责，
    /// 这样「粘贴」与「拖拽移动」走的是同一条执行路径。
    pub fn paste_mutations(
        &self,
        destination_dir: &Path,
        conflict: ConflictPolicy,
    ) -> Vec<FileMutation> {
        self.sources
            .iter()
            .filter_map(|source| {
                let name = source.file_name()?;
                let destination_path = destination_dir.join(name);
                Some(match self.mode {
                    ClipboardMode::Copy => FileMutation::Copy {
                        source_path: source.clone(),
                        destination_path,
                        conflict,
                    },
                    ClipboardMode::Move => FileMutation::Move {
                        source_path: source.clone(),
                        destination_path,
                        conflict,
                    },
                })
            })
            .collect()
    }
}

/// 粘贴前的合法性检查。
///
/// 两条真正的坑，都不是「同名」那种能靠一次失败说清的：
/// 1. **把目录粘进它自己的子孙里** —— 递归复制会一直造下去，`move` 更是直接把源挪走；
/// 2. **`move` 粘到原目录** —— 源和目标是同一个路径，一次「什么都没发生」的失败。
///
/// 返回第一条不合法的原因，让 UI 能在动手之前拦住。空 `sources` 不算错误
/// （「粘贴」本身就该是禁用的，那是 UI 的事）。
pub fn validate_paste(
    sources: &[PathBuf],
    destination_dir: &Path,
    mode: ClipboardMode,
) -> FileOpResult<()> {
    for source in sources {
        if is_under(destination_dir, source) {
            return Err(FileOpError::new(
                "EINVAL",
                format!(
                    "不能把目录粘进它自己的子目录: {} → {}",
                    source.display(),
                    destination_dir.display()
                ),
            ));
        }
        if mode == ClipboardMode::Move && source.parent() == Some(destination_dir) {
            return Err(FileOpError::new(
                "EEXIST",
                format!("这一项已经在这个目录里了: {}", source.display()),
            ));
        }
    }
    Ok(())
}

/// `path` 是否位于 `ancestor` 之下（含 `ancestor` 自身）。
pub fn is_under(path: &Path, ancestor: &Path) -> bool {
    let mut current = Some(path);
    while let Some(candidate) = current {
        if candidate == ancestor {
            return true;
        }
        current = candidate.parent();
    }
    false
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

    fn source(name: &str) -> PathBuf {
        PathBuf::from("/library").join(name)
    }

    #[test]
    fn copy_paste_keeps_the_clipboard_but_move_paste_clears_it() {
        let mut copy =
            DirectoryClipboard::new(ClipboardMode::Copy, vec![source("a"), source("b")], 1);
        copy.clear_if_move();
        assert_eq!(copy.len(), 2, "复制模式要留住剪贴板，好连着粘到几个目录");

        let mut cut =
            DirectoryClipboard::new(ClipboardMode::Move, vec![source("a"), source("b")], 1);
        cut.clear_if_move();
        assert!(cut.is_empty(), "剪切粘完就不再是「待粘贴」了");
        assert!(!cut.snapshot().available);
    }

    #[test]
    fn paste_mutations_target_the_destination_directory_with_the_original_names() {
        let clipboard = DirectoryClipboard::new(
            ClipboardMode::Copy,
            vec![source("comic-a"), source("comic-b")],
            1,
        );
        let mutations = clipboard.paste_mutations(Path::new("/target"), ConflictPolicy::Fail);
        assert_eq!(mutations.len(), 2);
        assert_eq!(
            mutations[0],
            FileMutation::Copy {
                source_path: source("comic-a"),
                destination_path: PathBuf::from("/target/comic-a"),
                conflict: ConflictPolicy::Fail,
            }
        );
        // 步骤名与上游一致：mutation 的 kind 就是 copy / move。
        assert_eq!(mutations[0].kind(), "copy");
    }

    #[test]
    fn move_clipboard_produces_move_mutations() {
        let clipboard = DirectoryClipboard::new(ClipboardMode::Move, vec![source("a")], 1);
        let mutations = clipboard.paste_mutations(Path::new("/target"), ConflictPolicy::Fail);
        assert_eq!(mutations[0].kind(), "move");
    }

    #[test]
    fn validate_rejects_pasting_a_directory_into_its_own_descendant() {
        let error = validate_paste(
            &[PathBuf::from("/library/comic")],
            Path::new("/library/comic/chapter-1"),
            ClipboardMode::Copy,
        )
        .unwrap_err();
        assert_eq!(error.code, "EINVAL");
    }

    #[test]
    fn validate_rejects_moving_into_the_directory_it_already_lives_in() {
        // 复制到原目录是合法但不常用；移动过去则是一次必然失败的「什么都没发生」。
        assert!(
            validate_paste(
                &[PathBuf::from("/library/comic")],
                Path::new("/library"),
                ClipboardMode::Copy
            )
            .is_ok()
        );
        let error = validate_paste(
            &[PathBuf::from("/library/comic")],
            Path::new("/library"),
            ClipboardMode::Move,
        )
        .unwrap_err();
        assert_eq!(error.code, "EEXIST");
    }

    #[test]
    fn validate_allows_a_normal_move_between_directories() {
        assert!(
            validate_paste(
                &[PathBuf::from("/library/a"), PathBuf::from("/library/b")],
                Path::new("/library/shelf"),
                ClipboardMode::Move
            )
            .is_ok()
        );
    }

    #[test]
    fn is_under_is_inclusive_on_the_ancestor_itself() {
        assert!(is_under(Path::new("/a/b/c"), Path::new("/a")));
        assert!(is_under(Path::new("/a"), Path::new("/a")));
        assert!(!is_under(Path::new("/a"), Path::new("/a/b")));
        assert!(!is_under(Path::new("/ab"), Path::new("/a")));
    }

    #[test]
    fn snapshot_reports_what_the_ui_needs_to_enable_paste() {
        let empty = DirectoryClipboard::new(ClipboardMode::Copy, Vec::new(), 7);
        assert!(!empty.snapshot().available);

        let filled = DirectoryClipboard::new(ClipboardMode::Move, vec![source("a")], 7);
        let snapshot = filled.snapshot();
        assert!(snapshot.available);
        assert_eq!(snapshot.mode, ClipboardMode::Move);
        assert_eq!(snapshot.total, 1);
        assert_eq!(snapshot.generation, 7);
    }
}
