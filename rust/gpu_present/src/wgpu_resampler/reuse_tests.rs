use super::*;
use rossi_local_core::decode::PagePixels;

fn pair() -> (WgpuResampler, WgpuResampler) {
    let (device, queue) = super::tests::init_test_device().expect("GPU tests require an adapter");
    (
        WgpuResampler::new(device.clone(), queue.clone()).unwrap(),
        WgpuResampler::new(device, queue).unwrap(),
    )
}

fn page(width: u32, height: u32, seed: u8) -> Arc<PagePixels> {
    Arc::new(PagePixels {
        width,
        height,
        source_width: width,
        source_height: height,
        rgba: (0..height)
            .flat_map(|y| {
                (0..width).flat_map(move |x| {
                    [
                        (x * 17 + y * 3) as u8 ^ seed,
                        (x / 3 + y * 31) as u8 ^ seed,
                        (x / 2 + y / 2) as u8 ^ seed,
                        (x + y) as u8 ^ seed,
                    ]
                })
            })
            .collect(),
    })
}

fn render(
    resampler: &mut WgpuResampler,
    pixels: &Arc<PagePixels>,
    width: u32,
    height: u32,
    tracked: bool,
    anime: bool,
) -> (Vec<u8>, ResampleTimings) {
    let stride = width as usize * 4 + 20;
    let mut output = vec![0xa5; stride * height as usize];
    let timings = if tracked {
        resampler.resample_page_to_buffer_timed(
            pixels,
            width,
            height,
            output.as_mut_ptr(),
            stride,
            anime,
        )
    } else {
        resampler.resample_to_buffer_timed(
            &pixels.rgba,
            pixels.width,
            pixels.height,
            width,
            height,
            output.as_mut_ptr(),
            stride,
            anime,
        )
    }
    .unwrap();
    (output, timings)
}

fn compare(
    reused: &mut WgpuResampler,
    reference: &mut WgpuResampler,
    pixels: &Arc<PagePixels>,
    width: u32,
    height: u32,
    anime: bool,
) -> ResampleTimings {
    let (actual, timings) = render(reused, pixels, width, height, true, anime);
    let (expected, _) = render(reference, pixels, width, height, false, anime);
    assert_eq!(
        actual, expected,
        "same source, {width}x{height}, anime={anime}"
    );
    timings
}

#[test]
fn same_pixels_reuse_upload_and_generate_only_missing_mips() {
    let (mut reused, mut reference) = pair();
    let pixels = page(513, 385, 0);
    // 单独覆盖已有容量中的逐级补齐，而不被容量重建掩盖。
    reused.get_or_create_source_texture(513, 385, 8);
    let first = compare(&mut reused, &mut reference, &pixels, 128, 96, false);
    assert!(!first.source_reused);
    assert_eq!(first.uploaded_bytes, 513 * 385 * 4);
    assert_eq!(first.mipmap_generated_levels, 2);
    let deeper = compare(&mut reused, &mut reference, &pixels, 64, 48, false);
    assert!(deeper.source_reused);
    assert_eq!(deeper.uploaded_bytes, 0);
    assert_eq!(deeper.upload_ms, 0.0);
    assert_eq!(deeper.mipmap_generated_levels, 1);
    assert_eq!(reused.source_texture_info().generated_mip_levels, 4);
    for anime in [false, true] {
        let larger = compare(&mut reused, &mut reference, &pixels, 300, 225, anime);
        assert!(larger.source_reused);
        assert_eq!(larger.mipmap_generated_levels, 0);
        assert_eq!(larger.mipmap_encode_ms, 0.0);
        assert_eq!(larger.mipmap_submit_ms, 0.0);
        assert_eq!(reused.source_texture_info().generated_mip_levels, 4);
    }
}

#[test]
fn capacity_growth_and_dimension_change_require_fresh_uploads() {
    let (mut reused, mut reference) = pair();
    let pixels = page(513, 385, 12);
    compare(&mut reused, &mut reference, &pixels, 300, 225, false);
    let growing = compare(&mut reused, &mut reference, &pixels, 64, 48, false);
    assert!(!growing.source_reused);
    assert_eq!(growing.uploaded_bytes, 513 * 385 * 4);
    assert_eq!(growing.mipmap_generated_levels, 3);
    let changed = page(129, 97, 33);
    let resized = compare(&mut reused, &mut reference, &changed, 64, 48, false);
    assert!(!resized.source_reused);
    assert_eq!(resized.uploaded_bytes, 129 * 97 * 4);
    assert_eq!(reused.source_texture_info().mip_levels, 2);
}

#[test]
fn background_overwrite_and_enhanced_replacement_cannot_reuse_stale_content() {
    let (mut reused, mut reference) = pair();
    let raw = page(129, 97, 1);
    let enhanced = page(129, 97, 91);
    let cloned_raw = Arc::new((*raw).clone());
    for pixels in [&raw, &enhanced, &raw, &cloned_raw] {
        let timings = compare(&mut reused, &mut reference, pixels, 64, 48, false);
        assert!(!timings.source_reused);
        assert_eq!(timings.uploaded_bytes, 129 * 97 * 4);
    }
    assert!(compare(&mut reused, &mut reference, &cloned_raw, 66, 50, false).source_reused);
}

#[test]
fn mutable_slice_calls_invalidate_owned_identity_even_at_the_same_address() {
    let (mut reused, mut reference) = pair();
    let owned = page(129, 97, 1);
    compare(&mut reused, &mut reference, &owned, 64, 48, false);
    let mut slice = (*owned).clone();
    let pointer = slice.rgba.as_ptr();
    let stride = 64 * 4;
    for byte in [2, 200] {
        slice.rgba.fill(byte);
        assert_eq!(slice.rgba.as_ptr(), pointer);
        let mut actual = vec![0; stride * 48];
        let mut expected = vec![0; stride * 48];
        let timings = reused
            .resample_to_buffer_timed(
                &slice.rgba,
                129,
                97,
                64,
                48,
                actual.as_mut_ptr(),
                stride,
                false,
            )
            .unwrap();
        reference
            .resample_to_buffer(
                &slice.rgba,
                129,
                97,
                64,
                48,
                expected.as_mut_ptr(),
                stride,
                false,
            )
            .unwrap();
        assert!(!timings.source_reused);
        assert_eq!(actual, expected);
    }
    assert!(!compare(&mut reused, &mut reference, &owned, 64, 48, false).source_reused);
}

#[test]
fn weak_identity_does_not_keep_pixels_alive_and_make_mut_forces_upload() {
    let (mut reused, mut reference) = pair();
    let mut pixels = page(129, 97, 0);
    compare(&mut reused, &mut reference, &pixels, 64, 48, false);
    let old_identity = Arc::downgrade(&pixels);
    assert!(Arc::get_mut(&mut pixels).is_none());
    Arc::make_mut(&mut pixels).rgba.fill(200);
    assert!(old_identity.upgrade().is_none());
    assert!(!compare(&mut reused, &mut reference, &pixels, 64, 48, false).source_reused);
    let remaining = Arc::downgrade(&pixels);
    drop(pixels);
    assert!(
        remaining.upgrade().is_none(),
        "renderer must not retain decoded pixel storage"
    );
    let next = page(129, 97, 4);
    assert!(!compare(&mut reused, &mut reference, &next, 64, 48, false).source_reused);
}
