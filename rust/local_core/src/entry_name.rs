//! 归档条目名：规范化与同名去重。
//!
//! `dedup_entry_name` 直接复用 mImageViewer 源码（MIT）；规范化是本地更严格的
//! 适配，拒绝空路径段与 `.` / `..`。两者决定了两件事：
//!
//! 1. **页序的输入**——规范化之后才排序，所以 `a\b.jpg` 与 `a/b.jpg` 是同一条；
//! 2. **页的可寻址性**——归档里两条不同原始名可能规范化成同一个名字
//!    （`a\b.jpg` 与 `a/b.jpg`），如果 UI 用名字当句柄，其中一条就永远读不到。

#[cfg(test)]
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

// 唯一化函数体直接来自上游；pub(crate) 仅在构建边界提升为 pub。
include!(concat!(env!("OUT_DIR"), "/entry_dedup.rs"));

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
