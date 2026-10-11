use super::*;

#[test]
fn capture_and_restore_strided_pixels_without_padding_leaks() {
    let width = 3;
    let height = 2;
    let source_stride = 16;
    let mut source = vec![0xee; source_stride * height as usize];
    for y in 0..height as usize {
        for x in 0..width as usize * 4 {
            source[y * source_stride + x] = (y * 20 + x) as u8;
        }
    }
    let frame = unsafe { PreRenderedFrame::capture(source.as_ptr(), source_stride, width, height) };
    assert_eq!(frame.stride, 12);
    assert_eq!(frame.bgra.len(), 24);
    assert_eq!(&frame.bgra[..12], &source[..12]);
    assert_eq!(&frame.bgra[12..], &source[16..28]);

    // 故意偏移一个字节，验证复制与补边不依赖 u32 对齐；首尾哨兵不可写坏。
    let destination_stride = 24;
    let mut destination = vec![0xaa; 1 + destination_stride * 3 + 1];
    unsafe {
        copy_pre_rendered_frame(
            &frame,
            destination.as_mut_ptr().add(1),
            destination_stride,
            4,
            3,
        );
    }
    for y in 0..2 {
        let offset = 1 + y * destination_stride;
        assert_eq!(
            &destination[offset..offset + 12],
            &frame.bgra[y * 12..y * 12 + 12]
        );
        assert!(destination[offset + 12..offset + destination_stride]
            .iter()
            .all(|&v| v == 0));
    }
    assert!(
        destination[1 + 2 * destination_stride..destination.len() - 1]
            .iter()
            .all(|&v| v == 0)
    );
    assert_eq!(destination[0], 0xaa);
    assert_eq!(*destination.last().unwrap(), 0xaa);
}

#[test]
fn capture_packed_buffer_owns_pixels_and_crops_without_touching_guards() {
    let mut source: Vec<u8> = (0..32).collect();
    let frame = unsafe { PreRenderedFrame::capture(source.as_ptr(), 16, 4, 2) };
    source.fill(0xff);
    assert_eq!(*frame.bgra, (0..32).collect::<Vec<u8>>());
    let mut destination = vec![0xaa; 14];
    unsafe { copy_pre_rendered_frame(&frame, destination.as_mut_ptr().add(1), 12, 3, 1) };
    assert_eq!(&destination[1..13], &frame.bgra[..12]);
    assert_eq!(destination[0], 0xaa);
    assert_eq!(destination[13], 0xaa);
}

#[test]
fn show_cache_reuses_the_exact_rendered_pixels_with_strided_destination() {
    let directory =
        std::env::temp_dir().join(format!("rossi_single_render_{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let image = image::RgbaImage::from_fn(3, 2, |x, y| {
        image::Rgba([(x * 70) as u8, (y * 110) as u8, 80, 255])
    });
    image.save(directory.join("000.png")).unwrap();
    let mut presenter = MacPresenter::new(7, 5).unwrap();
    presenter.set_prefetch(false);
    presenter.open(&directory).unwrap();
    let stride = 64;
    let mut first = vec![0xaa; stride * 5];
    presenter
        .show_into_buffer(0, first.as_mut_ptr(), stride, 7, 5)
        .unwrap();
    assert!(!presenter.last_prerender_hit);
    {
        let cache = presenter.shared_cache.cache.lock().unwrap();
        let page = cache.entries.iter().find(|p| p.index == 0).unwrap();
        let frame = &page.pre_rendered_raw[0];
        assert_eq!(frame.stride, 28);
        for y in 0..5 {
            assert_eq!(
                &frame.bgra[y * 28..(y + 1) * 28],
                &first[y * stride..y * stride + 28]
            );
        }
    }
    let mut second = vec![0xcc; stride * 5];
    presenter
        .show_into_buffer(0, second.as_mut_ptr(), stride, 7, 5)
        .unwrap();
    assert!(presenter.last_prerender_hit);
    let stats = presenter.stats_json();
    for key in [
        "rendererLockMs",
        "frameCaptureMs",
        "targetSetupMs",
        "uploadMs",
        "gpuWaitMs",
        "cpuCopyMs",
    ] {
        assert!(stats.contains(&format!("\"{key}\":0.00")), "{key}: {stats}");
    }
    assert_eq!(
        first, second,
        "缓存命中与首次渲染应逐字节一致，包括透明行尾"
    );
    let mut invalid = vec![0xaa; 5];
    assert!(presenter
        .show_into_buffer(0, invalid.as_mut_ptr(), 1, 7, 5)
        .is_err());
    assert_eq!(invalid, vec![0xaa; 5]);
    drop(presenter);
    std::fs::remove_dir_all(directory).unwrap();
}
