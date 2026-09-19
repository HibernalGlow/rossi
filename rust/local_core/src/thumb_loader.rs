// Copyright (c) 2024-2026 mImageViewer authors
// SPDX-License-Identifier: MIT
//
// Vendored from mImageViewer `src/thumb_loader.rs` at commit 1fd6f863.
// Preserves upstream function, constant, and type names.

use std::path::{Path, PathBuf};

pub const CACHE_KEY_ZIP: &str = "zipthumb:";
pub const CACHE_KEY_PDF: &str = "pdfthumb:";
pub const CACHE_KEY_ARCHIVE: &str = "archivethumb:";
pub const CACHE_KEY_FOLDER: &str = "folderthumb:";
pub const FOLDER_THUMB_AUTO_ALGO_VERSION: u32 = 2;
pub const CACHE_KEY_PIN_SUFFIX: &str = "#pin:";

/// フォルダ代表サムネの自動選定用 cache key を組み立てる。
///
/// `identity` はフォルダ名または full path。ソート種別・探索深度・アルゴリズム世代を
/// key に含め、設定やロジックが変わったときだけ古い自動代表サムネを読まないようにする。
pub fn folder_thumb_auto_cache_key(
    identity: &str,
    sort: crate::settings::SortOrder,
    depth: u32,
) -> String {
    let sort_token = match sort {
        crate::settings::SortOrder::FileName => "name",
        crate::settings::SortOrder::Numeric => "numeric",
        crate::settings::SortOrder::DateAsc => "date-asc",
        crate::settings::SortOrder::DateDesc => "date-desc",
        crate::settings::SortOrder::NameAsc => "name-asc",
        crate::settings::SortOrder::NameDesc => "name-desc",
    };
    format!(
        "{CACHE_KEY_FOLDER}auto-v{FOLDER_THUMB_AUTO_ALGO_VERSION}:{sort_token}:d{depth}:{identity}"
    )
}

