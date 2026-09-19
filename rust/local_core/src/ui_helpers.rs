//! mImageViewer `ui_helpers` 中文件名自然排序所需的最小源码适配。
//!
//! 仅保留 `filename_sort.rs` 直接调用的纯排序函数，UI 绘制部分不进入 local_core。

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum NaturalChunk {
    Num(u64),
    Text(String),
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

/// `std::fs::Metadata` から mtime を UNIX epoch 秒として返す。取得失敗時は 0。
pub fn mtime_secs(meta: &std::fs::Metadata) -> i64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs() as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_numbers_precede_letters() {
        let num_key = natural_sort_key("1BACKUP");
        let text_key = natural_sort_key("BaiduNetdiskDownload");
        assert!(
            num_key < text_key,
            "Numbers must precede letters in natural sort: {num_key:?} should be less than {text_key:?}"
        );
    }
}
