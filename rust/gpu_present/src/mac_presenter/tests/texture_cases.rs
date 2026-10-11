use super::*;

#[test]
fn texture_stats_do_not_wait_for_in_flight_gpu_work() {
    let presenter = MacPresenter::new(32, 32).unwrap();
    let idle = presenter.stats_json();
    assert!(idle.contains("\"sourceMipLevels\":0"));
    assert!(idle.contains("\"sourceTextureTexelBytes\":0"));
    let resampler = presenter.resampler.clone();
    let guard = resampler.lock().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    let query = std::thread::spawn(move || {
        tx.send(presenter.stats_json()).unwrap();
    });
    let result = rx.recv_timeout(Duration::from_secs(1));
    // 先释放锁再 join，失败时也不会把测试线程留在阻塞状态。
    drop(guard);
    query.join().unwrap();
    let busy = result.expect("诊断查询不得等待渲染器锁");
    assert!(busy.contains("\"sourceMipLevels\":null"));
    assert!(busy.contains("\"sourceGeneratedMipLevels\":null"));
    assert!(busy.contains("\"sourceTextureTexelBytes\":null"));
}
