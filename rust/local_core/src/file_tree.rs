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

use crate::filename_sort::SortNameKey;
use crate::folder_tree::{is_convertible_archive_path, is_recognized_image_ext, is_virtual_folder};
// `sort_natural` 只在 macOS 分支用（/Volumes 卷列表要按自然序排），
// 无条件 import 会在 Windows/Linux 上触发 unused_imports。
#[cfg(target_os = "macos")]
use crate::page_order::sort_natural;

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
    /// 是否为 mImageViewer 支持的视频媒体。
    pub is_video: bool,
    /// 是否为 mImageViewer 支持的音频媒体。
    pub is_audio: bool,
    /// 文件大小（字节，目录为 0）。
    pub size: u64,
    /// 修改时间（秒数时间戳，获取失败为 0）。
    pub modified_secs: i64,
    /// 是否含有子项（对于目录：如果为空则为 false，有子项为 true）。
    pub has_children: bool,
}

/// 扩展名是否为漫画归档。
pub fn is_comic_archive_ext(ext: &str) -> bool {
    let lower = ext.to_ascii_lowercase();
    is_virtual_folder(Path::new(&format!("file.{lower}")))
        || is_convertible_archive_path(Path::new(&format!("file.{lower}")))
}

/// 路径是否为漫画归档文件。
pub fn is_comic_archive_path(path: &Path) -> bool {
    is_virtual_folder(path) || is_convertible_archive_path(path)
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

/// 列出指定目录下的条目（子目录、漫画归档、图片），按 mImageViewer 的源码排序。
///
/// 这里刻意不复制一套「近似的」文件系统判定：目录项类型、隐藏项、AppleDouble、
/// 内置扩展名和归档类型都直接调用 `vendor/mimageviewer/src` 的函数。Rossi 只把
/// 结果投影成自己的跨 UI DTO。
pub fn list_directory(dir_path: &Path) -> Result<Vec<FileTreeNode>> {
    list_directory_with_hidden(dir_path, false)
}

/// 把单个 `DirEntry` 投影成 `FileTreeNode`，并就地执行 mImageViewer 的隐藏项、
/// AppleDouble、内部 bundle 与「已识别媒体」策略。
///
/// 整目录列举与递归搜索**必须**走这一个函数：前者要画列表，后者要交出结果页签，
/// 两边各写一套扩展名判定的话，搜索结果里就会出现列表里根本不存在（或反过来被
/// 隐藏规则滤掉）的条目。
///
/// `probe_children` 关掉时目录的 `has_children` 一律为 `false`。列表需要它来画展开
/// 箭头；递归搜索只为**命中**的那几条构造节点，为扫过的每个目录多开一次 `read_dir`
/// 会让整趟遍历慢一倍。
pub fn node_for_dir_entry(
    entry: &fs::DirEntry,
    file_type: &fs::FileType,
    show_hidden_files: bool,
    probe_children: bool,
) -> Option<FileTreeNode> {
    let raw_name = entry.file_name();
    // mImageViewer 的 bundle / Windows 属性 / Unix 隐藏项规则必须在这里统一执行。
    if crate::fs_entry::is_internal_app_entry_name(&raw_name)
        || crate::fs_entry::should_hide_fs_entry(entry, show_hidden_files)
    {
        return None;
    }
    let name_str = raw_name.to_str()?;
    let path = entry.path();
    let entry_kind = crate::fs_entry::classify_dir_entry(entry, file_type);
    if entry_kind.is_directory() {
        // 检查子目录是否非空（轻量探测一条即可）
        let has_children = probe_children
            && fs::read_dir(&path)
                .map(|mut r| r.next().is_some())
                .unwrap_or(false);
        let metadata = entry.metadata().ok();
        let modified_secs = metadata
            .as_ref()
            .map(crate::ui_helpers::mtime_secs)
            .unwrap_or(0);
        return Some(FileTreeNode {
            path: path.to_string_lossy().to_string(),
            name: name_str.to_owned(),
            is_dir: true,
            is_archive: false,
            is_image: false,
            is_video: false,
            is_audio: false,
            size: 0,
            modified_secs,
            has_children,
        });
    }
    if !entry_kind.is_file() || crate::folder_tree::is_apple_double(&path) {
        return None;
    }
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.to_ascii_lowercase())
        .unwrap_or_default();
    let is_archive = is_virtual_folder(&path) || is_convertible_archive_path(&path);
    let is_image = is_recognized_image_ext(&extension);
    let is_video = crate::media_formats::is_video_ext(&extension);
    let is_audio = crate::folder_tree::is_audio_ext(&extension);

    // 图片、视频与容器可交给 Reader；音频保留在列表中供浏览。
    let is_supported_media = is_archive || is_image || is_video || is_audio;
    // 只收录 mImageViewer 已识别的媒体/容器，未知文档不会污染漫画 Reader。
    if !is_supported_media {
        return None;
    }
    let metadata = entry.metadata().ok();
    let size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
    let modified_secs = metadata
        .as_ref()
        .map(crate::ui_helpers::mtime_secs)
        .unwrap_or(0);
    Some(FileTreeNode {
        path: path.to_string_lossy().to_string(),
        name: name_str.to_owned(),
        is_dir: false,
        is_archive,
        is_image,
        is_video,
        is_audio,
        size,
        modified_secs,
        has_children: false,
    })
}

