//! 页序：哪些名字算一页、以及按什么顺序排。
//!
//! 规则取自 mImageViewer 的 `archive_converter::is_image_entry` /
//! `should_ignore_entry` 与 `filename_sort`，但去掉了它对 Windows
//! `LCMapStringEx` 的依赖——那套排序键只在 Windows 上存在，而 Rossi 要三平台同序。
//! 这里改成纯 Rust 的自然序：**数字段按数值比较**，于是 `page2 < page10`。

use std::cmp::Ordering;

/// **本 crate 真能解码**的扩展名（小写、不含前导点）。
///
/// 与 `Cargo.toml` 里 `image` 的 feature 集严格对齐：这里列了却解不了，
/// 就是让用户在读到那一页时才失败。
pub const CORE_DECODABLE_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "bmp", "gif", "tif", "tiff",
];

/// **本 crate 解不了、但外壳（Flutter / Skia）能解**的扩展名。
///
/// 这一档是实测逼出来的，不是预留。用户的真实归档
/// `G44 不会受伤 - NO.119 碧蓝档案 和纱 [30P-421MB].zip` 里 30 张**全是 `.avif`**，
/// 而 Flutter 的 `ui.instantiateImageCodec` 能把它们正常解成 5464×8192
/// （`test/avif_decode_probe_test.dart` 有可复跑的探针）。
///
/// 早先把这两类合成一张表，后果是**用户看到「打开 zip 没反应」**：
/// 枚举阶段就把全部条目滤掉，UI 收到 0 页，既没有页也没有拒绝原因。
/// 「算不算一页」是**格式识别**问题，「这一页谁来解」是**解码能力**问题，
/// 把后者当前者的门槛，症状就落在用户身上。
///
/// 代价必须写在这里免得以后误读：这些页**只能走 Dart 兜底显示路径**
/// （`docs/v0.1-local-core.md` §9），Phase 1 那条「Rust 解码 → GPU texture 上屏」
/// 对它们**暂时不成立** —— `image` 要解 avif 得带 libavif/dav1d 这类原生依赖，
/// 属 core 之外的东西，是否纳入由 Gate 决定。
pub const SHELL_DECODABLE_EXTENSIONS: &[&str] = &["avif", "jxl", "heic", "heif"];

/// 一页的解码归属。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeSupport {
    /// `decode_rgba` 能解，可进 Phase 1 的 Rust → GPU 上屏路径。
    Core,
    /// 只有外壳（Flutter / Skia）能解；`decode_rgba` 会明确拒绝。
    ShellOnly,
}

impl DecodeSupport {
    pub fn label(self) -> &'static str {
        match self {
            Self::Core => "core",
            Self::ShellOnly => "shell-only",
        }
    }
}

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
///
/// 两档都算页：只要**某一侧能解**，它就该出现在页序里。
/// 「谁负责解」由 [`decode_support`] 单独回答。
pub fn is_image_name(name: &str) -> bool {
    decode_support(name).is_some()
}

/// 这一页由谁解码。不认识的格式返回 `None`（不算页）。
pub fn decode_support(name: &str) -> Option<DecodeSupport> {
    let ext = extension_lower(name)?;
    if CORE_DECODABLE_EXTENSIONS.contains(&ext.as_str()) {
        Some(DecodeSupport::Core)
    } else if SHELL_DECODABLE_EXTENSIONS.contains(&ext.as_str()) {
        Some(DecodeSupport::ShellOnly)
    } else {
        None
    }
}

/// 是否必须交给外壳解码（等价于 `decode_support(..) == Some(ShellOnly)`）。
///
/// 单独给一个谓词，是因为调用点（`LocalSource::page_pixels`、探针、以后的上屏层）
/// 想要的都是这个判断，而不是枚举值本身。
pub fn needs_shell_decoder(name: &str) -> bool {
    decode_support(name) == Some(DecodeSupport::ShellOnly)
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
        // 谁都不认识的格式不是页：列出来只会让用户在翻到它时才失败
        for name in ["1.cr2", "1.mp4", "1.txt", "no_dot"] {
            assert!(!is_image_name(name), "{name}");
        }
    }

    /// 这一条是**回归线**，不是补充测试：把 `avif` 挡在页枚举之外，
    /// 曾让用户看到「打开 zip 没反应」（30 张全是 avif → 0 页，且无拒绝原因）。
    #[test]
    fn shell_only_formats_are_pages_but_not_core_decodable() {
        for name in ["1.avif", "1.AVIF", "ch/2.jxl", "3.heic", "4.HEIF"] {
            assert!(is_image_name(name), "{name} 应当算作一页");
            assert!(needs_shell_decoder(name), "{name} 应当由外壳解码");
            assert_eq!(decode_support(name), Some(DecodeSupport::ShellOnly));
        }
        // 反过来：核心能解的页绝不能被标成 shell-only
        for name in ["1.jpg", "1.png", "1.webp"] {
            assert_eq!(decode_support(name), Some(DecodeSupport::Core), "{name}");
            assert!(!needs_shell_decoder(name), "{name}");
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
