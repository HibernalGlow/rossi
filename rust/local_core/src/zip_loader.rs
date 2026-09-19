//! mImageViewer `zip_loader::first_image_entry` 的 local_core 适配。

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

pub fn first_image_entry(path: &Path, cancel: Option<&AtomicBool>) -> Option<String> {
    let file = std::fs::File::open(path).ok()?;
    let mut archive = zip::ZipArchive::new(file).ok()?;
    for index in 0..archive.len() {
        if cancel.is_some_and(|flag| flag.load(Ordering::Relaxed)) {
            return None;
        }
        let entry = archive.by_index(index).ok()?;
        if entry.is_file() && crate::page_order::is_page_name(entry.name()) {
            return Some(entry.name().to_owned());
        }
    }
    None
}
