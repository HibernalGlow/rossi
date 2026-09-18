//! 归档条目名：规范化与同名去重。
//!
//! 移植自 mImageViewer `archive_converter` 里的 `normalize_entry_name` /
//! `dedup_entry_name`（MIT），语义保持一致，因为它决定了两件事：
//!
//! 1. **页序的输入**——规范化之后才排序，所以 `a\b.jpg` 与 `a/b.jpg` 是同一条；
//! 2. **页的可寻址性**——归档里两条不同原始名可能规范化成同一个名字
//!    （`a\b.jpg` 与 `a/b.jpg`），如果 UI 用名字当句柄，其中一条就永远读不到。

use std::collections::HashSet;

/// 把条目名规范成 ZIP 标准的相对路径，并拒绝危险形式。
///
/// - `\` → `/`（RAR 里普遍用反斜杠）
/// - 去掉前导 `/`，去掉尾部 `/`（目录）
/// - 含 `.` / `..` 段的一律拒绝（zip-slip）
///
/// 我们自己从不把条目写到磁盘，所以这条防线的目的不是防目录穿越，
/// 而是**保证名字是干净的相对路径**——页句柄、缓存键、日志都依赖这一点。
pub fn normalize_entry_name(raw: &str) -> Option<String> {
    let s = raw.replace('\\', "/");
    let s = s.trim_matches('/');
    if s.is_empty() {
        return None;
    }
    if s.split('/')
        .any(|seg| seg.is_empty() || seg == "." || seg == "..")
    {
        return None;
    }
    Some(s.to_string())
}

/// 与已出现过的名字冲突时，在扩展名前插入 ` (N)` 使其唯一。
///
/// 返回的可能是**新名字**，所以调用方必须把返回值当作真正的页名使用。
pub fn dedup_entry_name(name: String, seen: &mut HashSet<String>) -> String {
    if seen.insert(name.clone()) {
        return name;
    }
    let (stem, ext) = match name.rfind('.') {
        Some(i) => (&name[..i], &name[i..]), // ext 含前导点
        None => (name.as_str(), ""),
    };
    let mut n = 2usize;
    loop {
        let candidate = format!("{stem} ({n}){ext}");
        if seen.insert(candidate.clone()) {
            return candidate;
        }
        n += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalization_unifies_separators_and_trims() {
        assert_eq!(
            normalize_entry_name(r"a\b\1.jpg").as_deref(),
            Some("a/b/1.jpg")
        );
        assert_eq!(normalize_entry_name("/a/1.jpg").as_deref(), Some("a/1.jpg"));
        assert_eq!(normalize_entry_name("a/1.jpg/").as_deref(), Some("a/1.jpg"));
        assert_eq!(normalize_entry_name("1.jpg").as_deref(), Some("1.jpg"));
    }

    #[test]
    fn normalization_rejects_dangerous_and_empty_names() {
        assert_eq!(normalize_entry_name(""), None);
        assert_eq!(normalize_entry_name("/"), None);
        assert_eq!(normalize_entry_name("../1.jpg"), None);
        assert_eq!(normalize_entry_name("a/../../1.jpg"), None);
        assert_eq!(normalize_entry_name("a//1.jpg"), None);
    }

    #[test]
    fn duplicate_names_are_disambiguated_in_a_stable_order() {
        let mut seen = HashSet::new();
        assert_eq!(dedup_entry_name("page.png".into(), &mut seen), "page.png");
        assert_eq!(
            dedup_entry_name("page.png".into(), &mut seen),
            "page (2).png"
        );
        assert_eq!(
            dedup_entry_name("page.png".into(), &mut seen),
            "page (3).png"
        );
        // 原本就叫 "page (2).png" 的第三条不能与上面生成的撞名
        assert_eq!(
            dedup_entry_name("page (2).png".into(), &mut seen),
            "page (2) (2).png"
        );
        // 没有扩展名时直接拼在末尾
        let mut seen2 = HashSet::new();
        assert_eq!(dedup_entry_name("README".into(), &mut seen2), "README");
        assert_eq!(dedup_entry_name("README".into(), &mut seen2), "README (2)");
    }
}
