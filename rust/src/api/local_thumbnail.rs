use std::collections::HashMap;
use std::path::Path;

use anyhow::Result;
use flutter_rust_bridge::frb;
use rossi_local_core::thumbnail_pipeline::{
    get_cached_book_dimensions, get_or_create_thumbnail, pick_aspect_for_cached_book,
};

/// 从 mImageViewer SQLite 目录数据库 (`CatalogDb`) 获取或按需生成单页缩略图。
///
/// 1. 优先查 SQLite (`{cache_dir}/{xx}/{sha256}.db` 的 `thumbnails` 表)；
/// 2. 命中返回 WebP 字节流；
/// 3. 未命中则后台从归档/文件夹读取、缩放、压缩为 WebP 存入 SQLite 并返回。
#[frb]
pub fn get_local_thumbnail(
    cache_dir: String,
    book_path: String,
    entry_name: String,
    page_index: u32,
    max_long_side: Option<u32>,
) -> Result<Option<Vec<u8>>> {
    get_or_create_thumbnail(
        Path::new(&cache_dir),
        Path::new(&book_path),
        &entry_name,
        page_index as usize,
        max_long_side,
    )
}

/// 从 SQLite 目录数据库直接读取整本漫画所有已缓存页面的真实宽高 (免解压大图)。
#[frb]
pub fn get_cached_book_page_dimensions(
    cache_dir: String,
    book_path: String,
) -> Result<HashMap<String, (u32, u32)>> {
    get_cached_book_dimensions(Path::new(&cache_dir), Path::new(&book_path))
}

/// 获取整本书已缓存页面的推荐自动缩略图比例标签（如 "16:9", "1:1", "2:3" 等）。
#[frb]
pub fn get_cached_book_auto_aspect(cache_dir: String, book_path: String) -> Result<Option<String>> {
    let aspect = pick_aspect_for_cached_book(Path::new(&cache_dir), Path::new(&book_path))?;
    Ok(aspect.map(|a| a.label().to_string()))
}

/// 获取或生成文件管理器条目 (文件夹、单张图片或漫画归档) 的缩略图。
///
/// 遵循 mImageViewer SQLite CatalogDb 与代表图推选逻辑。
#[frb]
pub fn get_file_manager_entry_thumbnail(
    cache_dir: String,
    entry_path: String,
    is_dir: bool,
    is_archive: bool,
    is_image: bool,
    sort_order: Option<String>,
    max_depth: Option<u32>,
    max_long_side: Option<u32>,
) -> Result<Option<Vec<u8>>> {
    let sort = match sort_order.as_deref() {
        Some("FileName") => Some(rossi_local_core::settings::SortOrder::FileName),
        Some("Numeric") => Some(rossi_local_core::settings::SortOrder::Numeric),
        Some("DateAsc") => Some(rossi_local_core::settings::SortOrder::DateAsc),
        Some("DateDesc") => Some(rossi_local_core::settings::SortOrder::DateDesc),
        Some("NameAsc") => Some(rossi_local_core::settings::SortOrder::NameAsc),
        Some("NameDesc") => Some(rossi_local_core::settings::SortOrder::NameDesc),
        _ => None,
    };
    rossi_local_core::thumbnail_pipeline::get_or_create_file_manager_thumbnail(
        Path::new(&cache_dir),
        Path::new(&entry_path),
        is_dir,
        is_archive,
        is_image,
        sort,
        max_depth,
        max_long_side,
    )
}

