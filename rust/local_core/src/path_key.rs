// Vendored from vendor/mimageviewer/src/path_key.rs (MIT License)
// 保留函数名与实现，用于 SQLite Catalog 数据库路径与 Key 规范化。

use std::path::Path;

/// 是否为驱动器根目录（如 `C:\`）或按共享根目录处理的路径。
pub fn is_drive_or_share_root(path: &Path) -> bool {
    if path.parent().is_none() {
        return true;
    }
    let s = path.to_string_lossy();
    if s.len() >= 2 && s.chars().nth(1) == Some(':') {
        let remainder = &s[2..];
        remainder.is_empty() || remainder == "\\" || remainder == "/"
    } else {
        false
    }
}

/// 返回去除驱动器字母、统一为小写与正斜杠的路径字符串。
pub fn normalize(path: &Path) -> String {
    let s = path.to_string_lossy();
    let no_drive = if s.len() >= 2 && s.chars().nth(1) == Some(':') {
        &s[2..]
    } else {
        &s
    };
    no_drive.to_lowercase().replace('\\', "/")
}

/// 返回 **保留** 驱动器字母、统一为小写与正斜杠的路径字符串。
pub fn normalize_keep_drive(path: &Path) -> String {
    path.to_string_lossy().to_lowercase().replace('\\', "/")
}

/// 对 DB 键与实际文件枚举结果这类书写方式可能不同的 2 个路径，
/// 按与 `normalize_keep_drive` 相同的规则进行比较。
pub fn eq_keep_drive(a: &Path, b: &Path) -> bool {
    normalize_keep_drive(a) == normalize_keep_drive(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_drive_letter() {
        assert_eq!(normalize(Path::new(r"C:\Foo\Bar")), "/foo/bar");
        assert_eq!(
            normalize(Path::new(r"D:\Photos\IMG.jpg")),
            "/photos/img.jpg"
        );
    }

    #[test]
    fn no_drive_letter_passthrough() {
        assert_eq!(normalize(Path::new("/foo/bar")), "/foo/bar");
        assert_eq!(
            normalize(Path::new(r"\\server\share\file")),
            "//server/share/file"
        );
    }

    #[test]
    fn lowercases_and_unifies_slashes() {
        assert_eq!(
            normalize(Path::new(r"C:\Mixed/Slash\Path")),
            "/mixed/slash/path"
        );
    }
}
