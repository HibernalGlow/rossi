//! mImageViewer `folder_tree` 的无 UI 排序设置适配。
//!
//! 文件管理器把设置保存在自己的 Rust 状态中；这里的类型只为直接编译并调用
//! mImageViewer `folder_tree.rs` 的源码函数，不承载 Flutter 状态。

use std::cmp::Ordering;

use crate::filename_sort::SortNameKey;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SortOrder {
    NameAsc,
    NameDesc,
    Numeric,
    DateAsc,
    DateDesc,
}

impl Default for SortOrder {
    fn default() -> Self {
        Self::NameAsc
    }
}

impl SortOrder {
    pub fn name_key(self, name: &str) -> SortNameKey {
        match self {
            Self::Numeric => SortNameKey::with_natural(name),
            _ => SortNameKey::file_name(name),
        }
    }

    pub fn compare_name_keys(
        self,
        left: &SortNameKey,
        left_mtime: i64,
        right: &SortNameKey,
        right_mtime: i64,
    ) -> Ordering {
        let by_name = match self {
            Self::Numeric => left.compare_natural(right),
            _ => left.compare_file_name(right),
        };
        match self {
            Self::NameDesc => by_name.reverse(),
            Self::DateAsc => left_mtime
                .cmp(&right_mtime)
                .then_with(|| left.compare_file_name(right)),
            Self::DateDesc => right_mtime
                .cmp(&left_mtime)
                .then_with(|| left.compare_file_name(right)),
            _ => by_name,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Settings {
    pub skip_zip_if_folder_exists: bool,
    pub skip_archive_if_zip_exists: bool,
    pub include_convertible_archives: bool,
    pub sort_order: SortOrder,
}

impl Settings {
    pub fn archive_file_handling_ignores_convertible(&self) -> bool {
        !self.include_convertible_archives
    }
}
