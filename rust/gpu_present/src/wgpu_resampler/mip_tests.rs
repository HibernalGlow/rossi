use super::*;

fn resamplers() -> (WgpuResampler, WgpuResampler) {
    let (device, queue) = super::tests::init_test_device().expect("GPU tests require an adapter");
    (
        WgpuResampler::new(device.clone(), queue.clone()).unwrap(),
        WgpuResampler::new(device, queue).unwrap(),
    )
}

fn pixels(width: u32, height: u32, seed: u32) -> Vec<u8> {
    (0..height)
        .flat_map(|y| {
            (0..width).flat_map(move |x| {
                [
                    ((x * 17 + y * 3 + seed * 61) % 256) as u8,
                    ((y * 31 + x / 3 + seed * 37) % 256) as u8,
                    ((x / 2 + y / 2 + seed * 11) % 256) as u8,
                    ((x + y + seed * 19) % 256) as u8,
                ]
            })
        })
        .collect()
}

fn render(
    resampler: &mut WgpuResampler,
    rgba: &[u8],
    width: u32,
    height: u32,
    target_w: u32,
    target_h: u32,
    anime: bool,
) -> Vec<u8> {
    let stride = target_w as usize * 4 + 20;
    let mut result = vec![0xa5; stride * target_h as usize];
    resampler
        .resample_to_buffer(
            rgba,
            width,
            height,
            target_w,
            target_h,
            result.as_mut_ptr(),
            stride,
            anime,
        )
        .unwrap();
    result
}

#[test]
fn texel_capacity_counts_odd_and_thin_mip_chains() {
    for (width, height, levels, bytes) in [
        (1, 1, 1, 4),
        (7, 3, 1, 84),
        (7, 3, 2, 96),
        (7, 3, 3, 100),
        (1, 8, 4, 60),
    ] {
        assert_eq!(source::texel_bytes(width, height, levels), bytes);
    }
}

#[test]
fn limited_mips_match_full_texture_capacity_for_scaling_and_anime4k() {
    let (mut limited, mut full) = resamplers();
    let (width, height) = (513, 385);
    let rgba = pixels(width, height, 0);
    full.get_or_create_source_texture(width, height, full_mip_levels(width, height));
    for (target_w, target_h, anime) in [
        (320, 240, false),
        (128, 96, false),
        (71, 48, false),
        (10, 5, false),
        (900, 650, false),
        (64, 64, true),
    ] {
        let expected = render(&mut full, &rgba, width, height, target_w, target_h, anime);
        let actual = render(
            &mut limited,
            &rgba,
            width,
            height,
            target_w,
            target_h,
            anime,
        );
        assert_eq!(actual, expected, "{target_w}x{target_h}, anime={anime}");
    }
    let (mut anime, _) = resamplers();
    render(&mut anime, &rgba, width, height, 64, 64, true);
    let info = anime.source_texture_info();
    assert_eq!(info.mip_levels, 1, "Anime4K samples only level zero");
    assert_eq!(info.generated_mip_levels, 1);
    assert_eq!(info.texel_bytes, u64::from(width) * u64::from(height) * 4);
}

#[test]
fn reused_texture_regenerates_needed_levels_for_new_pixels_and_zoom() {
    let (mut reused, mut fresh) = resamplers();
    let (width, height) = (512, 384);
    let cases = [
        (16, 12, 6, 6),
        (512, 384, 6, 1),
        (128, 96, 6, 3),
        (8, 6, 7, 7),
    ];
    for (seed, (target_w, target_h, allocated, generated)) in cases.into_iter().enumerate() {
        let rgba = pixels(width, height, seed as u32);
        // 强制参考纹理以本次需要的容量重新建，避免它也复用旧页的下游 mip。
        fresh.source_cache = None;
        let expected = render(&mut fresh, &rgba, width, height, target_w, target_h, false);
        let actual = render(&mut reused, &rgba, width, height, target_w, target_h, false);
        assert_eq!(
            actual, expected,
            "page/zoom step {seed} must not sample stale levels"
        );
        let info = reused.source_texture_info();
        assert_eq!(info.mip_levels, allocated);
        assert_eq!(info.generated_mip_levels, generated);
    }
    // 尺寸变化后不能沿用上一尺寸的 mip 容量或像素。
    let rgba = pixels(129, 97, 5);
    let actual = render(&mut reused, &rgba, 129, 97, 64, 48, false);
    let expected = render(&mut fresh, &rgba, 129, 97, 64, 48, false);
    assert_eq!(actual, expected);
    assert_eq!(reused.source_texture_info().mip_levels, 2);
}
