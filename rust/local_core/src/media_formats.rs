//! 用户可自定义的「哪些后缀算图片 / 算视频」。
//!
//! 语义照 neoview `domain/page/media.ts:64-65`：**用户列出来就是替换默认表**，
//! 空表表示「没设置过」，继续用内置默认。上游那条行为有测试钉着
//! （`media.test.ts:21-31`：自定义之后 `resolve("clip.mp4")` 反而变 `undefined`），
//! 所以这里同样不做「追加」—— 追加是另一条旋钮（`extra_video`，见 [`set`]）。
//!
//! # 为什么这张表必须在 Rust
//!
//! 「这个文件算不算媒体」的判定住在浏览层：`folder_tree::is_recognized_image_ext`
//! 与 `file_tree.rs` 的 `is_video` 决定一个条目**是否出现在列表里**。Dart 侧那套
//! `RossiMediaKind` / `disguisedExtensions` 只管「已经列出来的这一页是谁」，
//! 所以只改 Dart 的话，用户加了后缀仍然在文件管理器里**看不见**（`.wbp` 被隐藏
//! 就是这个根因）。判定要生效，表就得推到 Rust 来。
//!
//! # 为什么判定挂在 [`Tables`] 这个值上，而不是一律走全局
//!
//! 生产路径确实只有一份全局表（[`is_image_ext`] 等），但**判定本身是纯函数**。
//! 表是进程级 `static`，而 `cargo test` 默认多线程 —— 让测试去写那份全局，症状是
//! 与本模块毫无关系的 25 条测试一起红（`page_order` 与 `rar_source` 那些
//! 「这一页算不算页」的断言被中途换掉的表洗掉）。所以测试一律构造 [`Tables`] 值
//! 来断言，全局那一份只在启动与设置变更时被写。
//!
//! # 为什么只有替换档与追加档，没有第三档 MIME
//!
//! neoview 还有 `mediaMimeTypes`（后缀→MIME 覆盖，`image/gif` 意味着动图）。
//! 本仓不用 MIME 承载这件事（动图由容器嗅探回答，见 [`crate::animation`]），
//! 搬那一档只会多一条优先链却没有消费者。

use std::sync::{LazyLock, RwLock};

/// 一张表最多多少条（neoview `media.ts:154-166` 的上限）。
const MAX_ENTRIES: usize = 128;

/// 单个后缀最长多少个字符（上游同一条校验）。
const MAX_SUFFIX_LEN: usize = 16;

/// 一份「什么后缀算图片 / 算视频」的答案。
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tables {
    image: Vec<String>,
    video: Vec<String>,
    /// 永远追加在视频档之上：这是改造前就存在的那条「自定义视频后缀」设置，
    /// 它的语义是**追加**，不该被替换档吞掉。
    extra_video: Vec<String>,
}

impl Tables {
    /// 用户是否**确实**设置过图片档。
    ///
    /// 需要单独问一句，是因为「表非空」在两处含义不同：[`Tables::is_image_ext`] 关心的
    /// 是命中与否，而「要不要把默认表里根本没有的后缀也算成一页」只能在用户真的
    /// 设置过之后才成立 —— 否则 `folder_tree` 那张比页序表宽得多的默认表
    /// （含 dng / cr2 等相机 RAW）会平白多出一批页。
    pub fn overriding_image(&self) -> bool {
        !self.image.is_empty()
    }

    /// 这个后缀算不算图片（只看表，不含 Susie 插件那一档）。
    pub fn is_image_ext(&self, ext: &str) -> bool {
        pick(&self.image, ext, crate::folder_tree::SUPPORTED_EXTENSIONS)
    }

    /// 这个后缀算不算视频（替换档 ∪ 追加档）。
    pub fn is_video_ext(&self, ext: &str) -> bool {
        pick(&self.video, ext, crate::page_order::VIDEO_EXTENSIONS)
            || self.extra_video.iter().any(|entry| entry == ext)
    }

    /// 规整并收下用户给的三张表。
    pub fn normalized(image: &[String], video: &[String], extra_video: &[String]) -> Self {
        Self {
            image: normalize_all(image),
            video: normalize_all(video),
            extra_video: normalize_all(extra_video),
        }
    }
}

fn pick(user: &[String], ext: &str, defaults: &[&str]) -> bool {
    if user.is_empty() {
        return defaults.contains(&ext);
    }
    user.iter().any(|entry| entry == ext)
}