/// Folder item の自動代表 cache key を、通常一覧と再帰 cache-only 参照で同じ規則から作る。
///
/// ドライブルートや集約ビューは同名衝突を避けるため full path、それ以外は basename を
/// identity にする。再帰探索側は物理フォルダだけを扱うため、直上がドライブ / share root
/// かどうかから `use_full_path` を決めてこの helper を呼ぶ。
pub fn folder_thumb_auto_cache_key_for_path(
    path: &Path,
    use_full_path: bool,
    sort: crate::settings::SortOrder,
    depth: u32,
) -> Option<String> {
    let identity = if use_full_path {
        path.to_string_lossy().into_owned()
    } else {
        path.file_name().and_then(|name| name.to_str())?.to_owned()
    };
    Some(folder_thumb_auto_cache_key(&identity, sort, depth))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FolderThumbResolution {
    Image(PathBuf),
}

/// フォルダ内をスキャンして代表画像を返す。
/// `sort` で指定されたソート順でフォルダブロックと画像ブロックをそれぞれ並べ、
/// サムネイル一覧に近い順序 (フォルダ → 画像) で最初に見つかった画像を選ぶ。
/// サブフォルダ再帰は最大 `remaining_depth` 階層。
pub fn resolve_folder_thumb_image(
    folder: &Path,
    sort: crate::settings::SortOrder,
    remaining_depth: u32,
) -> Option<FolderThumbResolution> {
    resolve_folder_thumb_image_inner(
        folder,
        sort,
        remaining_depth,
        remaining_depth,
    )
}

pub fn resolve_folder_thumb_image_inner(
    folder: &Path,
    sort: crate::settings::SortOrder,
    remaining_depth: u32,
    configured_depth: u32,
) -> Option<FolderThumbResolution> {
    fn mtime_for_sort(entry: &std::fs::DirEntry, sort: crate::settings::SortOrder) -> i64 {
        match sort {
            crate::settings::SortOrder::DateAsc | crate::settings::SortOrder::DateDesc => entry
                .metadata()
                .ok()
                .map_or(0, |m| crate::ui_helpers::mtime_secs(&m)),
            _ => 0,
        }
    }

    let entries = std::fs::read_dir(folder).ok()?;
    let mut images: Vec<(PathBuf, i64)> = Vec::new();
    let mut subdirs: Vec<(PathBuf, i64)> = Vec::new();

    for entry in entries.flatten() {
        let Ok(ft) = entry.file_type() else {
            continue;
        };
        let p = entry.path();
        let kind = crate::fs_entry::classify_dir_entry(&entry, &ft);
        if kind.is_directory() {
            let mtime = mtime_for_sort(&entry, sort);
            subdirs.push((p, mtime));
        } else if kind.is_file() {
            if let Some(ext) = p.extension().and_then(|e| e.to_str()) {
                if crate::folder_tree::is_recognized_image_ext(&ext.to_ascii_lowercase()) {
                    let mtime = mtime_for_sort(&entry, sort);
                    images.push((p, mtime));
                }
            }
        }
    }

    // サムネイル一覧はフォルダブロックを画像より先に出すため、代表サムネも
    // キャッシュミス時の自動選定ではサブフォルダを先に辿る。
    if remaining_depth > 0 {
        let mut keyed_subdirs: Vec<_> = subdirs
            .into_iter()
            .map(|(path, mtime)| {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                let key = sort.name_key(name);
                (path, mtime, key)
            })
            .collect();
        keyed_subdirs
            .sort_by(|(_, a_mt, ak), (_, b_mt, bk)| sort.compare_name_keys(ak, *a_mt, bk, *b_mt));
        subdirs = keyed_subdirs
            .into_iter()
            .map(|(path, mtime, _)| (path, mtime))
            .collect();
        for (sub, _) in &subdirs {
            if let Some(img) = resolve_folder_thumb_image_inner(
                sub,
                sort,
                remaining_depth - 1,
                configured_depth,
            ) {
                return Some(img);
            }
        }
    }

    if !images.is_empty() {
        let mut keyed_images: Vec<_> = images
            .into_iter()
            .map(|(path, mtime)| {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                let key = sort.name_key(name);
                (path, mtime, key)
            })
            .collect();
        keyed_images
            .sort_by(|(_, a_mt, ak), (_, b_mt, bk)| sort.compare_name_keys(ak, *a_mt, bk, *b_mt));
        images = keyed_images
            .into_iter()
            .map(|(path, mtime, _)| (path, mtime))
            .collect();
        return Some(FolderThumbResolution::Image(
            images.into_iter().next().unwrap().0,
        ));
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::SortOrder;
    use tempfile::TempDir;

    fn resolved_image_path(res: Option<FolderThumbResolution>) -> Option<PathBuf> {
        match res {
            Some(FolderThumbResolution::Image(p)) => Some(p),
            None => None,
        }
    }

    #[test]
    fn test_resolve_folder_thumb_numeric_sorts_subdirs() {
        let tmp = TempDir::new().unwrap();
        let dir1 = tmp.path().join("01-sub");
        let dir2 = tmp.path().join("02-sub");
        let dir10 = tmp.path().join("10-sub");
        std::fs::create_dir_all(&dir1).unwrap();
        std::fs::create_dir_all(&dir2).unwrap();
        std::fs::create_dir_all(&dir10).unwrap();

        std::fs::write(dir10.join("a.jpg"), b"not decoded").unwrap();
        let expected = dir2.join("a.jpg");
        std::fs::write(&expected, b"not decoded").unwrap();

        let picked = resolve_folder_thumb_image(tmp.path(), SortOrder::Numeric, 1);

        assert_eq!(resolved_image_path(picked), Some(expected));
    }

    #[test]
    fn default_folder_thumb_sort_picks_cover_before_numbered_sibling() {
        let tmp = TempDir::new().unwrap();
        let expected = tmp.path().join("00表紙.jpg");
        std::fs::write(&expected, b"not decoded").unwrap();
        std::fs::write(tmp.path().join("00表紙2.jpg"), b"not decoded").unwrap();

        let picked = resolve_folder_thumb_image_inner(
            tmp.path(),
            SortOrder::default(),
            0,
            0,
        );

        assert_eq!(resolved_image_path(picked), Some(expected));
    }

    #[test]
    fn resolve_folder_thumb_sorts_subdirs_by_date_desc() {
        let tmp = TempDir::new().unwrap();
        let old_dir = tmp.path().join("old");
        std::fs::create_dir_all(&old_dir).unwrap();
        std::fs::write(old_dir.join("a.jpg"), b"not decoded").unwrap();

        std::thread::sleep(std::time::Duration::from_millis(1_100));

        let new_dir = tmp.path().join("new");
        std::fs::create_dir_all(&new_dir).unwrap();
        let expected = new_dir.join("a.jpg");
        std::fs::write(&expected, b"not decoded").unwrap();

        let picked = resolve_folder_thumb_image(tmp.path(), SortOrder::DateDesc, 1);

        assert_eq!(resolved_image_path(picked), Some(expected));
    }

    #[test]
    fn resolve_folder_thumb_prefers_folder_block_before_direct_images() {
        let tmp = TempDir::new().unwrap();
        let sub = tmp.path().join("01-sub");
        std::fs::create_dir_all(&sub).unwrap();
        let expected = sub.join("09.jpg");
        std::fs::write(&expected, b"not decoded").unwrap();
        std::fs::write(tmp.path().join("00.jpg"), b"not decoded").unwrap();

        let picked = resolve_folder_thumb_image(tmp.path(), SortOrder::Numeric, 1);

        assert_eq!(resolved_image_path(picked), Some(expected));
    }

    #[test]
    fn resolve_folder_thumb_depth_zero_uses_direct_images() {
        let tmp = TempDir::new().unwrap();
        let sub = tmp.path().join("01-sub");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(sub.join("00.jpg"), b"not decoded").unwrap();
        let expected = tmp.path().join("01.jpg");
        std::fs::write(&expected, b"not decoded").unwrap();

        let picked = resolve_folder_thumb_image(tmp.path(), SortOrder::Numeric, 0);

        assert_eq!(resolved_image_path(picked), Some(expected));
    }
}
