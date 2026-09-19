//! CBZ / ZIP 来源。
//!
//! 定位方式与 mImageViewer 不同，这里**故意**如此：
//!
//! - mImageViewer 用「去重后的条目名」当句柄，读的时候重新扫一遍列表按名字找。
//! - Rossi 用**中央目录里的下标**当句柄（`Locator::ZipIndex`）。
//!
//! 下标有两个好处：读一页是 O(1) 而不是 O(条目数)；而且归档里有两条同名条目时
//! 不会读错那一条（名字去重是为了 UI 显示，不该承担寻址职责）。
//!
//! 与 RAR 一样**不常驻句柄**：每次读一页都重新打开归档。代价是重复解析中央目录
//! （典型漫画包几百条、几 KB），换来的是「连读三本内存不增长」这条判据不依赖
//! 任何缓存淘汰策略是否写对（v0.1 判据 D）。

use std::collections::HashSet;
use std::fs::File;
use std::io::Read;
use std::path::Path;

use anyhow::{Context, Result, bail};
use zip::ZipArchive;

use crate::entry_name::{dedup_entry_name, normalize_entry_name};
use crate::page_order::{is_page_name, should_ignore_name, sort_natural};
use crate::{Locator, PageEntry};

/// 单条目解压上限，防 zip bomb / 防把显存和内存一次吃掉。
const MAX_ENTRY_BYTES: u64 = 512 * 1024 * 1024;

pub fn is_zip_path(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip") || ext.eq_ignore_ascii_case("cbz"))
}

fn open_archive(path: &Path) -> Result<ZipArchive<File>> {
    let file = File::open(path).with_context(|| format!("无法打开归档: {}", path.display()))?;
    ZipArchive::new(file).with_context(|| format!("中央目录读取失败: {}", path.display()))
}

/// 枚举归档里的页面。
pub fn enumerate(path: &Path) -> Result<Vec<PageEntry>> {
    let mut archive = open_archive(path)?;
    let mut seen = HashSet::new();
    let mut pages = Vec::new();

    for index in 0..archive.len() {
        let entry = archive
            .by_index(index)
            .with_context(|| format!("读取第 {index} 条条目失败"))?;
        if entry.is_dir() {
            continue;
        }
        let Some(name) = normalize_entry_name(entry.name()) else {
            continue;
        };
        if should_ignore_name(&name) || !is_page_name(&name) {
            continue;
        }
        // 名字只服务 UI；同名条目在这里被唯一化，避免列表里出现两行一样的名字。
        let display = dedup_entry_name(name, &mut seen);
        pages.push(PageEntry {
            name: display,
            size: entry.size(),
            locator: Locator::ZipIndex(index),
        });
    }

    sort_natural(&mut pages, |page| page.name.as_str());
    Ok(pages)
}

/// 按下标读取一条条目的字节。
pub fn read_entry(path: &Path, index: usize) -> Result<Vec<u8>> {
    let mut archive = open_archive(path)?;
    if index >= archive.len() {
        bail!("条目下标越界: {index} / {}", archive.len());
    }
    let mut entry = archive
        .by_index(index)
        .with_context(|| format!("读取第 {index} 条条目失败"))?;

    let declared = entry.size();
    if declared > MAX_ENTRY_BYTES {
        bail!("条目声明大小 {declared} 字节，超过 {MAX_ENTRY_BYTES} 上限");
    }

    let mut bytes = Vec::with_capacity(declared.min(8 * 1024 * 1024) as usize);
    entry
        .read_to_end(&mut bytes)
        .with_context(|| format!("解压第 {index} 条条目失败"))?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;

    fn png_bytes(width: u32, height: u32, value: u8) -> Vec<u8> {
        let mut buffer = image::RgbaImage::new(width, height);
        for pixel in buffer.pixels_mut() {
            *pixel = image::Rgba([value, value, value, 255]);
        }
        let mut out = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(buffer)
            .write_to(&mut out, image::ImageFormat::Png)
            .unwrap();
        out.into_inner()
    }

    /// 现造一个 CBZ：故意以乱序写入，并在其中混入非图片、macOS 资源与隐藏文件。
    fn write_cbz(path: &Path) {
        let file = File::create(path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default();
        writer.start_file("page10.jpg", options).unwrap();
        writer.write_all(&png_bytes(4, 4, 10)).unwrap();
        writer.start_file("page2.jpg", options).unwrap();
        writer.write_all(&png_bytes(4, 4, 2)).unwrap();
        writer.start_file("__MACOSX/page1.jpg", options).unwrap();
        writer.write_all(b"junk").unwrap();
        writer.start_file("readme.txt", options).unwrap();
        writer.write_all(b"junk").unwrap();
        writer.start_file("dir/", options).unwrap();
        writer.start_file("dir/page1.jpg", options).unwrap();
        writer.write_all(&png_bytes(4, 4, 1)).unwrap();
        writer.finish().unwrap();
    }

    #[test]
    fn enumerates_in_natural_order_and_skips_noise() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.cbz");
        write_cbz(&path);

        let pages = enumerate(&path).unwrap();
        let names: Vec<&str> = pages.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["dir/page1.jpg", "page2.jpg", "page10.jpg"]);
    }

    #[test]
    fn reads_every_page_back_by_index() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.cbz");
        write_cbz(&path);

        let pages = enumerate(&path).unwrap();
        for page in &pages {
            let Locator::ZipIndex(index) = page.locator else {
                panic!("expected zip locator");
            };
            let bytes = read_entry(&path, index).unwrap();
            let decoded = crate::decode::decode_rgba(&bytes).unwrap();
            assert_eq!((decoded.width, decoded.height), (4, 4));
        }
    }

    /// 两条**原始名不同、规范化后相同**的条目（`a\p.png` 与 `a/p.png`）
    /// 正是去重存在的理由：UI 不能显示两行一样的名字，而两条又必须各自可寻址。
    ///
    /// 顺带记一条实测结论：`zip` crate 的 writer **直接拒绝**写入完全重名的条目
    /// （`InvalidArchive("Duplicate filename: page.png")`），所以「真重名」的 ZIP
    /// 在本地造不出来——能造的只有这种「规范化后重名」。RAR 侧则真的有重名样本
    /// （见 `rar_source` 的内嵌夹具）。
    #[test]
    fn names_that_collide_only_after_normalization_get_unique_display_names() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("dup.cbz");
        {
            let file = File::create(&path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default();
            for (name, value) in [(r"a\p.png", 1u8), ("a/p.png", 2u8)] {
                writer.start_file(name, options).unwrap();
                writer.write_all(&png_bytes(2, 2, value)).unwrap();
            }
            writer.finish().unwrap();
        }

        let pages = enumerate(&path).unwrap();
        assert_eq!(pages.len(), 2, "两条条目都应当被列出");
        let mut names: Vec<&str> = pages.iter().map(|p| p.name.as_str()).collect();
        names.sort_unstable();
        assert_eq!(names, vec!["a/p (2).png", "a/p.png"]);

        let mut payloads = Vec::new();
        for page in &pages {
            let Locator::ZipIndex(index) = page.locator else {
                panic!("expected zip locator");
            };
            payloads.push(read_entry(&path, index).unwrap());
        }
        assert_ne!(
            payloads[0], payloads[1],
            "规范化后同名的条目必须各自可寻址（这就是 ZIP 用下标而不是用名字当句柄的原因）"
        );
    }
}
