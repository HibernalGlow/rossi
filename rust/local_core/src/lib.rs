//! Rossi 本地漫画核心（v0.1 判据 A）。
//!
//! 只做一件事：**把一个本地来源打开成有序的页序列，并能按页取出字节或像素。**
//!
//! ```text
//! LocalSource::open(path)
//!   ├── 散图文件夹   folder_source
//!   ├── CBZ / ZIP    zip_source
//!   └── CBR / RAR    rar_source   ← 逐条目按需读，不落盘（ADR-0011）
//!         ↓
//!   Vec<PageEntry>  （自然序，页序正确）
//!         ↓
//!   page_bytes(i) → decode::decode_rgba(i) → PagePixels
//! ```
//!
//! ## 这一层**不**做什么
//!
//! - 不持有会话状态、不持有归档句柄、不做缓存淘汰（那属于 Reader 层）；
//! - 不做上屏、不认识 wgpu / Flutter；
//! - 不做 tile 化、预取、超分（Phase 2/3 的事）。
//!
//! 这样切的目的是让「连读三本内存不增长」（判据 D）成为这一层的**结构性事实**，
//! 而不是某个缓存策略是否写对的结果。

pub mod decode;
pub mod entry_name;
pub mod folder_source;
pub mod page_order;
pub mod rar_source;
pub mod zip_source;

use std::fmt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

pub use decode::{PagePixels, ShellOnlyFormat, decode_rgba, decode_rgba_scaled, probe_size};
pub use page_order::{DecodeSupport, decode_support, is_image_name, needs_shell_decoder};
pub use rar_source::{
    RarDirectReadDecision, RarInspection, RarVolumeKind, ensure_direct_readable, inspect,
    is_rar_path,
};

/// 来源类型。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceKind {
    Folder,
    Zip,
    Rar,
}

impl SourceKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Folder => "folder",
            Self::Zip => "zip",
            Self::Rar => "rar",
        }
    }
}

/// 一页在来源里的定位方式。
///
/// 每种来源各有各的最优句柄：文件夹用相对路径、ZIP 用中央目录下标、
/// RAR 用归档内条目名。**不强行统一成一个字符串**，是因为 ZIP 用名字寻址会在
/// 同名条目上读错那一条（见 `zip_source` 的模块注释）。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Locator {
    /// 相对 `root` 的路径，`/` 分隔。
    FolderPath(String),
    /// `ZipArchive::by_index` 的下标。
    ZipIndex(usize),
    /// 归档内条目名（已规范化、去重）。
    RarEntryName(String),
}

/// 页序列里的一项。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PageEntry {
    /// 展示名（也是排序依据）。同名条目在这里已经被唯一化。
    pub name: String,
    /// 未压缩字节数。文件夹来源为文件长度。
    pub size: u64,
    pub locator: Locator,
}

/// 打开来源时**可被调用方精确识别**的拒绝原因。
///
/// 用类型而不是错误字符串，是因为 UI 需要按类别给出不同提示
/// （「这本是固实压缩的 RAR，v0.1 打不开」和「这文件损坏了」不是一回事）。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UnsupportedSource {
    /// 扩展名不在 v0.1 范围内（7z / PDF / 视频……）。
    UnknownFormat(String),
    /// 固实 RAR：读第 N 页要解压前 N-1 页，代价随页数平方增长。
    RarSolid,
    /// 归档里含嵌套归档。内层必须先落地成路径才能打开，v0.1 不实现。
    RarNestedArchive,
    /// 加密 RAR：v0.1 不提供密码输入。
    RarEncrypted,
}

impl fmt::Display for UnsupportedSource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownFormat(ext) => {
                write!(f, "v0.1 只支持散图文件夹 / CBZ / CBR，不支持 .{ext}")
            }
            Self::RarSolid => write!(f, "这是固实（solid）压缩的 RAR，v0.1 不支持直读"),
            Self::RarNestedArchive => write!(f, "归档里含嵌套归档，v0.1 不展开"),
            Self::RarEncrypted => write!(f, "这是加密的 RAR，v0.1 不支持"),
        }
    }
}

impl std::error::Error for UnsupportedSource {}

/// 一个已打开的本地来源。
///
/// 只保存「根路径 + 类型 + 页序列」——**不保存任何打开的文件/归档对象**。
#[derive(Clone, Debug)]
pub struct LocalSource {
    root: PathBuf,
    kind: SourceKind,
    pages: Vec<PageEntry>,
}

impl LocalSource {
    /// 按路径打开：目录、`.zip`/`.cbz`、`.rar`/`.cbr`。
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let root = path.as_ref().to_path_buf();
        let meta =
            std::fs::metadata(&root).with_context(|| format!("找不到来源: {}", root.display()))?;

