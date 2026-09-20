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
    let img = match crate::decode::decode(&raw_bytes) {
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
/// 1. 文件夹条目：递归选取最多四个子项的代表图，合成为封面；单图保留原比例；
/// 2. 单张图片条目：直接解码缩放，缓存键为文件名；
/// 3. 漫画归档条目 (ZIP/CBZ/RAR/CBR)：从前 16 页中提取首张可解码图片；
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

    let depth = max_depth.unwrap_or(8);
    let sort = sort_order.unwrap_or_default();
    let long_side = max_long_side.unwrap_or(THUMB_LONG_SIDE).max(1);
    let use_full_path = crate::path_key::is_drive_or_share_root(parent_dir);

    let cache_key = if is_dir {
        let auto_key = crate::thumb_loader::folder_thumb_auto_cache_key_for_path(
            entry_path,
            use_full_path,
            sort,
            depth,
        )
        .unwrap_or_else(|| {
            crate::thumb_loader::folder_thumb_auto_cache_key(
                &entry_path.to_string_lossy(),
                sort,
                depth,
            )
        });
        // 合成策略与尺寸独立入键，旧单图缓存不会盖住新封面。
        format!("{auto_key}:mosaic4:s{long_side}")
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

    // 2. 缓存未命中，根据条目类型生成缩略图
    let img = if is_dir {
        let tiles = crate::thumb_loader::resolve_folder_thumb_images(
            entry_path,
            sort,
            depth,
            4,
            |candidate| {
                use crate::thumb_loader::FolderThumbResolution;
                let image = match candidate {
                    FolderThumbResolution::Image(path) => decode_thumbnail_file(path),
                    FolderThumbResolution::Archive(path) => decode_archive_cover(path),
                }?;
                // 一次只保留一张全尺寸原图，合成阶段仅持有小图。
                Some(crate::fast_resize::resize_dynamic_fit(
                    &image,
                    long_side,
                    long_side,
                    crate::fast_resize::Quality::Lanczos3,
                ))
            },
        );
        compose_folder_cover(tiles, long_side)
    } else if is_archive {
        decode_archive_cover(entry_path)
    } else {
        decode_thumbnail_file(entry_path)
    };
    let Some(img) = img else {
        return Ok(None);
    };
    // 合成封面没有单张「原图尺寸」，不冒充图书页尺寸写入数据库。
    let source_dims = (!is_dir).then_some((img.width(), img.height()));
    let Some((webp_data, w, h)) = encode_thumb_webp(&img, long_side, 75.0) else {
        return Ok(None);
    };
    let _ = catalog.save(&cache_key, mtime, file_size, w, h, source_dims, &webp_data);
    Ok(Some(webp_data))
}

fn decode_thumbnail_file(path: &Path) -> Option<image::DynamicImage> {
    crate::decode::decode(&std::fs::read(path).ok()?).ok()
}

fn decode_archive_cover(path: &Path) -> Option<image::DynamicImage> {
    let source = LocalSource::open(path).ok()?;
    // 封面损坏时容许向后找，但不为一个列表条目解完整本书。
    (0..source.len().min(16))
        .find_map(|index| crate::decode::decode(&source.page_bytes(index).ok()?).ok())
}

fn compose_folder_cover(
    mut tiles: Vec<image::DynamicImage>,
    long_side: u32,
) -> Option<image::DynamicImage> {
    if tiles.len() <= 1 {
        return tiles.pop();
    }
    let size = long_side.max(2);
    let half = size / 2;
    // 两图左右铺满；三图左一右二；四图 2×2。不会重复图片或留下空格。
    let cells = match tiles.len() {
        2 => vec![(0, 0, half, size), (half, 0, size - half, size)],
        3 => vec![
            (0, 0, half, size),
            (half, 0, size - half, half),
            (half, half, size - half, size - half),
        ],
        _ => vec![
            (0, 0, half, half),
            (half, 0, size - half, half),
            (0, half, half, size - half),
            (half, half, size - half, size - half),
        ],
    };
    let mut cover = image::RgbImage::new(size, size);
    for (tile, (x, y, width, height)) in tiles.into_iter().zip(cells) {
        let (tw, th) = (tile.width(), tile.height());
        let (cw, ch) = if u64::from(tw) * u64::from(height) > u64::from(th) * u64::from(width) {
            (
                ((u64::from(th) * u64::from(width) / u64::from(height)) as u32).max(1),
                th,
            )
        } else {
            (
                tw,
                ((u64::from(tw) * u64::from(height) / u64::from(width)) as u32).max(1),
            )
        };
        let cropped = tile.crop_imm((tw - cw) / 2, (th - ch) / 2, cw, ch);
        let resized = crate::fast_resize::resize_dynamic_exact(
            &cropped,
            width,
            height,
            crate::fast_resize::Quality::Lanczos3,
        )
        .to_rgb8();
        image::imageops::replace(&mut cover, &resized, i64::from(x), i64::from(y));
    }
    Some(image::DynamicImage::ImageRgb8(cover))
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

    fn png_bytes(color: [u8; 3]) -> Vec<u8> {
        let img = image::RgbImage::from_pixel(80, 120, image::Rgb(color));
        let mut bytes = std::io::Cursor::new(Vec::new());
        img.write_to(&mut bytes, image::ImageFormat::Png).unwrap();
        bytes.into_inner()
    }

    fn write_cbz(path: &Path, pages: &[(&str, &[u8])]) {
        use std::io::Write;
        let file = std::fs::File::create(path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        for (name, bytes) in pages {
            zip.start_file(*name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(bytes).unwrap();
        }
        zip.finish().unwrap();
    }

    fn folder_thumbnail(cache: &Path, folder: &Path, depth: u32, size: u32) -> Option<Vec<u8>> {
        get_or_create_file_manager_thumbnail(
            cache,
            folder,
            true,
            false,
            false,
            None,
            Some(depth),
            Some(size),
        )
        .unwrap()
    }

    #[test]
    fn folder_thumbnail_reads_nested_archive_and_skips_broken_cover() {
        let tmp = tempfile::tempdir().unwrap();
        let folder = tmp.path().join("series");
        let volume = folder.join("volume");
        std::fs::create_dir_all(&volume).unwrap();
        let cover = png_bytes([240, 30, 30]);
        write_cbz(
            &volume.join("book.cbz"),
            &[("00.png", b"broken image"), ("01.png", &cover)],
        );
        let cache = tmp.path().join("cache");
        assert!(folder_thumbnail(&cache, &folder, 0, 64).is_none());
        let bytes = folder_thumbnail(&cache, &folder, 1, 64).expect("nested archive cover");
        let image = image::load_from_memory(&bytes).unwrap();
        assert!((63..=64).contains(&image.height()));
        assert!(
            image.width() < image.height(),
            "single cover keeps its aspect"
        );
        assert!(folder_thumbnail(&cache, &volume, 0, 64).is_some());
    }

    #[test]
    fn folder_thumbnail_skips_metadata_and_failed_candidates() {
        let tmp = tempfile::tempdir().unwrap();
        let folder = tmp.path().join("series");
        let broken = folder.join("00-broken");
        let metadata = folder.join(crate::fs_entry::PORTABLE_METADATA_BUNDLE_DIRNAME);
        std::fs::create_dir_all(&broken).unwrap();
        std::fs::create_dir_all(&metadata).unwrap();
        std::fs::write(broken.join("00.jpg"), b"bad image").unwrap();
        std::fs::write(folder.join("00.cbz"), b"bad archive").unwrap();
        // 即使元数据文件碰巧能解码，也不能被选成封面。
        let hidden = png_bytes([0, 0, 255]);
        std::fs::write(folder.join("._00.png"), &hidden).unwrap();
        std::fs::write(metadata.join("cover.png"), &hidden).unwrap();
        // 扩展名错写成 jpg 的 PNG 仍应按内容解码。
        std::fs::write(folder.join("01.jpg"), png_bytes([240, 30, 30])).unwrap();
        let bytes =
            folder_thumbnail(&tmp.path().join("cache"), &folder, 3, 64).expect("later valid image");
        let image = image::load_from_memory(&bytes).unwrap().to_rgb8();
        let pixel = image.get_pixel(image.width() / 2, image.height() / 2);
        assert!(pixel[0] > 200 && pixel[2] < 60);
        assert!(image.width() < image.height(), "only one visible image");
    }

    #[test]
    fn folder_thumbnail_composes_children_and_caches_each_size() {
        let tmp = tempfile::tempdir().unwrap();
        let folder = tmp.path().join("series");
        let child = folder.join("01-child");
        std::fs::create_dir_all(&child).unwrap();
        std::fs::write(child.join("01.png"), png_bytes([240, 30, 30])).unwrap();
        // 一个子目录只贡献一张，避免第一本书占满父目录的四格。
        std::fs::write(child.join("02.png"), png_bytes([0, 0, 0])).unwrap();
        write_cbz(
            &folder.join("02.cbz"),
            &[("01.png", &png_bytes([30, 240, 30]))],
        );
        std::fs::write(folder.join("03.png"), png_bytes([30, 30, 240])).unwrap();
        std::fs::write(folder.join("04.png"), png_bytes([240, 240, 30])).unwrap();
        std::fs::write(folder.join("05.png"), png_bytes([0, 0, 0])).unwrap();
        let cache = tmp.path().join("cache");
        let bytes = folder_thumbnail(&cache, &folder, 3, 64).expect("four tile cover");
        let image = image::load_from_memory(&bytes).unwrap().to_rgb8();
        assert_eq!(image.dimensions(), (64, 64));
        for ((x, y), expected) in [
            ((16, 16), [240, 30, 30]),
            ((48, 16), [30, 240, 30]),
            ((16, 48), [30, 30, 240]),
            ((48, 48), [240, 240, 30]),
        ] {
            let actual = image.get_pixel(x, y);
            for channel in 0..3 {
                assert!(actual[channel].abs_diff(expected[channel]) < 25);
            }
        }
        let large = folder_thumbnail(&cache, &folder, 3, 96).unwrap();
        assert_eq!(image::load_from_memory(&large).unwrap().width(), 96);
        // 破坏子封面后仍能命中同尺寸 SQLite 缓存，不会重新解码。
        std::fs::write(child.join("01.png"), b"removed image data").unwrap();
        assert_eq!(folder_thumbnail(&cache, &folder, 3, 64), Some(bytes));
    }

    #[test]
    fn folder_thumbnail_fills_two_and_three_tiles_at_odd_sizes() {
        let tmp = tempfile::tempdir().unwrap();
        let cache = tmp.path().join("cache");
        for count in [2, 3] {
            let folder = tmp.path().join(format!("{count}-tiles"));
            std::fs::create_dir(&folder).unwrap();
            for index in 0..count {
                let mut color = [30; 3];
                color[index] = 240;
                std::fs::write(folder.join(format!("{index}.png")), png_bytes(color)).unwrap();
            }
            let bytes = folder_thumbnail(&cache, &folder, 0, 65).unwrap();
            let image = image::load_from_memory(&bytes).unwrap().to_rgb8();
            assert_eq!(image.dimensions(), (65, 65));
            assert!(
                image
                    .pixels()
                    .all(|pixel| pixel.0.into_iter().max().unwrap() > 100)
            );
            let left = image.get_pixel(16, 32);
            assert!(left[0] > 200 && left[1] < 60);
            let top_right = image.get_pixel(48, 16);
            assert!(top_right[1] > 200 && top_right[0] < 60);
            let bottom_right = image.get_pixel(48, 48);
            assert!(bottom_right[if count == 2 { 1 } else { 2 }] > 200);
        }
    }

    #[test]
    fn folder_thumbnail_default_reaches_beyond_three_levels() {
        let tmp = tempfile::tempdir().unwrap();
        let folder = tmp.path().join("series");
        let nested = folder.join("a/b/c/d");
        std::fs::create_dir_all(&nested).unwrap();
        std::fs::write(nested.join("cover.png"), png_bytes([240, 30, 30])).unwrap();
        let bytes = get_or_create_file_manager_thumbnail(
            &tmp.path().join("cache"),
            &folder,
            true,
            false,
            false,
            None,
            None,
            Some(64),
        )
        .unwrap();
        assert!(bytes.is_some());
    }

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
