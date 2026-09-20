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
///
/// `avif` 跟着 `avif` feature 走（默认开启）。它从外壳档搬到这里，
/// 是因为 Windows 引擎实测解不了 —— 交给外壳等于交给「解不动」，
/// 而 dav1d 已经证明能解（见 `SHELL_DECODABLE_EXTENSIONS` 的实测表）。
///
/// `jxl` 不在表里：它跟着 `jxl_backend` 的三个后端 feature 走，
/// 归属判断在 [`decode_support`] 里（见 [`JXL_CORE`]）。
#[cfg(feature = "avif")]
pub const CORE_DECODABLE_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "bmp", "gif", "tif", "tiff", "avif",
];

/// `avif` feature 关闭时的核心档（见 `Cargo.toml` 的 `[features]`）。
#[cfg(not(feature = "avif"))]
pub const CORE_DECODABLE_EXTENSIONS: &[&str] =
    &["jpg", "jpeg", "png", "webp", "bmp", "gif", "tif", "tiff"];

/// `jxl` 是否已进核心档：任一 JXL 后端 feature（`jxl-rs-mt` / `jxl-rs-1t` /
/// `jxl-oxide`）开启即为真。App 默认开 `jxl-rs-mt`，所以默认构建里
/// `jxl` 由核心自己解（§12.8 实测比 dav1d 快 1.6–2.3×），不再依赖外壳。
pub const JXL_CORE: bool = cfg!(any(
    feature = "jxl-rs-mt",
    feature = "jxl-rs-1t",
    feature = "jxl-oxide"
));

/// **本 crate 解不了、但外壳（Flutter / Skia）可能能解**的扩展名。
///
/// `jxl` 一直留在这一档表里作为**兜底**：它实际的归属由 [`decode_support`] 里的
/// [`JXL_CORE`] 先行判断 —— 任一 JXL 后端 feature 开着就是核心档，只有全关
/// （`--no-default-features` 这类构建）才真正落到这张表。
///
/// 这一档是实测逼出来的，不是预留。用户的真实归档
/// `G44 不会受伤 - NO.119 碧蓝档案 和纱 [30P-421MB].zip` 里 30 张**全是 `.avif`**。
///
/// 早先把这两类合成一张表，后果是**用户看到「打开 zip 没反应」**：
/// 枚举阶段就把全部条目滤掉，UI 收到 0 页，既没有页也没有拒绝原因。
/// 「算不算一页」是**格式识别**问题，「这一页谁来解」是**解码能力**问题，
/// 把后者当前者的门槛，症状就落在用户身上。所以枚举必须包含这一档。
///
/// # 但「交给外壳」不等于「外壳解得动」
///
/// 这里踩过一次，记清楚免得再犯：当初的判据是
/// 「`ui.instantiateImageCodec` 能把样本解成 5464×8192」，据此认定
/// **显示路径可用**。那个结论是错的 —— 它跑在 `flutter_tester` 上，
/// 而 App 跑的是 `flutter_windows.dll`，**两者的解码器不是同一个**。
///
/// 在真机引擎上复测（`integration_test/avif_decode_probe_test.dart`）：
///
/// | 样本 | 裸解码 | `ResizeImage` | 只读描述子 |
/// |---|---|---|---|
/// | avif（4:2:0 与 4:4:4、同尺寸对照） | 失败 | 失败 | **成功、尺寸正确** |
/// | 同尺寸 jpeg 5208×7808 | 成功 | 成功 | 成功 |
///
/// 症状是最刺眼的那种「半能」：**读得出尺寸，解不出像素**
/// （`Exception: Could not decompress image.`）。
/// 引擎的 PDB 里只有 `jpeg` / `png` / `wuffs` / `libwebp` 符号，
/// **`dav1d` / `libavif` / `aom` / `avif` 一个都没有** —— 它没链进 AV1 解码器。
/// 关掉 Impeller 重测无变化。
///
/// 所以留在这一档的格式，准确含义是：
/// **本 crate 不解，交由外壳；外壳解得动与否取决于平台。**
/// 列出来的价值在于用户能看见「书里有 N 页」，而不是「能显示」。
///
/// 曾经 `avif` 也在这里。后来量出 dav1d 这条路可行（同尺寸实测
/// 176–304 ms / 张，与 JPEG 同量级），才把它搬到核心档 —— 结论是
/// **不要把一个能自己解决的问题挂到平台能力上**。
#[cfg(feature = "avif")]
pub const SHELL_DECODABLE_EXTENSIONS: &[&str] = &["jxl", "heic", "heif"];