/// 规整一个后缀：去空白、去前导点、小写。
///
/// 与上游一样按 `^[a-z0-9][a-z0-9+_-]{0,15}$` 筛：不合规的**丢掉**而不是报错。
/// 理由是这张表在 Rust 侧是第二道关口 —— 设置界面已经用
/// `MediaKindOverrides.invalidEntries` 拦过一遍，走到这里的多半是旧存档或
/// 手工改过的值，为一颗坏后缀把整张表判死是更糟的结果。
fn normalize(raw: &str) -> Option<String> {
    let text = raw.trim().trim_start_matches('.').to_ascii_lowercase();
    if text.is_empty() || text.len() > MAX_SUFFIX_LEN {
        return None;
    }
    let mut chars = text.chars();
    let Some(first) = chars.next() else {
        return None;
    };
    if !(first.is_ascii_lowercase() || first.is_ascii_digit()) {
        return None;
    }
    if !chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '+' | '_' | '-'))
    {
        return None;
    }
    Some(text)
}

fn normalize_all(values: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(values.len().min(MAX_ENTRIES));
    for value in values {
        let Some(ext) = normalize(value) else {
            continue;
        };
        if out.contains(&ext) {
            continue;
        }
        if out.len() >= MAX_ENTRIES {
            break;
        }
        out.push(ext);
    }
    out
}

static TABLES: LazyLock<RwLock<Tables>> = LazyLock::new(RwLock::default);

/// 当前生效的表。读不到（锁坏了）就当用户没设置过。
pub fn current() -> Tables {
    TABLES.read().map(|slot| slot.clone()).unwrap_or_default()
}

/// 装上用户设置的三张表（空数组 = 该档不覆盖默认）。
pub fn set(image: &[String], video: &[String], extra_video: &[String]) {
    let next = Tables::normalized(image, video, extra_video);
    if let Ok(mut slot) = TABLES.write() {
        *slot = next;
    }
}

/// 见 [`Tables::overriding_image`]。
pub fn overriding_image() -> bool {
    current().overriding_image()
}

/// 见 [`Tables::is_image_ext`]。
pub fn is_image_ext(ext: &str) -> bool {
    current().is_image_ext(ext)
}

/// 见 [`Tables::is_video_ext`]。
pub fn is_video_ext(ext: &str) -> bool {
    current().is_video_ext(ext)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 一律构造值来断言：**不要**在这里调 [`set`]，见模块注释。
    fn table(image: &[&str], video: &[&str], extra: &[&str]) -> Tables {
        let to_vec =
            |values: &[&str]| -> Vec<String> { values.iter().map(|v| (*v).to_string()).collect() };
        Tables::normalized(&to_vec(image), &to_vec(video), &to_vec(extra))
    }

    #[test]
    fn empty_tables_keep_the_defaults() {
        let tables = table(&[], &[], &[]);
        assert!(tables.is_image_ext("png"));
        assert!(tables.is_video_ext("mp4"));
        // 没设置过时，不认识的仍然不算。
        assert!(!tables.is_image_ext("myimg"));
        assert!(
            !tables.overriding_image(),
            "相机 RAW 那一档比页序表宽得多，没覆盖时绝不能拿它当页序的依据"
        );
    }

    #[test]
    fn user_image_table_replaces_the_default() {
        let tables = table(&["webp", "myimg"], &[], &[]);
        assert!(tables.is_image_ext("myimg"), "用户加进来的档要算图片");
        assert!(
            !tables.is_image_ext("png"),
            "替换语义：用户列出来就是全部，png 不在表里就不算（neoview media.ts:64-65 同一条）"
        );
        assert!(tables.overriding_image());
        // 视频档没设置，仍然是默认表。
        assert!(tables.is_video_ext("mp4"));
    }

    #[test]
    fn extra_video_entries_survive_a_replacement_list() {
        let tables = table(&[], &["webm"], &["myvid"]);
        assert!(tables.is_video_ext("webm"));
        assert!(tables.is_video_ext("myvid"), "追加档不该被替换档吞掉");
        assert!(!tables.is_video_ext("mp4"), "替换之后默认视频档不再参与");
    }

    #[test]
    fn suffixes_are_normalized_and_bad_ones_are_dropped() {
        let too_long = "x".repeat(MAX_SUFFIX_LEN + 1);
        let tables = table(
            &[" .JPG ", "jpg", "web*p", "", "-lead", &too_long],
            &[],
            &[],
        );
        assert!(
            tables.is_image_ext("jpg"),
            "去点 / 小写 / 去重之后仍然算，且只保留一条"
        );
        assert!(!tables.is_image_ext("web*p"), "含非法字符的直接丢掉");
        assert!(!tables.is_image_ext("lead"), "首位必须是字母或数字");
        assert!(!tables.is_image_ext(&too_long), "超过 16 字符丢掉");
    }

    #[test]
    fn table_is_capped_at_the_entry_limit() {
        let many: Vec<String> = (0..400).map(|i| format!("img{i}")).collect();
        let tables = Tables::normalized(&many, &[], &[]);
        assert!(tables.is_image_ext("img0"));
        assert!(tables.is_image_ext("img127"));
        assert!(!tables.is_image_ext("img128"), "上限 {MAX_ENTRIES} 条");
    }
}
