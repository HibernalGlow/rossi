use std::collections::HashMap;
use std::path::Path;

use anyhow::{Context, Result};

use crate::LocalSource;
use crate::catalog::{CatalogDb, THUMB_LONG_SIDE, encode_thumb_webp};

/// 从 mImageViewer 目录数据库获取或生成单页缩略图。
///
/// 1. 优先查阅 SQLite `CatalogDb` 缓存 (`{cache_dir}/{xx}/{sha256}.db`)；
/// 2. 命中有效缓存直接返回 WebP 字节流；
/// 3. 未命中则从 `LocalSource` 读取对应页面，缩放并编码为 WebP 存入 SQLite 并返回。
pub fn get_or_create_thumbnail(
    cache_dir: &Path,
    book_path: &Path,
    entry_name: &str,
    page_index: usize,
    max_long_side: Option<u32>,
) -> Result<Option<Vec<u8>>> {
    let meta = match std::fs::metadata(book_path) {
        Ok(m) => m,
        Err(_) => return Ok(None),
    };

    let (effective_entry_name, mut source_opt) = if entry_name.is_empty() {
        match LocalSource::open(book_path) {
            Ok(s) => {
                let pages = s.pages();
                if page_index < pages.len() {
                    (pages[page_index].name.clone(), Some(s))
                } else {
                    (format!("page_{page_index}"), Some(s))
                }
            }
            Err(_) => (format!("page_{page_index}"), None),
        }
    } else {
        (entry_name.to_string(), None)
    };

    let (mtime, file_size) = if meta.is_dir() {
        let child_path = book_path.join(&effective_entry_name);
        match std::fs::metadata(&child_path) {
            Ok(cm) => (
                cm.modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0),
                cm.len() as i64,
            ),
            Err(_) => (0, 0),
        }
    } else {
        (
            meta.modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0),
            meta.len() as i64,
        )
    };

    // 1. 尝试从已有 CatalogDb 读取
    let catalog = CatalogDb::open(cache_dir, book_path)
        .with_context(|| format!("打开缩略图数据库失败: {}", book_path.display()))?;

    if let Ok(Some(entry)) = catalog.load_one(&effective_entry_name) {
        if (mtime == 0 || entry.mtime == mtime) && (file_size == 0 || entry.file_size == file_size)
        {
            return Ok(Some(entry.jpeg_data));
        }
    }

    // 2. 缓存未命中：通过 LocalSource 提取并生成
    let source = match source_opt.take() {
        Some(s) => s,
        None => match LocalSource::open(book_path) {
            Ok(s) => s,
            Err(_) => return Ok(None),
        },
    };

    let pages = source.pages();
    if page_index >= pages.len() {
        return Ok(None);
    }

    let raw_bytes = source.page_bytes(page_index)?;
    let img = match image::load_from_memory(&raw_bytes) {
        Ok(i) => i,
        Err(_) => return Ok(None),
    };

    let source_dims = (img.width(), img.height());
    let long_side = max_long_side.unwrap_or(THUMB_LONG_SIDE);
    let (webp_data, w, h) = match encode_thumb_webp(&img, long_side, 75.0) {
        Some(res) => res,
        None => return Ok(None),
    };

    // 3. 异步/同步写入 SQLite
    let _ = catalog.save(
        &effective_entry_name,
        mtime,
        file_size,
        w,
        h,
        Some(source_dims),
        &webp_data,
    );

    Ok(Some(webp_data))
}

/// 快速查询整本书中所有已缓存页面的原图真实宽高（无需解压原图）。
pub fn get_cached_book_dimensions(
    cache_dir: &Path,
    book_path: &Path,
) -> Result<HashMap<String, (u32, u32)>> {
    let catalog = match CatalogDb::open_existing_read_only(cache_dir, book_path)? {
        Some(c) => c,
        None => return Ok(HashMap::new()),
    };

    let dims_map = catalog.load_source_dims()?;
    let mut result = HashMap::new();
    for (name, dims) in dims_map {
        if let Some(d) = dims {
            result.insert(name, d);
        }
    }
    Ok(result)
}
