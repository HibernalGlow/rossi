//! 缓存 DB 的存放位置决定，以及整个缓存目录的管理。
//!
//! `.db` 的扫描本身 (`collect_db_paths` / `collect_db_files`) 是父模块 `catalog.rs` 的
//! 私有辅助函数，因此向上引用。

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::path_key;

use super::{collect_db_files, collect_db_paths};

// -----------------------------------------------------------------------
// DB path helpers
// -----------------------------------------------------------------------

/// 以 `{cache_dir}/{xx}/{sha256}.db` 的形式返回 DB 文件路径。
/// xx 为哈希 hex 的前 2 个字符（分散到 256 个子文件夹）。
pub fn db_path_for(cache_dir: &Path, folder_path: &Path) -> PathBuf {
    // 普通子文件夹照旧丢弃盘符，即使可移动盘的盘符变化也继续继承缓存。而只有驱动器
    // 根目录，`C:\Photos`
    // 与 `D:\Photos` 这样同名直下项目会冲突成同一个 root catalog / 同一个 basename key，
    // 因此保留盘符，把 DB 本身分离开。
    let normalized = if path_key::is_drive_or_share_root(folder_path) {
        path_key::normalize_keep_drive(folder_path)
    } else {
        path_key::normalize(folder_path)
    };
    let hash = format!("{:x}", Sha256::digest(normalized.as_bytes()));
    cache_dir.join(&hash[..2]).join(format!("{}.db", hash))
}
/// 缓存目录的默认位置
pub fn default_cache_dir() -> PathBuf {
    std::env::temp_dir().join("breeze_cache")
}

// -----------------------------------------------------------------------
// 缓存管理工具
// -----------------------------------------------------------------------

/// 返回 cache_dir 下 .db 文件的数量与总字节数。
pub fn cache_stats(cache_dir: &Path) -> (usize, u64) {
    let mut count = 0usize;
    let mut total_bytes = 0u64;
    collect_db_files(cache_dir, &mut |meta| {
        count += 1;
        total_bytes += meta.len();
    });
    (count, total_bytes)
}

/// 删除 cache_dir 下最后更新时间在 `days` 天以前的 .db 文件。
/// 返回删除的文件数。
pub fn delete_old_cache(cache_dir: &Path, days: u64) -> usize {
    let now = std::time::SystemTime::now();
    let threshold = std::time::Duration::from_secs(days * 24 * 3600);
    let mut deleted = 0usize;
    collect_db_paths(cache_dir, &mut |path, meta| {
        let age = meta
            .modified()
            .ok()
            .and_then(|mtime| now.duration_since(mtime).ok())
            .unwrap_or(std::time::Duration::ZERO);
        if age >= threshold {
            if std::fs::remove_file(path).is_ok() {
                deleted += 1;
            }
        }
    });
    deleted
}

/// 删除 cache_dir 下的全部 .db 文件。
/// 返回删除的文件数。
pub fn delete_all_cache(cache_dir: &Path) -> usize {
    let mut deleted = 0usize;
    collect_db_paths(cache_dir, &mut |path, _| {
        if std::fs::remove_file(path).is_ok() {
            deleted += 1;
        }
    });
    deleted
}
