//! mImageViewer `ActivityGate` 的 local_core 无 UI 适配。

use std::sync::atomic::AtomicBool;

#[derive(Debug, Default)]
pub struct ActivityGate;

impl ActivityGate {
    pub fn wait_until_idle(&self, _cancel: &AtomicBool) {}
}
