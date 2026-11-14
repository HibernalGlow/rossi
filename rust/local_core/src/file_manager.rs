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
mod columns;
mod hierarchy;
mod listing;
mod search;
mod state;
mod tab_defaults;
mod types;
mod util;
pub use hierarchy::*;
pub use search::*;
pub use state::*;
pub use types::*;
// listing / util 里全是 pub(super) 的内部助手（见两个文件顶部）：它们只在
// file_manager 及其子模块内可见，对外没有一件可重导出。这里仍要把名字引进
// 本模块作用域，好让各子模块靠 `use super::*` 互相看见；但用 `pub use` 会
// 触发「glob 没有重导出任何 pub 项」的警告，所以降成私有 `use`。
use listing::*;
use util::*;

#[cfg(test)]
mod tests;
