//! 递归复制（不跟进符号链接）。

use super::*;

/// 递归复制，**保留符号链接**（按链接复制，不跟进去）。
///
/// 上游用 `cp(recursive: true)` 且没开 `dereference`，语义一致。
/// 不跟进链接同时消掉了「复制一个指向自己祖先的链接」导致无限递归的可能。
pub fn copy_tree(source: &Path, destination: &Path) -> FileOpResult<()> {
    let metadata =
        fs::symlink_metadata(source).map_err(|error| FileOpError::from_io(error, source))?;
    let file_type = metadata.file_type();

    if file_type.is_symlink() {
        return copy_symlink(source, destination);
    }

    if file_type.is_dir() {
        // 不用 `create_dir_all`：父目录由调用方保证存在，这里少创建一个父目录
        // 就等于少一次「用户没要的目录被悄悄造出来」。
        fs::create_dir(destination).map_err(|error| FileOpError::from_io(error, destination))?;
        let entries = fs::read_dir(source).map_err(|error| FileOpError::from_io(error, source))?;
        for entry in entries {
            let entry = entry.map_err(|error| FileOpError::from_io(error, source))?;
            copy_tree(&entry.path(), &destination.join(entry.file_name()))?;
        }
        return Ok(());
    }

    fs::copy(source, destination).map_err(|error| FileOpError::from_io(error, destination))?;
    preserve_mtime(source, destination, &metadata);
    Ok(())
}

/// 尽力保留修改时间。
///
/// 上游 `cp` 带了 `preserveTimestamps: true`。`std::fs::copy` 不保留，于是在拷完之后补一次。
/// 失败不报错：时间戳是元数据，不是内容 —— 为了它把一次成功的复制判成失败不划算。
fn preserve_mtime(_source: &Path, destination: &Path, metadata: &fs::Metadata) {
    let Ok(modified) = metadata.modified() else {
        return;
    };
    // 目录在 Windows 上打不开（`File::open` 对目录要 `FILE_FLAG_BACKUP_SEMANTICS`），
    // 所以这里只对文件生效；目录的 mtime 由后续写入自然刷新。
    if let Ok(handle) = fs::File::open(destination) {
        let _ = handle.set_modified(modified);
    }
}

#[cfg(unix)]
fn copy_symlink(source: &Path, destination: &Path) -> FileOpResult<()> {
    let target = fs::read_link(source).map_err(|error| FileOpError::from_io(error, source))?;
    std::os::unix::fs::symlink(target, destination)
        .map_err(|error| FileOpError::from_io(error, destination))
}

#[cfg(windows)]
fn copy_symlink(source: &Path, destination: &Path) -> FileOpResult<()> {
    use std::os::windows::fs::{symlink_dir, symlink_file};
    let target = fs::read_link(source).map_err(|error| FileOpError::from_io(error, source))?;
    let is_dir = fs::metadata(source)
        .map(|metadata| metadata.is_dir())
        .unwrap_or(false);
    let outcome = if is_dir {
        symlink_dir(target, destination)
    } else {
        symlink_file(target, destination)
    };
    outcome.map_err(|error| FileOpError::from_io(error, destination))
}

#[cfg(not(any(unix, windows)))]
fn copy_symlink(source: &Path, destination: &Path) -> FileOpResult<()> {
    let _ = (source, destination);
    Err(FileOpError::unsupported("这个平台不支持复制符号链接"))
}