/// `avif` feature 关闭时，它退回这一档（只列页、不解码）。
#[cfg(not(feature = "avif"))]
pub const SHELL_DECODABLE_EXTENSIONS: &[&str] = &["avif", "jxl", "heic", "heif"];

/// 一页的解码归属。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeSupport {
    /// `decode_rgba` 能解，可进 Phase 1 的 Rust → GPU 上屏路径。
    Core,
    /// `decode_rgba` 明确拒绝；交给外壳，**外壳解得动与否取决于平台**
    /// （Windows 引擎实测解不动 avif，见上）。
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

/// 核心**不解**、交给外壳播放的视频扩展名（小写、不含前导点）。
///
/// 并集口径见 `lib/video/model/video_media_kind.dart` 的注释：以 neoview 的
/// `media.ts` 为主，补 mImageViewer `folder_tree.rs` 的 `SUPPORTED_VIDEO_EXTENSIONS`。
/// 两边必须一致 —— 页序与「这一页是谁」的判定分属两语言，各自一张表迟早漂移。
pub const VIDEO_EXTENSIONS: &[&str] = &[
    "3g2", "3gp", "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "nov", "ogg", "ogv",
    "webm", "wmv",
];

/// 是否为视频条目。
pub fn is_video_name(name: &str) -> bool {
    match extension_lower(name) {
        // `.nov` 是被改名的 mp4：按真实内容算，与 Dart 侧同一张伪装后缀表。
        Some(ext) if ext == "nov" => true,
        Some(ext) => VIDEO_EXTENSIONS.contains(&ext.as_str()),
        None => false,
    }
}

/// 是否**算一页**：图片、或外壳能播的视频。
///
/// 这条判断必须是「格式识别」而不是「解码能力」—— ADR-0008 里那条踩坑记录
/// （枚举阶段把条目滤光 → UI 收到 0 页 → 用户看到「打开 zip 没反应」）
/// 对视频同样成立：视频不该在页序阶段就消失。
pub fn is_page_name(name: &str) -> bool {
    is_image_name(name) || is_video_name(name)
}