/// List a directory with the same mImageViewer classification and sorting
/// rules, optionally retaining user-hidden entries.  OS/system entries and
/// Rossi/mImageViewer metadata bundles remain hidden in both modes.
pub fn list_directory_with_hidden(
    dir_path: &Path,
    show_hidden_files: bool,
) -> Result<Vec<FileTreeNode>> {
    if !dir_path.is_dir() {
        return Err(anyhow::anyhow!("路径不是有效目录: {}", dir_path.display()));
    }

    let read_dir =
        fs::read_dir(dir_path).with_context(|| format!("读取目录失败: {}", dir_path.display()))?;

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

        let Some(node) = node_for_dir_entry(&entry, &file_type, show_hidden_files, true) else {
            continue;
        };
        nodes.push(node);
    }

    // 排序策略保持 mImageViewer 的 FileNameSortKey：文件夹排在前面，漫画归档次之，
    // 图片/视频/音频最后；同类使用同一份大小写、数字和 Windows 排序键。
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

        rank_a.cmp(&rank_b).then_with(|| {
            SortNameKey::with_natural(&a.name).compare_natural(&SortNameKey::with_natural(&b.name))
        })
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

    /// 回归线：`.wbp`（改名的 WebP）与 `.apng` 曾在文件管理器里**完全不出现**。
    ///
    /// 根因是这里查的表（`folder_tree::SUPPORTED_EXTENSIONS`）与阅读器页序查的表
    /// （`page_order::CORE_DECODABLE_EXTENSIONS`）是两张，只补后者等于「翻开书能看见、
    /// 列表里没有」。症状不对称，所以两边都要有断言钉着。
    #[test]
    fn alias_suffixes_are_listed_as_images() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        for name in ["motion.wbp", "loop.apng", "page.png", "note.txt"] {
            fs::File::create(root.join(name)).unwrap();
        }

        let nodes = list_directory(root).unwrap();
        let names: Vec<&str> = nodes.iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, vec!["loop.apng", "motion.wbp", "page.png"]);
        for node in &nodes {
            assert!(node.is_image, "{} 应当算图片", node.name);
        }
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
        fs::File::create(root.join("clip.mp4")).unwrap();
        fs::File::create(root.join("song.mp3")).unwrap();
        fs::File::create(root.join(".DS_Store")).unwrap();
        fs::File::create(root.join("._ignored.jpg")).unwrap();
        fs::File::create(root.join("readme.txt")).unwrap(); // txt 应当被过滤

        let nodes = list_directory(root).unwrap();

        // 应当包含：2 个文件夹，2 个归档，图片/视频/音频各 1 项 = 7 项
        assert_eq!(nodes.len(), 7);

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

        // 图片/视频/音频都沿用 mImageViewer 的源码扩展名判定。
        assert_eq!(nodes[4].name, "clip.mp4");
        assert!(nodes[4].is_video);
        assert_eq!(nodes[5].name, "cover.jpg");
        assert!(nodes[5].is_image);
        assert_eq!(nodes[6].name, "song.mp3");
        assert!(nodes[6].is_audio);
    }
}
