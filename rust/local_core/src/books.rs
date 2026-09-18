//! mImageViewer `books::path_is_under_any` 的纯路径适配。

use std::path::Path;

pub fn path_is_under_any(path: &Path, roots: &[std::path::PathBuf]) -> bool {
    roots.iter().any(|root| path.starts_with(root))
}
