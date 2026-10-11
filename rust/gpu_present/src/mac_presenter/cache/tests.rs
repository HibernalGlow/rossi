use super::*;

fn pixels(bytes: usize) -> Arc<PagePixels> {
    Arc::new(PagePixels {
        width: 1,
        height: 1,
        source_width: 1,
        source_height: 1,
        rgba: vec![0; bytes],
    })
}

fn frame(bytes: usize) -> PreRenderedFrame {
    PreRenderedFrame {
        target_w: 1,
        target_h: 1,
        stride: 4,
        bgra: Arc::new(vec![0; bytes]),
    }
}

fn cache(bytes: usize) -> PageCache {
    PageCache {
        limits: CacheLimits {
            pages: 16,
            raw_pages: 3,
            bytes,
        },
        ..PageCache::default()
    }
}

#[test]
fn every_existing_entry_growth_enforces_budget() {
    for mutation in 0..4 {
        let mut c = cache(12);
        c.insert(CachedPage::new_raw(0, 1, Some(pixels(4))));
        c.insert(CachedPage::new_raw(1, 1, Some(pixels(4))));
        match mutation {
            0 => c.add_pre_rendered(1, 1, frame(8)),
            1 => c.add_pre_rendered_enhanced(1, 1, frame(8)),
            2 => c.set_pixels(1, 1, pixels(12)),
            _ => c.set_enhanced_pixels(1, 1, pixels(8)),
        }
        assert_eq!(c.bytes(), 12, "mutation {mutation}");
        assert!(!c.has(0, 1));
        assert!(c.has(1, 1));
        assert_eq!(c.evicted, 1);
    }
}

#[test]
fn background_growth_keeps_current_page_and_counts_oversize() {
    let mut c = cache(12);
    c.insert(CachedPage::new_raw(0, 1, Some(pixels(8))));
    c.pin(0, 1);
    c.insert(CachedPage::new_raw(1, 1, Some(pixels(8))));
    assert!(c.has(0, 1));
    assert!(!c.has(1, 1));
    assert!(c.store_enhanced_render(0, 1, pixels(16), Some(frame(4))));
    assert_eq!(c.bytes(), 28);
    assert_eq!(c.over_budget_bytes(), 16);
    c.insert(CachedPage::new_raw(2, 1, Some(pixels(4))));
    assert!(!c.has(2, 1));
    c.pin(3, 1);
    assert_eq!(c.bytes(), 0, "翻页后旧页不再享有超预算保留");
    c.clear();
    assert_eq!(c.pinned, None);
}

#[test]
fn raw_count_limit_applies_after_refilling_existing_entries() {
    let mut c = cache(100);
    c.limits.raw_pages = 1;
    c.pin(0, 1);
    c.store_raw_render(0, 1, pixels(4), frame(4));
    c.store_raw_render(1, 1, pixels(4), frame(4));
    c.set_pixels(1, 1, pixels(4));
    assert!(c.entries[0].raw_pixels.is_some());
    assert!(c.entries[1].raw_pixels.is_none());
    assert!(!c.entries[1].pre_rendered_raw.is_empty());
}

#[test]
fn enhanced_pixels_and_frame_are_admitted_together() {
    let mut c = cache(8);
    c.insert(CachedPage::new_raw(0, 1, Some(pixels(4))));
    c.insert(CachedPage::new_raw(1, 1, Some(pixels(4))));
    // 非 LRU 尾部的页面更新超分；总大小仍在预算内时不应先逐出它再留下悬空帧。
    c.limits.bytes = 12;
    assert!(c.store_enhanced_render(0, 1, pixels(4), Some(frame(4))));
    let p = c.entries.iter().find(|p| p.index == 0).unwrap();
    assert!(p.enhanced_pixels.is_some());
    assert_eq!(p.pre_rendered_enhanced.len(), 1);
    assert!(!c.has(1, 1));
    assert_eq!(c.bytes(), 12);
}
