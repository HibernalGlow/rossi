use std::collections::HashMap;
use std::path::Path;

use anyhow::Result;
use flutter_rust_bridge::frb;
use rossi_local_core::thumbnail_pipeline::{get_cached_book_dimensions, get_or_create_thumbnail};

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
