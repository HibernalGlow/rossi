//! 执行一条 `FileMutation`，并生成可撤销的回执。

use super::*;

/// 移动。先试 `rename`（同卷上是 O(1) 的元数据操作），跨卷则退回复制 + 删除。
///
/// 上游用 `move-file`，它做的正是这件事（`EXDEV` → `cp` + `rm`）。
pub fn move_entry(source: &Path, destination: &Path) -> FileOpResult<()> {
    match fs::rename(source, destination) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::CrossesDevices => {
            copy_tree(source, destination)?;
            remove_at(source)
        }
        Err(error) => Err(FileOpError::from_io(error, destination)),
    }
}

/// 「名字 (2).ext」式顺延。Breeze 的下载链路已经在用这个约定。
pub fn unique_destination(destination: &Path) -> PathBuf {
    if !destination.exists() {
        return destination.to_path_buf();
    }
    let parent = destination.parent().map(Path::to_path_buf);
    let stem = destination
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_default();
    let extension = destination
        .extension()
        .map(|extension| extension.to_string_lossy().into_owned());
    for index in 2..10_000u32 {
        let name = match &extension {
            Some(extension) => format!("{stem} ({index}).{extension}"),
            None => format!("{stem} ({index})"),
        };
        let candidate = match &parent {
            Some(parent) => parent.join(name),
            None => PathBuf::from(name),
        };
        if !candidate.exists() {
            return candidate;
        }
    }
    destination.to_path_buf()
}

/// 按冲突策略把目标定下来。
///
/// 返回 `(最终目标, 目标原本是否已存在)`。第二个值决定「这次操作能不能撤销」——
/// 上游也是这么用的（覆盖了别人的东西就不该把「撤销」做成「删掉它」）。
fn resolve_destination(
    destination: &Path,
    conflict: ConflictPolicy,
) -> FileOpResult<(PathBuf, bool)> {
    let existed = path_exists(destination)?;
    match conflict {
        ConflictPolicy::Fail => {
            if existed {
                return Err(FileOpError::exists(destination));
            }
            Ok((destination.to_path_buf(), false))
        }
        ConflictPolicy::Overwrite => {
            if existed {
                remove_at(destination)?;
            }
            Ok((destination.to_path_buf(), existed))
        }
        ConflictPolicy::KeepBoth => {
            if existed {
                let unique = unique_destination(destination);
                Ok((unique, false))
            } else {
                Ok((destination.to_path_buf(), false))
            }
        }
    }
}

/// 执行一条变更。
///
/// 与 neoview `PlatformFileMutationProvider.#execute` 逐分支对应。
/// `create_undo` 为假时只做副作用、不生成回执（撤销本身走的就是这条路）。
pub fn execute_mutation(
    mutation: &FileMutation,
    backend: &dyn TrashBackend,
    create_undo: bool,
) -> FileOpResult<Option<FileUndoReceipt>> {
    match mutation {
        FileMutation::Copy {
            source_path,
            destination_path,
            conflict,
        } => {
            let (destination, existed) = resolve_destination(destination_path, *conflict)?;
            copy_tree(source_path, &destination)?;
            if create_undo && !existed {
                Ok(Some(FileUndoReceipt {
                    original: mutation.clone(),
                    inverse: FileMutation::Delete {
                        source_path: destination.clone(),
                    },
                    guard: snapshot(&destination)?,
                    trash_item: None,
                }))
            } else {
                Ok(None)
            }
        }
        FileMutation::Move {
            source_path,
            destination_path,
            conflict,
        } => {
            let (destination, existed) = resolve_destination(destination_path, *conflict)?;
            move_entry(source_path, &destination)?;
            if create_undo && !existed {
                Ok(Some(FileUndoReceipt {
                    original: mutation.clone(),
                    inverse: FileMutation::Move {
                        source_path: destination.clone(),
                        destination_path: source_path.clone(),
                        conflict: ConflictPolicy::Fail,
                    },
                    guard: snapshot(&destination)?,
                    trash_item: None,
                }))
            } else {
                Ok(None)
            }
        }
        FileMutation::Rename {
            source_path,
            destination_path,
            conflict,
        } => {
            if !same_parent(source_path, destination_path) {
                return Err(FileOpError::new(
                    "EXDEV",
                    format!(
                        "改名要求源与目标同目录: {} → {}",
                        source_path.display(),
                        destination_path.display()
                    ),
                ));
            }
            let case_only = is_windows_case_only_rename(source_path, destination_path);
            // 只改大小写时「目标已存在」是假象，跳过检查与删除。
            let (destination, existed) = if case_only {
                (destination_path.clone(), false)
            } else {
                resolve_destination(destination_path, *conflict)?
            };
            fs::rename(source_path, &destination)
                .map_err(|error| FileOpError::from_io(error, source_path))?;
            if create_undo && !existed {
                Ok(Some(FileUndoReceipt {
                    original: mutation.clone(),
                    inverse: FileMutation::Rename {
                        source_path: destination.clone(),
                        destination_path: source_path.clone(),
                        conflict: ConflictPolicy::Fail,
                    },
                    guard: snapshot(&destination)?,
                    trash_item: None,
                }))
            } else {
                Ok(None)
            }
        }
        FileMutation::Delete { source_path } => {
            remove_at(source_path)?;
            Ok(None)
        }
        FileMutation::Trash { source_path } => {
            // 先取守卫再扔：扔完原路径就没了，取不到快照。
            let guard = snapshot(source_path)?;
            let item = backend.trash(source_path)?;
            if create_undo && backend.supports_restore() {
                Ok(Some(FileUndoReceipt {
                    original: mutation.clone(),
                    inverse: mutation.clone(),
                    guard,
                    trash_item: Some(item),
                }))
            } else {
                Ok(None)
            }
        }
        FileMutation::CreateDirectory { destination_path } => {
            let (destination, _) = resolve_destination(destination_path, ConflictPolicy::Fail)?;
            fs::create_dir(&destination)
                .map_err(|error| FileOpError::from_io(error, &destination))?;
            if create_undo {
                Ok(Some(FileUndoReceipt {
                    original: mutation.clone(),
                    inverse: FileMutation::Delete {
                        source_path: destination.clone(),
                    },
                    guard: snapshot(&destination)?,
                    trash_item: None,
                }))
            } else {
                Ok(None)
            }
        }
    }
}

/// 撤销一条回执。对应 neoview `PlatformFileMutationProvider.undo`。
///
/// 顺序很重要：**先校验守卫再动手**。先删后校验等于把「撤销」做成「无条件删除」。
pub fn undo_mutation(receipt: &FileUndoReceipt, backend: &dyn TrashBackend) -> FileOpResult<()> {
    if let Some(item) = &receipt.trash_item {
        if !backend.supports_restore() {
            return Err(FileOpError::unsupported("这个平台上没有程序化的回收站恢复"));
        }
        let original = receipt
            .original
            .source_path()
            .ok_or_else(|| FileOpError::unsupported("回收站回执缺少原路径"))?;
        if path_exists(original)? {
            return Err(FileOpError::stale(original));
        }
        return backend.restore(item);
    }

    let current = snapshot(&receipt.guard.path)?;
    if !same_guard(&current, &receipt.guard) {
        return Err(FileOpError::stale(&receipt.guard.path));
    }
    execute_mutation(&receipt.inverse, backend, false).map(|_| ())
}
