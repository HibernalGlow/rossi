//! 直接编译 mImageViewer 原文件；MIT 版权与测试保留在上游源码中。
//! 子模块更新自动进入编译，复核基线见 docs/mimageviewer-reuse-inventory.json。
#[rustfmt::skip]
#[path = "../../../vendor/mimageviewer/src/filename_sort.rs"]
mod upstream;
pub use upstream::*;
