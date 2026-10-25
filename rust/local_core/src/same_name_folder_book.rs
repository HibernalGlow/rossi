//! 同名「文件夹 / 书（ZIP 等容器）」候选的三态投影策略与设置迁移。
//!
//! 直接复用 mImageViewer 源码（MIT，v4.8.1 的 `src/same_name_folder_book.rs`）。
//! 上游 866c01f68 把旧 `skip_zip_if_folder_exists` 布尔升级成三态：
//!
//! - `PreferBook`：有同名书时文件夹不进候选（新默认；上游公告的语义翻转：
//!   旧「开」映射到它）；
//! - `PreferFolder`：有同名文件夹时书不进候选（与旧 `skip_zip=true` 行为一致）；
//! - `ShowBoth`：都保留（旧「关」映射到它）。
//!
//! [`canonicalize`] 迁移设置 JSON 里的旧布尔键，[`keep_mask`] 由
//! `folder_tree::sorted_subdirs` 在既有资格检查之后做候选投影。
//! 上游自带的 `mod tests` 里有一个用例依赖上游全量 `Settings`
//! （本仓是缩减版），不随切片搬运，等价契约在下方本地测试。

// 上游文件的导入随 items 切片一起留在上游侧，这里补齐（见 entry_name.rs 先例）。
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::HashSet;
use std::path::Path;

include!(concat!(env!("OUT_DIR"), "/same_name_folder_book.rs"));

#[cfg(test)]
mod tests {
    use super::*;

    fn map(json: serde_json::Value) -> serde_json::Map<String, serde_json::Value> {
        json.as_object().unwrap().clone()
    }

    /// 上游 `released_bool_and_new_precedence` 的等价契约：
    /// 旧开 → prefer_book，旧关 → show_both，新键（含畸形值）永远压过旧布尔。
    #[test]
    fn legacy_bool_migrates_and_new_key_wins() {
        for (old, expected) in [(true, "prefer_book"), (false, "show_both")] {
            let mut m = map(serde_json::json!({ LEGACY_KEY: old }));
            canonicalize(&mut m).unwrap();
            assert_eq!(m[KEY], expected);
            assert!(!m.contains_key(LEGACY_KEY));
        }
        let mut m = map(serde_json::json!({ KEY: "prefer_folder", LEGACY_KEY: true }));
        canonicalize(&mut m).unwrap();
        assert_eq!(m[KEY], "prefer_folder");
        // 未来变体不回退成旧布尔，而是显式报错
        let mut m = map(serde_json::json!({ KEY: "future", LEGACY_KEY: false }));
        assert!(canonicalize(&mut m).is_err());
    }

    /// 三态投影：按 (路径, 是否文件夹) 候选行产出保留掩码，名字忽略大小写。
    #[test]
    fn keep_mask_projects_policy_over_same_name_rows() {
        use std::path::Path;
        let rows = [
            (Path::new("/root/book"), true),
            (Path::new("/root/book.zip"), false),
            (Path::new("/root/other"), true),
        ];
        let mask = |policy: SameNameFolderBookPolicy| {
            keep_mask(policy, rows.iter().copied())
                .into_iter()
                .map(|keep| if keep { "keep" } else { "drop" })
                .collect::<Vec<_>>()
        };
        assert_eq!(
            mask(SameNameFolderBookPolicy::PreferBook),
            ["drop", "keep", "keep"]
        );
        assert_eq!(
            mask(SameNameFolderBookPolicy::PreferFolder),
            ["keep", "drop", "keep"]
        );
        assert_eq!(
            mask(SameNameFolderBookPolicy::ShowBoth),
            ["keep", "keep", "keep"]
        );
    }
}
