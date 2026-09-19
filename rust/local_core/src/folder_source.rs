//! 散图文件夹来源。
//!
//! 两步策略，先便宜后昂贵：
//!
//! 1. **平铺**：只列 `root` 的直接子文件。这是「一个文件夹就是一本书」的常见形态，
//!    也是最便宜的。
//! 2. 平铺结果为空时才**递归**——因为「书籍目录 / 章节目录 / 页」这种结构同样常见，
//!    而它和第 1 步的判定信号是互斥的（有直接子文件就说明不是章节结构）。
//!
//! 不跟随符号链接：`file_type()` 不解析链接，所以既避免了目录环，也避免了
//! 「一本书的页散落在链接外的磁盘上」这种会让验收口径失控的情况。

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};

use crate::entry_name::normalize_entry_name;
use crate::page_order::{is_page_name, should_ignore_name, sort_natural};
use crate::{Locator, PageEntry};

/// 平铺阶段的页数上限（见 `MAX_FILES`）。
const MAX_DEPTH: usize = 8;
/// 递归阶段的总文件数上限。
///
/// 超限直接报错而不是截断：用户把「整个漫画库根目录」拖进来时说「读到第 20000 页为止」
/// 比报错更糟——它看起来像成功了。
const MAX_FILES: usize = 20_000;

/// 枚举一个文件夹里的页面。
pub fn enumerate(root: &Path) -> Result<Vec<PageEntry>> {
    if !root.is_dir() {
        bail!("不是文件夹: {}", root.display());
    }

    let mut flat = Vec::new();
    collect_dir(root, root, false, 0, &mut flat)?;
    if !flat.is_empty() {
        finish(&mut flat);
        return Ok(flat);
    }

    let mut deep = Vec::new();
    collect_dir(root, root, true, 0, &mut deep)?;
    finish(&mut deep);
    Ok(deep)
}

fn finish(pages: &mut Vec<PageEntry>) {
    sort_natural(pages, |page| match &page.locator {
        Locator::FolderPath(rel) => rel.as_str(),
        _ => page.name.as_str(),
    });
}

fn collect_dir(
    root: &Path,
    dir: &Path,
    recurse: bool,
    depth: usize,
    out: &mut Vec<PageEntry>,
) -> Result<()> {
    let read = fs::read_dir(dir).with_context(|| format!("无法列出目录: {}", dir.display()))?;
    for entry in read {
        let entry = entry.with_context(|| format!("读取目录项失败: {}", dir.display()))?;
        let file_type = entry.file_type().context("读取目录项类型失败")?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            // 非 UTF-8 名字无法在归档/文件夹之间统一表示，跳过而不是猜。
            continue;
        };

        let path = entry.path();
        let rel = relative_slash(root, &path)?;
        if should_ignore_name(&rel) {
            continue;
        }

        if file_type.is_file() {
            if !is_page_name(name) {
                continue;
            }
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            out.push(PageEntry {
                name: rel.clone(),
                size,
                locator: Locator::FolderPath(rel),
            });
            if out.len() > MAX_FILES {
                bail!("文件夹里的文件超过 {MAX_FILES} 个上限，请直接指向某一本书的目录");
            }
        } else if file_type.is_dir() && recurse {
            if depth + 1 >= MAX_DEPTH {
                bail!("目录层级超过 {MAX_DEPTH} 层，请直接指向某一本书的目录");
            }
            collect_dir(root, &path, recurse, depth + 1, out)?;
        }
    }
    Ok(())
}

/// 相对路径转成 `/` 分隔的形式（页序与句柄都按这个形式）。
fn relative_slash(root: &Path, path: &Path) -> Result<String> {
    let rel = path
        .strip_prefix(root)
        .with_context(|| format!("{} 不在 {} 下", path.display(), root.display()))?;
    let text = rel.to_string_lossy().replace('\\', "/");
    normalize_entry_name(&text).with_context(|| format!("非法文件名: {text}"))
}

/// 读取一页。
pub fn read_page(root: &Path, rel: &str) -> Result<Vec<u8>> {
    let Some(rel) = normalize_entry_name(rel) else {
        bail!("非法相对路径: {rel}");
    };
    let path: PathBuf = root.join(rel.replace('/', std::path::MAIN_SEPARATOR_STR));
    fs::read(&path).with_context(|| format!("读取失败: {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn write(path: &Path, bytes: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, bytes).unwrap();
    }

    #[test]
    fn flat_folder_is_sorted_naturally_and_skips_noise() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        write(&root.join("page10.jpg"), b"x");
        write(&root.join("page2.jpg"), b"x");
        write(&root.join("page1.jpg"), b"x");
        write(&root.join("cover.JPEG"), b"x");
        // 噪声：非图片、macOS 资源叉、隐藏文件、子目录（平铺阶段不递归）
        write(&root.join("notes.txt"), b"x");
        write(&root.join("._page1.jpg"), b"x");
        write(&root.join(".DS_Store"), b"x");
        write(&root.join("extras/page1.jpg"), b"x");

        let pages = enumerate(root).unwrap();
        let names: Vec<&str> = pages.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(
            names,
            vec!["cover.JPEG", "page1.jpg", "page2.jpg", "page10.jpg"]
        );
        assert!(matches!(pages[0].locator, Locator::FolderPath(_)));
    }

    #[test]
    fn falls_back_to_recursion_when_there_are_no_direct_files() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        write(&root.join("ch1/2.jpg"), b"x");
        write(&root.join("ch1/1.jpg"), b"x");
        write(&root.join("ch2/1.jpg"), b"x");

        let pages = enumerate(root).unwrap();
        let names: Vec<&str> = pages.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["ch1/1.jpg", "ch1/2.jpg", "ch2/1.jpg"]);
    }

    #[test]
    fn reads_a_page_back_by_its_locator() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        write(&root.join("ch1/1.jpg"), b"payload-a");
        write(&root.join("ch1/2.jpg"), b"payload-b");

        let pages = enumerate(root).unwrap();
        let first = pages.first().unwrap();
        let Locator::FolderPath(rel) = &first.locator else {
            panic!("expected folder locator");
        };
        assert_eq!(read_page(root, rel).unwrap(), b"payload-a");
    }

    #[test]
    fn rejects_paths_that_escape_the_root() {
        let dir = tempfile::tempdir().unwrap();
        assert!(read_page(dir.path(), "../oops.jpg").is_err());
        // 前导 `/` 会被规范化掉，于是变成一个根下不存在的相对路径 -> 仍然是错误
        assert!(read_page(dir.path(), "/abs.jpg").is_err());
    }
}
