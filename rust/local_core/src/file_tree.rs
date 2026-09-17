//! 跨平台本地文件树与漫画容器扫描模块。
//!
//! 继承自 mImageViewer 的跨平台目录与归档导航设计：
//! 1. 跨平台探测系统驱动器与常用位置（Windows 盘符、macOS /Volumes 挂载卷、用户主目录、下载目录等）；
//! 2. 目录项智能分类：子文件夹、漫画归档（CBZ/ZIP/CBR/RAR/7Z）、单张图片；
//! 3. 严格过滤系统垃圾与元数据（macOS `._*` AppleDouble、`.DS_Store`、`__MACOSX`、`Thumbs.db`）；
//! 4. 采用 `sort_natural` 自然数字排序（如 "001"、"002"、"010" 符合人类阅读直觉）。

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::entry_name::normalize_entry_name;
use crate::page_order::{is_image_name, should_ignore_name, sort_natural};

/// 根路径/常用位置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RootLocation {
    /// 显示标签，例如 "BOX (外接)"、"C:\"、"主目录"、"下载" 等。
    pub label: String,
    /// 绝对路径。
    pub path: String,
}

/// 树节点条目。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTreeNode {
    /// 完整绝对路径。
    pub path: String,
    /// 显示名称（文件名或目录名）。
    pub name: String,
    /// 是否为目录。
    pub is_dir: bool,
    /// 是否为漫画归档文件（ZIP / CBZ / CBR / RAR / 7Z / PDF）。
    pub is_archive: bool,
    /// 是否为单张支持的图片。
    pub is_image: bool,
    /// 文件大小（字节，目录为 0）。
    pub size: u64,
    /// 是否含有子项（对于目录：如果为空则为 false，有子项为 true）。
    pub has_children: bool,
}

/// 扩展名是否为漫画归档。
pub fn is_comic_archive_ext(ext: &str) -> bool {
    let lower = ext.to_ascii_lowercase();
    matches!(
        lower.as_str(),
        "zip" | "cbz" | "cbr" | "rar" | "7z" | "cb7" | "pdf"
    )
}

/// 路径是否为漫画归档文件。
pub fn is_comic_archive_path(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(is_comic_archive_ext)
        .unwrap_or(false)
}

/// 探测跨平台根路径与常用驱动器列表。
pub fn get_available_roots() -> Vec<RootLocation> {
    let mut roots = Vec::new();

    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Storage::FileSystem::{GetDriveTypeW, GetLogicalDrives};
        use windows::core::PCWSTR;

        let mask = unsafe { GetLogicalDrives() };
        for i in 0..26u32 {
            if (mask & (1 << i)) == 0 {
                continue;
            }
            let letter = (b'A' + i as u8) as char;
            let root_str = format!("{letter}:\\");
            let wide: Vec<u16> = root_str.encode_utf16().chain(std::iter::once(0)).collect();
            let drive_type = unsafe { GetDriveTypeW(PCWSTR(wide.as_ptr())) };
            // 排除不存在与未知类型的驱动器
            if drive_type != 0 && drive_type != 1 {
                roots.push(RootLocation {
                    label: format!("本地磁盘 ({letter}:)"),
                    path: root_str,
                });
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        // ① 扫描 /Volumes 下的所有挂载卷（外接硬盘、移动盘、U盘、网络盘等）
        let volumes = Path::new("/Volumes");
        if let Ok(entries) = fs::read_dir(volumes) {
            let mut vol_list = Vec::new();
            for entry in entries.flatten() {
                let p = entry.path();
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    if !name.starts_with('.') {
                        vol_list.push(RootLocation {
                            label: format!("卷: {name}"),
                            path: p.to_string_lossy().to_string(),
                        });
                    }
                }
            }
            sort_natural(&mut vol_list, |r| &r.label);
            roots.extend(vol_list);
        }
        // ② 根目录
        roots.push(RootLocation {
            label: "Macintosh HD (/)".to_string(),
            path: "/".to_string(),
        });
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        // Linux / Android / Unix
        roots.push(RootLocation {
            label: "根目录 (/)".to_string(),
            path: "/".to_string(),
        });
        for media_dir in &["/media", "/mnt"] {
            let p = Path::new(media_dir);
            if p.is_dir() {
                roots.push(RootLocation {
                    label: media_dir.to_string(),
                    path: media_dir.to_string(),
                });
            }
        }
    }

    // 常用用户目录（主目录、下载、图片、文稿、桌面）
    if let Some(home) = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")) {
        let home_path = PathBuf::from(home);
        if home_path.is_dir() {
            roots.push(RootLocation {
                label: "主目录 (~)".to_string(),
                path: home_path.to_string_lossy().to_string(),
            });

            for (sub, name) in &[
                ("Downloads", "下载 (Downloads)"),
                ("Pictures", "图片 (Pictures)"),
                ("Documents", "文稿 (Documents)"),
                ("Desktop", "桌面 (Desktop)"),
            ] {
                let p = home_path.join(sub);
                if p.is_dir() {
                    roots.push(RootLocation {
                        label: name.to_string(),
                        path: p.to_string_lossy().to_string(),
                    });
                }
            }
        }
    }

    roots
}

