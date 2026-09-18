//! mImageViewer `ui_helpers` 中文件名自然排序所需的最小源码适配。
//!
//! 仅保留 `filename_sort.rs` 直接调用的纯排序函数，UI 绘制部分不进入 local_core。

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum NaturalChunk {
    Text(String),
    Num(u64),
}

fn natural_digit_value(ch: char) -> Option<u32> {
    if ch.is_ascii_digit() {
        return Some(ch as u32 - '0' as u32);
    }
    if ('\u{ff10}'..='\u{ff19}').contains(&ch) {
        return Some(ch as u32 - '\u{ff10}' as u32);
    }
    None
}

/// 与 mImageViewer `src/ui_helpers.rs::natural_sort_key` 保持同名和排序语义。
pub fn natural_sort_key(name: &str) -> Vec<NaturalChunk> {
    let mut chunks = Vec::new();
    let mut chars = name.chars().peekable();
    while let Some(ch) = chars.peek().copied() {
        if natural_digit_value(ch).is_some() {
            let mut value = 0u64;
            while let Some(next) = chars.peek().copied() {
                let Some(digit) = natural_digit_value(next) else {
                    break;
                };
                value = value.saturating_mul(10).saturating_add(u64::from(digit));
                chars.next();
            }
            chunks.push(NaturalChunk::Num(value));
        } else {
            let mut text = String::new();
            while let Some(next) = chars.peek().copied() {
                if natural_digit_value(next).is_some() {
                    break;
                }
                chars.next();
                if next.is_alphanumeric() {
                    text.extend(next.to_lowercase());
                }
            }
            if !text.is_empty() {
                chunks.push(NaturalChunk::Text(text));
            }
        }
    }
    chunks
}
