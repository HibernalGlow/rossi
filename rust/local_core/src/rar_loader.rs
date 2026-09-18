//! mImageViewer `rar_loader` 判定函数在 local_core 的薄适配。

use std::path::Path;

pub fn is_rar_path(path: &Path) -> bool {
    crate::rar_source::is_rar_path(path)
}

pub fn is_subsequent_volume(path: &Path) -> anyhow::Result<bool> {
    let (_, kind) = crate::rar_source::resolved_volume_path(path)?;
    Ok(matches!(kind, crate::rar_source::RarVolumeKind::Subsequent))
}
