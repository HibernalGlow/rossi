// Vendored from vendor/mimageviewer/src/path_key.rs (MIT License)
// 保留函数名与实现，用于 SQLite Catalog 数据库路径与 Key 规范化。

use std::path::Path;

/// ドライブルート (`C:\` など) または共有ルートとして扱うパスか。
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

/// ドライブ文字を除いて小文字化・スラッシュ統一したパス文字列を返す。
pub fn normalize(path: &Path) -> String {
    let s = path.to_string_lossy();
    let no_drive = if s.len() >= 2 && s.chars().nth(1) == Some(':') {
        &s[2..]
    } else {
        &s
    };
    no_drive.to_lowercase().replace('\\', "/")
}

/// ドライブ文字を **保持** したまま小文字化・スラッシュ統一したパス文字列を返す。
pub fn normalize_keep_drive(path: &Path) -> String {
    path.to_string_lossy().to_lowercase().replace('\\', "/")
}

/// DB キーと実ファイル列挙結果のように、表記が異なり得る 2 パスを
/// `normalize_keep_drive` と同じ規則で比較する。
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