        if meta.is_dir() {
            let pages = folder_source::enumerate(&root)?;
            return Ok(Self {
                root,
                kind: SourceKind::Folder,
                pages,
            });
        }

        let ext = root
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_ascii_lowercase())
            .unwrap_or_default();

        let (kind, pages) = match ext.as_str() {
            "zip" | "cbz" => (SourceKind::Zip, zip_source::enumerate(&root)?),
            "rar" | "cbr" => (SourceKind::Rar, rar_source::enumerate_pages(&root)?),
            other => {
                return Err(anyhow::Error::new(UnsupportedSource::UnknownFormat(
                    other.to_string(),
                )));
            }
        };
        Ok(Self { root, kind, pages })
    }

    pub fn kind(&self) -> SourceKind {
        self.kind
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn pages(&self) -> &[PageEntry] {
        &self.pages
    }

    pub fn is_empty(&self) -> bool {
        self.pages.is_empty()
    }

    pub fn len(&self) -> usize {
        self.pages.len()
    }

    pub fn total_bytes(&self) -> u64 {
        self.pages.iter().map(|page| page.size).sum()
    }

    /// 取一页的**编码字节**（JPEG/PNG/…，不是像素）。
    ///
    /// 每次调用都重新打开来源：内存占用与读过的页数无关（判据 D）。
    pub fn page_bytes(&self, index: usize) -> Result<Vec<u8>> {
        let page = self
            .pages
            .get(index)
            .with_context(|| format!("页下标越界: {index} / {}", self.pages.len()))?;
        match &page.locator {
            Locator::FolderPath(rel) => folder_source::read_page(&self.root, rel),
            Locator::ZipIndex(index) => zip_source::read_entry(&self.root, *index),
            Locator::RarEntryName(name) => rar_source::read_entry(&self.root, name),
        }
        .with_context(|| format!("读取第 {} 页失败: {}", index + 1, page.name))
    }

    /// 取一页的像素（RGBA8），按原尺寸。
    ///
    /// **只对核心能解的格式成立**（`DecodeSupport::Core`）。归档里出现
    /// `avif` / `jxl` / `heic` 这类页时返回 `ShellOnlyFormat` 而不是笼统的解码失败：
    /// 那些页要靠外壳（Flutter/Skia）显示，类别信息得留给调用方。
    ///
    /// 显示路径请用 [`Self::page_pixels_scaled`]：原尺寸的 44.8 MPix 会解出
    /// 179 MB 位图，而这条路径后面还有两次等量拷贝（过桥 + 建纹理）。
    pub fn page_pixels(&self, index: usize) -> Result<PagePixels> {
        self.page_pixels_scaled(index, None)
    }

    /// 取一页的像素（RGBA8），按 `target_width` 降采样。
    ///
    /// `target_width` 为 `None` / `0` / 不小于原宽时等价于 [`Self::page_pixels`]（**不放大**）。
    /// 尺寸与取舍依据见 [`decode::decode_rgba_scaled`]。
    pub fn page_pixels_scaled(
        &self,
        index: usize,
        target_width: Option<u32>,
    ) -> Result<PagePixels> {
        self.ensure_core_decodable(index)?;
        decode_rgba_scaled(&self.page_bytes(index)?, target_width)
    }

    /// 这一页由谁解码。下标越界返回 `None`。
    pub fn page_decode_support(&self, index: usize) -> Option<DecodeSupport> {
        self.pages
            .get(index)
            .and_then(|page| decode_support(&page.name))
    }

    /// 挡在核心解码之前的闸门：把「没有解码器」与「解不出来」分开。
    fn ensure_core_decodable(&self, index: usize) -> Result<()> {
        let page = self
            .pages
            .get(index)
            .with_context(|| format!("页下标越界: {index} / {}", self.pages.len()))?;
        if decode_support(&page.name) == Some(DecodeSupport::ShellOnly) {
            return Err(anyhow::Error::new(ShellOnlyFormat {
                extension: crate::page_order::extension_lower(&page.name).unwrap_or_default(),
            }))
            .with_context(|| format!("第 {} 页无法由核心解码: {}", index + 1, page.name));
        }
        Ok(())
    }

    /// 只读尺寸，不做完整解码。
    pub fn page_size(&self, index: usize) -> Result<(u32, u32)> {
        probe_size(&self.page_bytes(index)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn unknown_extensions_are_rejected_with_a_typed_reason() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.7z");
        std::fs::write(&path, b"7z\xBC\xAF\x27\x1C").unwrap();

        let error = LocalSource::open(&path).unwrap_err();
        let reason = error
            .downcast_ref::<UnsupportedSource>()
            .expect("应当是类型化的拒绝原因");
        assert_eq!(reason, &UnsupportedSource::UnknownFormat("7z".into()));
    }

    #[test]
    fn missing_paths_report_the_path() {
        let dir = tempfile::tempdir().unwrap();
        let error = LocalSource::open(dir.path().join("nope.cbz")).unwrap_err();
        assert!(error.to_string().contains("nope.cbz"), "{error}");
    }

    #[test]
    fn opens_a_cbz_and_exposes_pages_in_order() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.cbz");
        {
            let file = std::fs::File::create(&path).unwrap();
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::SimpleFileOptions::default();
            for name in ["p10.png", "p2.png", "p1.png"] {
                zip.start_file(name, options).unwrap();
                let mut buffer = image::RgbaImage::new(3, 2);
                for pixel in buffer.pixels_mut() {
                    *pixel = image::Rgba([200, 100, 50, 255]);
                }
                let mut bytes = std::io::Cursor::new(Vec::new());
                image::DynamicImage::ImageRgba8(buffer)
                    .write_to(&mut bytes, image::ImageFormat::Png)
                    .unwrap();
                zip.write_all(&bytes.into_inner()).unwrap();
            }
            zip.finish().unwrap();
        }

        let source = LocalSource::open(&path).unwrap();
        assert_eq!(source.kind(), SourceKind::Zip);
        assert_eq!(source.len(), 3);
        assert!(!source.is_empty());
        let names: Vec<&str> = source.pages().iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["p1.png", "p2.png", "p10.png"]);

        // 首末页都能真的读出并解码（判据 A 的「读到最后一页」）
        for index in [0, 2] {
            let pixels = source.page_pixels(index).unwrap();
            assert_eq!((pixels.width, pixels.height), (3, 2));
        }
        assert_eq!(source.page_size(1).unwrap(), (3, 2));
    }

    #[test]
    fn out_of_range_page_index_is_an_error_not_a_panic() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("empty");
        std::fs::create_dir(&path).unwrap();
        let source = LocalSource::open(&path).unwrap();
        assert!(source.is_empty());
        assert!(source.page_bytes(0).is_err());
    }

    /// 归档里混着 jxl（核心不能解）与 png（能解）时：
    /// 两者**都要出现在页序里**，但只有后者能从核心拿像素。
    ///
    /// 用垃圾字节冒充 jxl 是刻意的：闸门必须在**解码之前**生效，
    /// 所以「内容不是合法 jxl」这件事根本不该被读到。
    ///
    /// 这一条原先拿 `avif` 当例子。`avif` 打开 dav1d 之后搬到了核心档，
    /// 所以回归线换了人 —— 留着旧断言等于在测一个已经不存在的行为。
    /// `avif` 的归属现在按 feature 分支断言（见 `page_order.rs` 的测试）。
    #[test]
    fn shell_only_pages_are_listed_but_rejected_by_the_core_decoder() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("mixed.cbz");
        {
            let file = std::fs::File::create(&path).unwrap();
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::SimpleFileOptions::default();
            for name in ["1.png", "2.jxl", "3.png"] {
                zip.start_file(name, options).unwrap();
                let mut buffer = image::RgbaImage::new(2, 2);
                for pixel in buffer.pixels_mut() {
                    *pixel = image::Rgba([1, 2, 3, 255]);
                }
                let mut bytes = std::io::Cursor::new(Vec::new());
                image::DynamicImage::ImageRgba8(buffer)
                    .write_to(&mut bytes, image::ImageFormat::Png)
                    .unwrap();
                zip.write_all(&bytes.into_inner()).unwrap();
            }
            zip.finish().unwrap();
        }

        let source = LocalSource::open(&path).unwrap();
        assert_eq!(source.len(), 3, "jxl 也应当算作一页");
        assert_eq!(source.page_decode_support(0), Some(DecodeSupport::Core));
        assert_eq!(
            source.page_decode_support(1),
            Some(DecodeSupport::ShellOnly)
        );
        assert_eq!(source.page_decode_support(9), None, "越界应当是 None");

        // 核心能解的那两页照常
        assert_eq!(source.page_pixels(0).unwrap().width, 2);

        // 中间那页：必须是**类型化的**「外壳才解得动」，而不是笼统的解码失败
        let error = source.page_pixels(1).unwrap_err();
        let reason = error
            .downcast_ref::<ShellOnlyFormat>()
            .expect("应当是类型化的 ShellOnlyFormat");
        assert_eq!(reason.extension, "jxl");
    }
}
