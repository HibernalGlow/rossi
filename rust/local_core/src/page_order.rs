//! 页序：哪些名字算一页、以及按什么顺序排。
//!
//! 规则取自 mImageViewer 的 `archive_converter::is_image_entry` /
//! `should_ignore_entry` 与 `filename_sort`，但去掉了它对 Windows
//! `LCMapStringEx` 的依赖——那套排序键只在 Windows 上存在，而 Rossi 要三平台同序。
//! 这里改成纯 Rust 的自然序：**数字段按数值比较**，于是 `page2 < page10`。

use std::cmp::Ordering;

/// 认作页面并且**本 crate 真能解码**的扩展名（小写、不含前导点）。
///
/// 与 `Cargo.toml` 里 `image` 的 feature 集严格对齐：这里列了却解不了，
/// 就是让用户在读到那一页时才失败。mImageViewer 的表更长（heic / jxl / 相机 RAW），
/// 但那些走它的 WIC 路径，不属于 v0.1。
pub const IMAGE_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "bmp", "gif", "tif", "tiff",
];

/// 取小写扩展名（不含点）。
///
/// 「最后一个 `.` 必须在最后一个路径分隔符之后」这条判断是必要的：
/// 目录名里的点（`Vol.1/page`）不能被当成扩展名。
pub fn extension_lower(name: &str) -> Option<String> {
    let dot = name.rfind('.')?;
    let last_sep = name.rfind(['/', '\\']).map_or(0, |i| i + 1);
    if dot < last_sep {
        return None;
    }
    Some(name[dot + 1..].to_ascii_lowercase())
}

/// 是否为可读页面。
pub fn is_image_name(name: &str) -> bool {
    extension_lower(name)
        .is_some_and(|ext| IMAGE_EXTENSIONS.contains(&ext.as_str()))
}

/// 是否应当完全忽略（macOS 资源叉、隐藏文件/目录）。
///
/// 输入是**已统一成 `/` 的相对路径**，因此逐段判断即可同时覆盖
/// 「隐藏目录里的正常文件」与「`__MACOSX` 整棵树」。
pub fn should_ignore_name(rel: &str) -> bool {
    rel.split('/')
        .any(|seg| seg.is_empty() || seg.starts_with('.') || seg == "__MACOSX")
}

/// 自然序的排序块。
///
/// 变体顺序即比较顺序：数字段排在文字段之前（`1.png` 在 `a.png` 前）。
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Chunk {
    Num(u128),
    Text(String),
}

/// 把名字切成「数字段/文字段」序列。文字段统一小写，实现大小写不敏感。
fn natural_key(name: &str) -> Vec<Chunk> {
    let mut out = Vec::new();
    let mut text = String::new();
    let mut digits = String::new();

    // 闭包会同时借用两个累加器，用宏避免为它单独造一个结构体。
    macro_rules! flush_text {
        () => {
            if !text.is_empty() {
                out.push(Chunk::Text(std::mem::take(&mut text)));
            }
        };
    }
    macro_rules! flush_digits {
        () => {
            if !digits.is_empty() {
                // 超长数字串（> 38 位）用饱和值即可：排序只要单调，不需要精确。
                let value = digits.parse::<u128>().unwrap_or(u128::MAX);
                out.push(Chunk::Num(value));
                digits.clear();
            }
        };
    }

    for ch in name.chars() {
        if ch.is_ascii_digit() {
            flush_text!();
            digits.push(ch);
        } else {
            flush_digits!();
            for lower in ch.to_lowercase() {
                text.push(lower);
            }
        }
    }
    flush_text!();
    flush_digits!();
    out
}

/// 自然序比较。同键时用原始名字做确定性 tiebreak（`1.jpg` 与 `01.jpg` 数值相等）。
pub fn compare_natural(a: &str, b: &str) -> Ordering {
    natural_key(a)
        .cmp(&natural_key(b))
        .then_with(|| a.cmp(b))
}

/// 原地按自然序排序。
pub fn sort_natural<T, F>(items: &mut [T], mut name_of: F)
where
    F: FnMut(&T) -> &str,
{
    items.sort_by(|a, b| compare_natural(name_of(a), name_of(b)));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extension_is_taken_after_the_last_separator() {
        assert_eq!(extension_lower("a/b.PNG").as_deref(), Some("png"));
        assert_eq!(extension_lower(r"a\b\c.jpg").as_deref(), Some("jpg"));
        // 目录名里有点、但文件名没有扩展名 -> 不是图片
        assert_eq!(extension_lower("Vol.1/page"), None);
        assert_eq!(extension_lower("no_dot"), None);
    }

    #[test]
    fn only_decodable_extensions_count_as_pages() {
        for name in ["1.jpg", "1.JPEG", "1.png", "1.webp", "1.bmp", "1.gif", "1.tiff"] {
            assert!(is_image_name(name), "{name}");
        }
        // 这一步是 v0.1 的克制之处：能列出来就必须能解出来
        for name in ["1.heic", "1.jxl", "1.avif", "1.cr2", "1.mp4", "1.txt"] {
            assert!(!is_image_name(name), "{name}");
        }
    }

    #[test]
    fn ignore_rules_cover_apple_double_and_macosx_tree() {
        assert!(should_ignore_name("._page.jpg"));
        assert!(should_ignore_name("__MACOSX/page.jpg"));
        assert!(should_ignore_name("ch1/.hidden.jpg"));
        assert!(!should_ignore_name("ch1/page.jpg"));
        assert!(!should_ignore_name("page.jpg"));
    }

    #[test]
    fn natural_order_puts_page2_before_page10() {
        let mut names = vec!["page10.jpg", "page2.jpg", "Page1.jpg", "page20.jpg"];
        names.sort_by(|a, b| compare_natural(a, b));
        assert_eq!(
            names,
            vec!["Page1.jpg", "page2.jpg", "page10.jpg", "page20.jpg"]
        );
    }

    #[test]
    fn natural_order_is_deterministic_when_numbers_are_equal() {
        // 数值相同 -> 回落到原始字符串，保证排序是全序（不会因不稳定排序而抖动）
        assert_eq!(compare_natural("01.jpg", "1.jpg"), Ordering::Less);
        assert_eq!(compare_natural("a1b", "a1b"), Ordering::Equal);
        // 纯数字段排在纯文字段之前
        assert_eq!(compare_natural("1.png", "a.png"), Ordering::Less);
    }
}
