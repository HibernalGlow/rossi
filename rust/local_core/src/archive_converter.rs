//! mImageViewer `archive_converter` 中文件管理器需要的扩展名判定。

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArchiveFormat {
    Rar,
    SevenZip,
    Lzh,
}

impl ArchiveFormat {
    pub fn from_extension(extension: &str) -> Option<Self> {
        match extension.to_ascii_lowercase().as_str() {
            "rar" | "cbr" => Some(Self::Rar),
            "7z" | "cb7" => Some(Self::SevenZip),
            "lzh" | "lha" => Some(Self::Lzh),
            _ => None,
        }
    }
}

pub fn looks_like_non_first_rar_part(path: &std::path::Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            let lower = name.to_ascii_lowercase();
            lower.ends_with(".part2.rar")
                || lower.ends_with(".part3.rar")
                || lower.ends_with(".r01")
                || lower.ends_with(".r02")
        })
}
