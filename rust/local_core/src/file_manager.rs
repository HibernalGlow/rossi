//! 可迁移的文件管理器状态机。
//!
//! 这一层只依赖 `std::fs` 和本 crate 已有的目录枚举器，不依赖 Flutter、egui 或
//! 任何具体 UI。Rossi 的泳道卡片、桌面边栏以及后续的 Tauri / WASM 外壳都应该只
//! 负责把这里的快照画出来并转发动作。
//!
//! 目录枚举与自然排序沿用 `file_tree`（其过滤、排序规则对应 mImageViewer 的
//! `folder_tree` / `filename_sort`），状态机则把 NeoView 的多页签、穿透和子文件名
//! 投影收拢到一个可测试的 Rust API 中。

use std::collections::{HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Result, anyhow};

use crate::file_tree::{FileTreeNode, list_directory_with_hidden};

// 拆出的子模块：item 原样搬过去，这里声明并引回名字，
// 子模块之间通过 `use super::*` 互相可见。
mod types;
mod state;
mod search;
mod util;
mod listing;
pub use types::*;
pub use state::*;
pub use search::*;
pub use util::*;
pub use listing::*;

#[cfg(test)]
mod tests;