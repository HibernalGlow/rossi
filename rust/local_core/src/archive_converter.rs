//! 直接从 mImageViewer archive_converter 选取格式与分卷判定；不是完整转换器。
//! Copyright (c) 2026 SANO Taku (Mikage Sawatari), MIT.
//! 构建时读取子模块源码；只排除未接入转换运行时的 temp_suffix。
use crate::folder_tree::path_eq;
use std::path::Path;
include!(concat!(env!("OUT_DIR"), "/archive_metadata.rs"));

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_zip_is_not_a_conversion_candidate() {
        for ext in ["zip", "CBZ"] {
            assert_eq!(ArchiveFormat::from_extension(ext), None);
            assert_eq!(
                ArchiveFormat::nested_from_extension(ext),
                Some(ArchiveFormat::Zip)
            );
        }
        assert_eq!(
            ArchiveFormat::from_extension("CB7"),
            Some(ArchiveFormat::SevenZ)
        );
        assert_eq!(ArchiveFormat::convertible_labels(), "RAR / 7z / LZH");
    }
    #[test]
    fn later_rar_parts_are_detected_beyond_the_first_few_numbers() {
        for name in [
            "a.part02.rar",
            "a.part04.rar",
            "a.part11.RAR",
            "a.part111.rar",
        ] {
            assert!(looks_like_non_first_rar_part(Path::new(name)), "{name}");
        }
        for name in [
            "a.rar",
            "a.cbr",
            "a.part01.rar",
            "a.part1.RAR",
            "a.r00",
            "a.r01",
        ] {
            assert!(!looks_like_non_first_rar_part(Path::new(name)), "{name}");
        }
    }
}
