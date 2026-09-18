//! local_core 没有 mImageViewer 的 Susie 插件宿主；内置扩展名仍直接走 mImageViewer 判定。

pub fn supports_extension(_extension: &str) -> bool {
    false
}