/// 列出指定目录下的条目（子目录、漫画归档、图片），按自然排序排列。
pub fn list_directory(dir_path: &Path) -> Result<Vec<FileTreeNode>> {
    if !dir_path.is_dir() {
        return Err(anyhow::anyhow!("路径不是有效目录: {}", dir_path.display()));
    }

    let read_dir = fs::read_dir(dir_path)
        .with_context(|| format!("读取目录失败: {}", dir_path.display()))?;

    let mut nodes = Vec::new();

    for entry_res in read_dir {
        let entry = match entry_res {
            Ok(e) => e,
            Err(_) => continue,
        };

        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        let raw_name = entry.file_name();
        let Some(name_str) = raw_name.to_str() else {
            continue;
        };

        // 过滤系统隐藏与噪音文件
        if name_str.starts_with('.') || should_ignore_name(name_str) {
            continue;
        }

        let Some(clean_name) = normalize_entry_name(name_str) else {
            continue;
        };

        let path = entry.path();
        let is_dir = file_type.is_dir();

        if is_dir {
            // 检查子目录是否非空（轻量探测一条即可）
            let has_children = fs::read_dir(&path)
                .map(|mut r| r.next().is_some())
                .unwrap_or(false);

            nodes.push(FileTreeNode {
                path: path.to_string_lossy().to_string(),
                name: clean_name,
                is_dir: true,
                is_archive: false,
                is_image: false,
                size: 0,
                has_children,
            });
        } else if file_type.is_file() {
            let is_archive = is_comic_archive_path(&path);
            let is_image = is_image_name(&clean_name);

            // 只收录漫画归档和支持的图片
            if is_archive || is_image {
                let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
                nodes.push(FileTreeNode {
                    path: path.to_string_lossy().to_string(),
                    name: clean_name,
                    is_dir: false,
                    is_archive,
                    is_image,
                    size,
                    has_children: false,
                });
            }
        }
    }

    // 排序策略：文件夹排在前面，漫画归档次之，图片最后；同类按自然名称排序
    nodes.sort_by(|a, b| {
        let rank_a = if a.is_dir {
            0
        } else if a.is_archive {
            1
        } else {
            2
        };
        let rank_b = if b.is_dir {
            0
        } else if b.is_archive {
            1
        } else {
            2
        };

        if rank_a != rank_b {
            rank_a.cmp(&rank_b)
        } else {
            crate::page_order::compare_natural(&a.name, &b.name)
        }
    });

    Ok(nodes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_available_roots() {
        let roots = get_available_roots();
        assert!(!roots.is_empty(), "必须能探测到至少一个根目录");
    }

    #[test]
    fn test_list_directory_filtering_and_sorting() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        // 构造测试文件
        fs::create_dir(root.join("SubDirB")).unwrap();
        fs::create_dir(root.join("SubDirA")).unwrap();
        fs::File::create(root.join("book 10.zip")).unwrap();
        fs::File::create(root.join("book 2.cbz")).unwrap();
        fs::File::create(root.join("cover.jpg")).unwrap();
        fs::File::create(root.join(".DS_Store")).unwrap();
        fs::File::create(root.join("._ignored.jpg")).unwrap();
        fs::File::create(root.join("readme.txt")).unwrap(); // txt 应当被过滤

        let nodes = list_directory(root).unwrap();

        // 应当包含：2 个文件夹，2 个归档，1 个图片 = 5 项
        assert_eq!(nodes.len(), 5);

        // 验证顺序：文件夹优先且自然排序
        assert_eq!(nodes[0].name, "SubDirA");
        assert!(nodes[0].is_dir);
        assert_eq!(nodes[1].name, "SubDirB");
        assert!(nodes[1].is_dir);

        // 归档自然排序：book 2.cbz 必须排在 book 10.zip 前面
        assert_eq!(nodes[2].name, "book 2.cbz");
        assert!(nodes[2].is_archive);
        assert_eq!(nodes[3].name, "book 10.zip");
        assert!(nodes[3].is_archive);

        // 图片项
        assert_eq!(nodes[4].name, "cover.jpg");
        assert!(nodes[4].is_image);
    }
}
