//! mImageViewer `ui_helpers` 中文件名自然排序所需的最小源码适配。
//!
//! 仅保留 `filename_sort.rs` 直接调用的纯排序函数，UI 绘制部分不进入 local_core。

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum NaturalChunk {
    Num(u64),
    Text(String),
}

// Rossi 保留数字块先于文本块的已有顺序；上游 NaturalChunk 是 Text 在前。
// 函数体直接复用上游，与文件浏览既有排序约定的冲突仅留在这个枚举。
include!(concat!(env!("OUT_DIR"), "/natural_sort.rs"));

/// 从 `std::fs::Metadata` 以 UNIX epoch 秒的形式返回 mtime。获取失败时返回 0。
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
