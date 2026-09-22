//! Vendored directly from `vendor/mimageviewer/src/search_norm.rs` (MIT).
//!
//! 搜索文本的归一化函数。
//!
//! **设计上的重要约束**:
//!   建索引时 (ingest 生成 `all_text_norm`)、
//!   解析查询时 (search_query)、
//!   post-filter 时 (matches 的 text 侧) **这 3 处必须用同一个函数**。
//!   一旦不一致就会出现假阴性。Rossi 目前只有 post-filter 与解析 2 处
//!   （`zip_entry_key` 因索引侧尚未引入，作为面向未来的保留）。
//!
//! v1 仅做 `to_lowercase()`。NFKC（全角/半角归一化）留待 v2 考虑。
//! 引入 NFKC 时必须 bump `index_version` 并重建索引。

/// 索引与查询两侧共用的、用于搜索匹配的文本归一化。
/// v1: 仅小写化（与现行 `search_query.rs` 的 `to_lowercase()` 保持一致）。
pub fn normalize_for_match(s: &str) -> String {
    s.to_lowercase()
}

/// ZIP 内条目在 fts_meta 上的键表示 `<zip_path>\x1F<entry>`。
/// 接受已按 path_key 归一化的 `zip_path` 与原始条目路径（已统一为 slash、已小写化）。
///
/// 分隔符是 ASCII Unit Separator (U+001F)。Windows / POSIX 下都不允许把它当作
/// 普通文件名字符（Windows 禁止全部控制字符 0x00–0x1F，POSIX 下用户也基本不会用），
/// 因此可以从结构上排除 `<zip>SEP<entry>` 与普通路径 `c:/a/book.zip!cover.jpg`
/// 相冲突的歧义（对应 Codex P2）。旧实现用 `!` 作分隔，与文件名中含 `!` 的
/// Eagle 生成文件等存在歧义。通过 bump INDEX_VERSION，
/// 旧数据会自动重建。
pub const ZIP_ENTRY_SEP: char = '\u{1F}';

pub fn zip_entry_key(normalized_zip_path: &str, entry_name: &str) -> String {
    let entry_norm = entry_name.to_lowercase().replace('\\', "/");
    format!("{normalized_zip_path}{ZIP_ENTRY_SEP}{entry_norm}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_lowers_ascii() {
        assert_eq!(normalize_for_match("ABCdef"), "abcdef");
    }

    #[test]
    fn normalize_preserves_cjk() {
        // CJK 汉字、平假名、片假名经 to_lowercase 不会发生变化
        assert_eq!(normalize_for_match("夕焼け"), "夕焼け");
        assert_eq!(normalize_for_match("カメラ"), "カメラ");
    }

    #[test]
    fn normalize_fullwidth_ascii_lowercases() {
        // to_lowercase 也会把全角英文字母小写化（Unicode case folding 的行为）。
        // 实际上 fullwidth ⇄ halfwidth 混合时 "不会变成同一个 lowercase variant"，因此
        // 含全角的搜索在 v2 引入 NFKC 之前以完全匹配优先。
        assert_eq!(normalize_for_match("ＡＢＣ"), "ａｂｃ");
        // 半角小写与全角小写是不同的字符
        assert_ne!(normalize_for_match("abc"), normalize_for_match("ＡＢＣ"));
    }

    #[test]
    fn normalize_is_idempotent() {
        let s = "Mixed カメラ 123";
        let once = normalize_for_match(s);
        let twice = normalize_for_match(&once);
        assert_eq!(once, twice);
    }

    #[test]
    fn zip_entry_key_combines() {
        assert_eq!(
            zip_entry_key("c:/photos/archive.zip", "folder/img.jpg"),
            format!("c:/photos/archive.zip{ZIP_ENTRY_SEP}folder/img.jpg")
        );
    }

    #[test]
    fn zip_entry_key_lowers_entry() {
        assert_eq!(
            zip_entry_key("c:/a.zip", "SubDir\\Img.JPG"),
            format!("c:/a.zip{ZIP_ENTRY_SEP}subdir/img.jpg")
        );
    }

    /// 新 separator (U+001F) 不可能出现在 Windows / POSIX 的普通文件名中，
    /// 因此不会与普通路径 `c:/a/book.zip!cover.jpg`（文件名含 `!`）冲突。
    #[test]
    fn zip_entry_key_is_not_ambiguous_with_bang_filename() {
        let zip_key = zip_entry_key("c:/a/book.zip", "cover.jpg");
        let bang_filename = "c:/a/book.zip!cover.jpg";
        assert_ne!(zip_key, bang_filename);
        assert!(zip_key.contains(ZIP_ENTRY_SEP));
        assert!(!bang_filename.contains(ZIP_ENTRY_SEP));
    }
}
