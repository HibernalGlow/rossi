//! 直接编译 mImageViewer 路径身份模块（MIT），只保留跨平台盘符根判定适配。
//! 上游其余函数及测试随子模块更新；Rossi Catalog 仍识别 Windows 路径根。
include!(concat!(env!("OUT_DIR"), "/path_key.rs"));

pub fn is_drive_or_share_root(path: &Path) -> bool {
    if path.parent().is_none() {
        return true;
    }
    let s = path.to_string_lossy();
    if s.len() >= 2 && s.chars().nth(1) == Some(':') {
        let remainder = &s[2..];
        remainder.is_empty() || remainder == "\\" || remainder == "/"
    } else {
        false
    }
}