/// 这一页由谁解码。不认识的格式返回 `None`（不算页）。
pub fn decode_support(name: &str) -> Option<DecodeSupport> {
    let ext = extension_lower(name)?;
    // jxl 先于两档常量表判断：开着后端 feature 时它在核心档，
    // 全关时落进下面的 SHELL_DECODABLE_EXTENSIONS（"jxl" 一直留在那张表里）。
    if JXL_CORE && ext == "jxl" {
        return Some(DecodeSupport::Core);
    }
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
    natural_key(a).cmp(&natural_key(b)).then_with(|| a.cmp(b))
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

    /// 「一页可以是视频」这个判定就落在这两个函数上（验收 A1/E4 的根），
    /// 所以逐条钉住。特别注意**视频不许算图片页**：错判成 true 会让视频页被
    /// 送去解像素，症状是翻到那一页直接报解码失败。
    #[test]
    fn video_names_are_pages_but_not_image_pages() {
        for name in [
            "1.mp4", "1.MKV", "a/b.webm", "clip.mov", "x.m4v", "y.ogv", "z.flv", "w.3gp",
        ] {
            assert!(is_video_name(name), "{name} 该算视频条目");
            assert!(is_page_name(name), "{name} 该算一页");
            assert!(
                !is_image_name(name),
                "{name} 不该算图片页 —— 那会让它进像素解码那条路"
            );
        }
        // `.nov` 是被改名的 mp4：与 Dart 侧同一张伪装后缀表，在页序阶段就算页。
        assert!(is_video_name("cover.nov"));
        assert!(is_page_name("cover.nov"));
        // 不认识的既不是页也不是视频：列出来只会在翻到它时失败。
        for name in ["1.cr2", "1.txt", "no_dot", "1.zip", "1.rar"] {
            assert!(!is_video_name(name), "{name}");
            assert!(!is_page_name(name), "{name}");
        }
    }

    /// 两语言两张表的**漂移守卫**：页序在 Rust 判、「这一页是谁」在 Dart 判，
    /// 各自一张表迟早错开 —— 症状是某一页 Rust 算它存在、Dart 说它不是视频，
    /// 于是既不播也不出图。表头注释已经写了「两边必须一致」，这条把它变成断言。
    #[test]
    fn video_extension_table_matches_the_dart_side() {
        let dart = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../lib/video/model/video_media_kind.dart");
        let text = std::fs::read_to_string(&dart)
            .unwrap_or_else(|e| panic!("读不到 {}：{e}", dart.display()));
        let start = text
            .find("const Set<String> videoExtensions")
            .expect("Dart 侧的 videoExtensions 声明被改名了");
        let end = text[start..]
            .find('}')
            .map(|i| start + i)
            .expect("videoExtensions 没有收尾的大括号");
        let body = &text[start..end];
        let dart_exts: std::collections::BTreeSet<String> = body
            .split('\'')
            .filter(|s| {
                !s.is_empty()
                    && s.chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
            })
            .map(str::to_string)
            .collect();
        let rust_exts: std::collections::BTreeSet<String> =
            VIDEO_EXTENSIONS.iter().map(|s| s.to_string()).collect();
        assert_eq!(
            rust_exts, dart_exts,
            "Rust 的 VIDEO_EXTENSIONS 与 Dart 的 videoExtensions 不一致"
        );
        assert!(rust_exts.len() >= 15, "表短得不像话：{rust_exts:?}");
    }

    #[test]
    fn only_decodable_extensions_count_as_pages() {
        for name in [
            "1.jpg", "1.JPEG", "1.png", "1.webp", "1.bmp", "1.gif", "1.tiff",
        ] {
            assert!(is_image_name(name), "{name}");
        }
        // 谁都不认识的格式不是页：列出来只会让用户在翻到它时才失败
        for name in ["1.cr2", "1.mp4", "1.txt", "no_dot"] {
            assert!(!is_image_name(name), "{name}");
        }
    }

    /// 这一条是**回归线**，不是补充测试：把 `avif` 挡在页枚举之外，
    /// 曾让用户看到「打开 zip 没反应」（30 张全是 avif → 0 页，且无拒绝原因）。
    /// 无论 `avif` feature 开关，这些格式都必须**算页**。
    #[test]
    fn shell_only_formats_are_pages_but_not_core_decodable() {
        for name in ["1.avif", "1.AVIF", "1.jxl", "ch/2.heic", "3.HEIF"] {
            assert!(is_image_name(name), "{name} 应当算作一页");
        }
        // jxl 的归属**随后端 feature 变**（与 avif 同模式）。
        #[cfg(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide"))]
        {
            assert_eq!(decode_support("1.jxl"), Some(DecodeSupport::Core));
            assert!(!needs_shell_decoder("1.jxl"));
        }
        #[cfg(not(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide")))]
        {
            assert!(needs_shell_decoder("1.jxl"), "1.jxl 应当由外壳解码");
            assert_eq!(decode_support("1.jxl"), Some(DecodeSupport::ShellOnly));
        }
        for name in ["ch/2.heic", "3.HEIF"] {
            assert!(needs_shell_decoder(name), "{name} 应当由外壳解码");
            assert_eq!(decode_support(name), Some(DecodeSupport::ShellOnly));
        }
        // avif 的归属**随 feature 变**：开着由 dav1d 自己解，关着才交外壳。
        #[cfg(feature = "avif")]
        {
            assert_eq!(decode_support("1.avif"), Some(DecodeSupport::Core));
            assert!(!needs_shell_decoder("1.avif"));
        }
        #[cfg(not(feature = "avif"))]
        {
            assert_eq!(decode_support("1.avif"), Some(DecodeSupport::ShellOnly));
            assert!(needs_shell_decoder("1.avif"));
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
