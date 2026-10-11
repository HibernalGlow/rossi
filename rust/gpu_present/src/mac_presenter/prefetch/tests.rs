use super::*;

#[test]
fn idle_wait_requires_a_new_event_and_shutdown_unblocks_it() {
    let hub = Arc::new(PrefetchHub::new(4, 4));
    let (tx, rx) = std::sync::mpsc::channel();
    let worker_hub = hub.clone();
    let worker = thread::spawn(move || {
        tx.send(worker_hub.wait_for_work(0).is_none()).unwrap();
    });
    assert!(rx.recv_timeout(Duration::from_millis(60)).is_err());
    hub.shutdown();
    assert!(rx.recv_timeout(Duration::from_secs(1)).unwrap());
    worker.join().unwrap();
}

#[test]
fn foreground_guard_restores_work_on_error_and_source_changes_reject_old_results() {
    let hub = Arc::new(PrefetchHub::new(4, 4));
    hub.wake();
    let original = hub.shared.lock().unwrap().clone();
    assert!(hub.ready(original.revision));
    {
        let _guard = hub.foreground();
        let revision = hub.shared.lock().unwrap().revision;
        assert!(!hub.ready(revision));
    }
    let revision = hub.shared.lock().unwrap().revision;
    assert!(hub.ready(revision));
    hub.clear_source(2);
    let mut published = false;
    assert!(!hub.publish(&original, |_| published = true));
    assert!(!published);
    hub.set_enabled(false);
    let revision = hub.shared.lock().unwrap().revision;
    assert!(!hub.ready(revision));
}

#[test]
fn budget_eviction_does_not_keep_decoding_the_same_neighbors() {
    let directory =
        std::env::temp_dir().join(format!("rossi_prefetch_budget_{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    for i in 0..4 {
        image::RgbaImage::from_pixel(2, 2, image::Rgba([80, 0, 0, 255]))
            .save(directory.join(format!("{i}.png")))
            .unwrap();
    }
    let source = Arc::new(LocalSource::open(&directory).unwrap());
    let shared = Arc::new(SharedCache::new());
    shared.cache.lock().unwrap().set_test_budget(32);
    let presenter = MacPresenter::new(4, 4).unwrap();
    let hub = Arc::new(PrefetchHub::new(4, 4));
    let worker = spawn_prefetch_worker(shared.clone(), hub.clone(), presenter.resampler.clone());
    hub.set_anchor(0, source.len(), 1, 4, 4, Some(source));
    {
        let state = hub.shared.lock().unwrap();
        let (state, timeout) = hub
            .cv
            .wait_timeout_while(state, Duration::from_secs(5), |v| {
                v.completed_revision != v.revision
            })
            .unwrap();
        assert!(!timeout.timed_out(), "预算拒绝后应完成本轮并休眠");
        assert_eq!(state.completed_revision, state.revision);
    }
    let count = shared.cache.lock().unwrap().prefetched;
    assert_eq!(count, 4, "每个页面只解码一次");
    hub.shutdown();
    worker.join().unwrap();
    assert_eq!(shared.cache.lock().unwrap().prefetched, count);
    assert!(shared.cache.lock().unwrap().bytes() <= 32);
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn identical_dimensions_do_not_restart_completed_work() {
    let hub = PrefetchHub::new(4, 4);
    hub.update_dimensions(4, 4);
    assert_eq!(hub.shared.lock().unwrap().revision, 0);
    hub.update_dimensions(8, 4);
    assert_eq!(hub.shared.lock().unwrap().revision, 1);
}
