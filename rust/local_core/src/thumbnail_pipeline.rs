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

/// 从 mImageViewer 目录数据库获取或生成文件管理器条目 (文件夹/单张图片/漫画归档) 缩略图。
///
/// 遵循 mImageViewer 的规范：
/// 1. 文件夹条目：通过 `thumb_loader::resolve_folder_thumb_image` 递归推选代表图片，缓存键为 `folderthumb:auto-v2:...`；
/// 2. 单张图片条目：直接解码缩放，缓存键为文件名；
/// 3. 漫画归档条目 (ZIP/CBZ/RAR/CBR)：提取封面 (第 0 页) 并缩放，缓存键为 `zipthumb:{filename}`；
/// 4. 优先查验 parent_dir 下的 SQLite `CatalogDb` WAL 缓存；命中有效缓存直接返回 WebP 字节流。
pub fn get_or_create_file_manager_thumbnail(
    cache_dir: &Path,
    entry_path: &Path,
    is_dir: bool,
    is_archive: bool,
    is_image: bool,
    sort_order: Option<crate::settings::SortOrder>,
    max_depth: Option<u32>,
    max_long_side: Option<u32>,
) -> Result<Option<Vec<u8>>> {
    let meta = match std::fs::metadata(entry_path) {
        Ok(m) => m,
        Err(_) => return Ok(None),
    };

    let mtime = crate::ui_helpers::mtime_secs(&meta);
    let file_size = if is_dir { 0 } else { meta.len() as i64 };

    let parent_dir = entry_path.parent().unwrap_or(entry_path);
    let catalog = CatalogDb::open(cache_dir, parent_dir)
        .with_context(|| format!("打开目录缩略图数据库失败: {}", parent_dir.display()))?;

    let depth = max_depth.unwrap_or(3);
    let sort = sort_order.unwrap_or_default();
    let use_full_path = crate::path_key::is_drive_or_share_root(parent_dir);

    let cache_key = if is_dir {
        crate::thumb_loader::folder_thumb_auto_cache_key_for_path(
            entry_path,
            use_full_path,
            sort,
            depth,
        )
        .unwrap_or_else(|| format!("folderthumb:{}", entry_path.display()))
    } else if is_archive {
        let filename = entry_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        format!("{}{filename}", crate::thumb_loader::CACHE_KEY_ZIP)
    } else if is_image {
        entry_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string()
    } else {
        return Ok(None);
    };

    // 1. 尝试从 SQLite CatalogDb 加载缓存
    if let Ok(Some(entry)) = catalog.load_one(&cache_key) {
        if is_dir {
            if !entry.jpeg_data.is_empty() {
                return Ok(Some(entry.jpeg_data));
            }
        } else if (mtime == 0 || entry.mtime == mtime)
            && (file_size == 0 || entry.file_size == file_size)
        {
            return Ok(Some(entry.jpeg_data));
        }
    }

    let long_side = max_long_side.unwrap_or(THUMB_LONG_SIDE);

    // 2. 缓存未命中，根据条目类型生成缩略图
    if is_dir {
        let res = crate::thumb_loader::resolve_folder_thumb_image(entry_path, sort, depth);
        let Some(crate::thumb_loader::FolderThumbResolution::Image(img_path)) = res else {
            return Ok(None);
        };
        let img = match image::open(&img_path) {
            Ok(i) => i,
            Err(_) => return Ok(None),
        };
        let source_dims = (img.width(), img.height());
        let (webp_data, w, h) = match encode_thumb_webp(&img, long_side, 75.0) {
            Some(res) => res,
            None => return Ok(None),
        };
        let _ = catalog.save(
            &cache_key,
            mtime,
            file_size,
            w,
            h,
            Some(source_dims),
            &webp_data,
        );
        Ok(Some(webp_data))
    } else if is_image {
        let img = match image::open(entry_path) {
            Ok(i) => i,
            Err(_) => return Ok(None),
        };
        let source_dims = (img.width(), img.height());
        let (webp_data, w, h) = match encode_thumb_webp(&img, long_side, 75.0) {
            Some(res) => res,
            None => return Ok(None),
        };
        let _ = catalog.save(
            &cache_key,
            mtime,
            file_size,
            w,
            h,
            Some(source_dims),
            &webp_data,
        );
        Ok(Some(webp_data))
    } else if is_archive {
        let source = match LocalSource::open(entry_path) {
            Ok(s) => s,
            Err(_) => return Ok(None),
        };
        if source.is_empty() {
            return Ok(None);
        }
        let raw_bytes = match source.page_bytes(0) {
            Ok(b) => b,
            Err(_) => return Ok(None),
        };
        let img = match image::load_from_memory(&raw_bytes) {
            Ok(i) => i,
            Err(_) => return Ok(None),
        };
        let source_dims = (img.width(), img.height());
        let (webp_data, w, h) = match encode_thumb_webp(&img, long_side, 75.0) {
            Some(res) => res,
            None => return Ok(None),
        };
        let _ = catalog.save(
            &cache_key,
            mtime,
            file_size,
            w,
            h,
            Some(source_dims),
            &webp_data,
        );
        Ok(Some(webp_data))
    } else {
        Ok(None)
    }
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

/// 根据一组图片宽高 (width, height) 集合，自动推选最佳统一缩略图比例。
///
/// 过滤掉非法尺寸 (<= 0)，转为比率 (height / width)，使用 log 空间中位数推选最近邻比例桶。
pub fn pick_aspect_from_dimensions<I>(dims: I) -> Option<crate::settings::ThumbAspect>
where
    I: IntoIterator<Item = (u32, u32)>,
{
    let ratios: Vec<f32> = dims
        .into_iter()
        .filter_map(|(w, h)| {
            if w > 0 && h > 0 {
                Some(h as f32 / w as f32)
            } else {
                None
            }
        })
        .collect();
    crate::auto_aspect::pick_best(&ratios)
}

/// 从已缓存的图书页面尺寸中，自动选择整本书的最佳统一缩略图比例。
pub fn pick_aspect_for_cached_book(
    cache_dir: &Path,
    book_path: &Path,
) -> Result<Option<crate::settings::ThumbAspect>> {
    let dims = get_cached_book_dimensions(cache_dir, book_path)?;
    Ok(pick_aspect_from_dimensions(dims.into_values()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::ThumbAspect;

    #[test]
    fn test_pick_aspect_from_dimensions_empty_and_invalid() {
        assert_eq!(pick_aspect_from_dimensions([]), None);
        assert_eq!(
            pick_aspect_from_dimensions([(0, 0), (0, 100), (100, 0)]),
            None
        );
    }

    #[test]
    fn test_pick_aspect_from_dimensions_portrait_manga() {
        let dims = vec![(1000, 1500), (800, 1200), (1200, 1800)]; // 2:3
        assert_eq!(
            pick_aspect_from_dimensions(dims),
            Some(ThumbAspect::Portrait2x3)
        );
    }

    #[test]
    fn test_pick_aspect_from_dimensions_landscape() {
        let dims = vec![(1920, 1080), (1280, 720)]; // 16:9
        assert_eq!(
            pick_aspect_from_dimensions(dims),
            Some(ThumbAspect::Landscape16x9)
        );
    }

    #[test]
    fn test_pick_aspect_from_dimensions_mixed_lands_square() {
        // 横竖对称混排，中位数为 1.0 (Square)
        let dims = vec![(2000, 1000), (1000, 2000), (2000, 1000), (1000, 2000)];
        assert_eq!(pick_aspect_from_dimensions(dims), Some(ThumbAspect::Square));
    }

    #[test]
    fn test_file_manager_thumbnail_image_and_folder() {
        let tmp = tempfile::TempDir::new().unwrap();
        let cache_dir = tmp.path().join("cache");
        let work_dir = tmp.path().join("work");
        std::fs::create_dir_all(&work_dir).unwrap();

        // 1. 创建单张有效测试图片 (使用 image crate 编码一张 100x100 的 PNG)
        let img_path = work_dir.join("photo.png");
        let sample = image::RgbImage::new(100, 100);
        sample.save(&img_path).unwrap();

        // 生成单张图片缩略图
        let thumb = get_or_create_file_manager_thumbnail(
            &cache_dir,
            &img_path,
            false,
            false,
            true,
            None,
            None,
            Some(64),
        )
        .unwrap();
        assert!(thumb.is_some());
        let bytes1 = thumb.unwrap();
        assert!(!bytes1.is_empty());

        // 再次获取应命中 SQLite 缓存，返回相同字节
        let thumb2 = get_or_create_file_manager_thumbnail(
            &cache_dir,
            &img_path,
            false,
            false,
            true,
            None,
            None,
            Some(64),
        )
        .unwrap();
        assert_eq!(thumb2, Some(bytes1));

        // 2. 测试文件夹缩略图 (文件夹包含子文件夹与图片)
        let manga_dir = work_dir.join("MangaSeries");
        let vol1 = manga_dir.join("Vol1");
        std::fs::create_dir_all(&vol1).unwrap();
        let cover_path = vol1.join("cover.png");
        sample.save(&cover_path).unwrap();

        let folder_thumb = get_or_create_file_manager_thumbnail(
            &cache_dir,
            &manga_dir,
            true,
            false,
            false,
            None,
            Some(3),
            Some(64),
        )
        .unwrap();
        assert!(folder_thumb.is_some());
        let fbytes = folder_thumb.unwrap();
        assert!(!fbytes.is_empty());

        // 再次读取命中缓存
        let folder_thumb2 = get_or_create_file_manager_thumbnail(
            &cache_dir,
            &manga_dir,
            true,
            false,
            false,
            None,
            Some(3),
            Some(64),
        )
        .unwrap();
        assert_eq!(folder_thumb2, Some(fbytes));

        // 3. 不存在的文件返回 Ok(None)
        let non_existent = work_dir.join("ghost.png");
        let ghost = get_or_create_file_manager_thumbnail(
            &cache_dir,
            &non_existent,
            false,
            false,
            true,
            None,
            None,
            Some(64),
        )
        .unwrap();
        assert!(ghost.is_none());
    }
}
