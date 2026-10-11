use super::*;

#[test]
fn foreground_timings_survive_background_render_and_reset_on_cache_hit_or_failure() {
    let directory = std::env::temp_dir().join(format!("rossi_timing_{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    image::RgbaImage::from_fn(32, 24, |x, y| {
        image::Rgba([(x * 7) as u8, (y * 9) as u8, 80, 255])
    })
    .save(directory.join("000.png"))
    .unwrap();
    let mut presenter = MacPresenter::new(24, 16).unwrap();
    presenter.set_prefetch(false);
    presenter.open(&directory).unwrap();
    let mut output = vec![0xaa; 24 * 16 * 4];
    presenter
        .show_into_buffer(0, output.as_mut_ptr(), 96, 24, 16)
        .unwrap();
    let cold = presenter.last;
    let r = cold.resample;
    let stages = [
        r.target_setup_ms,
        r.source_setup_ms,
        r.upload_ms,
        r.mipmap_encode_ms,
        r.mipmap_submit_ms,
        r.render_encode_ms,
        r.render_submit_ms,
        r.readback_encode_ms,
        r.readback_submit_ms,
        r.gpu_wait_ms,
        r.cpu_copy_ms,
    ];
    assert!(stages.iter().all(|v| v.is_finite() && *v >= 0.0));
    assert!(r.gpu_wait_ms > 0.0);
    assert!(r.upload_ms > 0.0);
    assert!(stages.iter().sum::<f64>() <= r.total_ms + 0.01);
    assert!(
        r.total_ms + cold.renderer_lock_ms + cold.frame_capture_ms + cold.frame_cache_publish_ms
            <= cold.render_ms + 0.01
    );
    assert!(cold.render_ms + cold.decode_ms <= cold.total_ms + 0.01);
    assert_eq!(cold.cached_copy_ms, 0.0);

    // 与后台预取使用相同渲染器，但不经过 show：不得篡改前台一帧的归因。
    let shared = presenter.resampler.clone();
    std::thread::spawn(move || {
        let mut destination = vec![0; 8 * 8 * 4];
        shared
            .lock()
            .unwrap()
            .resample_to_buffer(
                &vec![0xff; 16 * 16 * 4],
                16,
                16,
                8,
                8,
                destination.as_mut_ptr(),
                32,
                false,
            )
            .unwrap();
    })
    .join()
    .unwrap();
    assert_eq!(presenter.last.resample.gpu_wait_ms, r.gpu_wait_ms);
    assert_eq!(presenter.last.resample.upload_ms, r.upload_ms);

    let mut cached = vec![0; output.len()];
    presenter
        .show_into_buffer(0, cached.as_mut_ptr(), 96, 24, 16)
        .unwrap();
    assert_eq!(output, cached);
    assert!(presenter.last.cached_copy_ms > 0.0);
    assert_eq!(presenter.last.renderer_lock_ms, 0.0);
    assert_eq!(presenter.last.frame_capture_ms, 0.0);
    assert_eq!(presenter.last.frame_cache_publish_ms, 0.0);
    assert_eq!(presenter.last.resample.total_ms, 0.0);
    assert_eq!(presenter.last.resample.gpu_wait_ms, 0.0);
    assert_eq!(presenter.last.resample.upload_ms, 0.0);

    assert!(presenter
        .show_into_buffer(0, cached.as_mut_ptr(), 1, 24, 16)
        .is_err());
    assert_eq!(presenter.last.total_ms, 0.0);
    assert_eq!(presenter.last.cached_copy_ms, 0.0);
    assert_eq!(presenter.last.resample.total_ms, 0.0);
    drop(presenter);
    std::fs::remove_dir_all(directory).unwrap();
}
