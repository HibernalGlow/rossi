    // 搬家接线（非搬动内容）：本文件挂在 `tests` 模块下，`super::*` 够不到宿主模块，
// 用绝对路径补一条与原先 `use super::*` 等价的 glob；可见性按 Rust 作用域规则取最小。
use crate::page_load_scheduler::*;

use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::sync::mpsc;
    use std::time::Duration;

    fn wait_until(mut predicate: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !predicate() {
            assert!(Instant::now() < deadline, "condition timed out");
            std::thread::yield_now();
        }
    }

    fn test_ticket(
        scheduler: &FsPageLoadScheduler,
        owner: u64,
        idx: usize,
        priority: FsPageLoadPriority,
        contract: FsPageLoadContract,
    ) -> FsPageLoadTicket {
        scheduler.request(owner, idx, priority, contract, None, 0)
    }

    #[test]
    fn slow_read_and_decode_stay_within_process_budget() {
        let scheduler = FsPageLoadScheduler::with_limits(3, 1);
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let active = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let mut tickets = Vec::new();
        let mut workers = Vec::new();

        for idx in 0_usize..12 {
            let priority = if idx < 2 {
                FsPageLoadPriority::High
            } else {
                FsPageLoadPriority::Normal
            };
            let ticket = test_ticket(
                &scheduler,
                (idx % 2) as u64,
                idx,
                priority,
                FsPageLoadContract::Sequential,
            );
            let waiter = ticket.waiter();
            let gate = Arc::clone(&gate);
            let active = Arc::clone(&active);
            let peak = Arc::clone(&peak);
            workers.push(std::thread::spawn(move || {
                let _permit = waiter.acquire_cancellable().expect("request admitted");
                let now = active.fetch_add(1, Ordering::SeqCst) + 1;
                peak.fetch_max(now, Ordering::SeqCst);
                let (open, changed) = &*gate;
                let mut open = open.lock().unwrap();
                while !*open {
                    open = changed.wait(open).unwrap();
                }
                active.fetch_sub(1, Ordering::SeqCst);
            }));
            tickets.push(ticket);
        }

        wait_until(|| {
            let stats = scheduler.stats();
            stats.running + stats.cancelling == 3
        });
        let stats = scheduler.stats();
        assert_eq!(stats.running, 3);
        assert!(stats.running_normal <= 2);
        assert!(peak.load(Ordering::SeqCst) <= 3);

        let (open, changed) = &*gate;
        *open.lock().unwrap() = true;
        changed.notify_all();
        for worker in workers {
            worker.join().unwrap();
        }
        assert_eq!(peak.load(Ordering::SeqCst), 3);
        assert_eq!(scheduler.stats(), FsPageLoadSchedulerStats::default());
        drop(tickets);
    }

    #[test]
    fn parked_waiter_wakes_when_the_head_starts_running() {
        // A waiter that parked while another request was ahead of it must still be
        // admitted once that request starts running and capacity is free. Without a
        // wake-up on the Waiting -> Running transition the budget collapses to one.
        let scheduler = FsPageLoadScheduler::with_limits(3, 0);
        let head = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let follower = test_ticket(
            &scheduler,
            1,
            1,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        let follower_waiter = follower.waiter();
        let (admitted_tx, admitted_rx) = mpsc::channel();
        let worker = std::thread::spawn(move || {
            let _permit = follower_waiter.acquire_cancellable().expect("admitted");
            admitted_tx.send(()).unwrap();
            std::thread::sleep(Duration::from_millis(200));
        });
        // Let the follower park behind the head. No further requests arrive after this.
        std::thread::sleep(Duration::from_millis(150));
        assert!(matches!(
            admitted_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));

        let head_permit = head.waiter().acquire_cancellable().expect("head admitted");
        admitted_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("parked follower must be admitted once the head starts running");
        drop(head_permit);
        worker.join().unwrap();
        drop((head, follower));
    }

    #[test]
    fn cancel_does_not_release_permit_until_worker_finishes() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let first = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let first_permit = first.waiter().acquire_cancellable().unwrap();
        first.cancel();
        assert_eq!(
            scheduler.stats(),
            FsPageLoadSchedulerStats {
                cancelling: 1,
                ..Default::default()
            }
        );

        let second = test_ticket(
            &scheduler,
            1,
            1,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let second_waiter = second.waiter();
        let (started_tx, started_rx) = mpsc::channel();
        let worker = std::thread::spawn(move || {
            let _permit = second_waiter.acquire_cancellable().unwrap();
            started_tx.send(()).unwrap();
        });
        wait_until(|| scheduler.stats().waiting == 1);
        assert!(matches!(
            started_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));

        drop(first_permit);
        started_rx
            .recv_timeout(Duration::from_secs(5))
            .expect("returned permit admits next request");
        worker.join().unwrap();
        drop((first, second));
    }

    #[test]
    fn cancelled_waiter_reads_zero_bytes() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let blocker = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let blocker_permit = blocker.waiter().acquire_cancellable().unwrap();
        let pending = test_ticket(
            &scheduler,
            1,
            1,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        let waiter = pending.waiter();
        let bytes_read = Arc::new(AtomicUsize::new(0));
        let worker_bytes_read = Arc::clone(&bytes_read);
        let worker = std::thread::spawn(move || {
            if let Some(_permit) = waiter.acquire_cancellable() {
                worker_bytes_read.fetch_add(1, Ordering::SeqCst);
            }
        });
        wait_until(|| scheduler.stats().waiting == 1);
        pending.cancel();
        worker.join().unwrap();
        assert_eq!(bytes_read.load(Ordering::SeqCst), 0);
        assert_eq!(scheduler.stats().running, 1);
        drop(blocker_permit);
        drop((blocker, pending));
    }

    #[test]
    fn permit_drop_returns_budget_on_error() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let failed = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let result = (|| -> Result<(), &'static str> {
            let _permit = failed.waiter().acquire_cancellable().unwrap();
            Err("decode failed")
        })();
        assert_eq!(result, Err("decode failed"));
        assert_eq!(scheduler.stats(), FsPageLoadSchedulerStats::default());

        let next = test_ticket(
            &scheduler,
            1,
            1,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        assert!(next.waiter().acquire_cancellable().is_some());
        drop((failed, next));
    }

    #[test]
    fn waiting_prefetch_is_promoted_without_cancel_or_restart() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let blocker = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let blocker_permit = blocker.waiter().acquire_cancellable().unwrap();
        let older = test_ticket(
            &scheduler,
            1,
            1,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        let promoted = test_ticket(
            &scheduler,
            1,
            2,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        promoted.promote_to_high(FsPageLoadContract::Sequential);
        assert!(!promoted.is_cancelled());

        let (order_tx, order_rx) = mpsc::channel();
        let mut workers = Vec::new();
        for (idx, waiter) in [(1, older.waiter()), (2, promoted.waiter())] {
            let order_tx = order_tx.clone();
            workers.push(std::thread::spawn(move || {
                let _permit = waiter.acquire_cancellable().unwrap();
                order_tx.send(idx).unwrap();
            }));
        }
        drop(order_tx);
        wait_until(|| scheduler.stats().waiting == 2);
        drop(blocker_permit);
        assert_eq!(order_rx.recv_timeout(Duration::from_secs(5)).unwrap(), 2);
        for worker in workers {
            worker.join().unwrap();
        }
        drop((blocker, older, promoted));
    }

    #[test]
    fn latest_seek_supersedes_only_waiting_requests_in_same_viewer() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let blocker = test_ticket(
            &scheduler,
            9,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let blocker_permit = blocker.waiter().acquire_cancellable().unwrap();
        let old_same_viewer = test_ticket(
            &scheduler,
            10,
            1,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        let sibling_viewer = test_ticket(
            &scheduler,
            20,
            2,
            FsPageLoadPriority::Normal,
            FsPageLoadContract::Sequential,
        );
        let latest = test_ticket(
            &scheduler,
            10,
            99,
            FsPageLoadPriority::High,
            FsPageLoadContract::LatestSeek,
        );

        assert!(old_same_viewer.is_cancelled());
        assert!(!sibling_viewer.is_cancelled());
        assert!(!latest.is_cancelled());
        assert_eq!(scheduler.stats().waiting, 2);
        drop((old_same_viewer, sibling_viewer, latest));
        drop(blocker_permit);
        drop(blocker);
    }

    #[test]
    fn sequential_burst_keeps_every_accepted_target() {
        let scheduler = FsPageLoadScheduler::with_limits(1, 0);
        let blocker = test_ticket(
            &scheduler,
            1,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let blocker_permit = blocker.waiter().acquire_cancellable().unwrap();
        let requests = (1..=6)
            .map(|idx| {
                test_ticket(
                    &scheduler,
                    1,
                    idx,
                    FsPageLoadPriority::Normal,
                    FsPageLoadContract::Sequential,
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(scheduler.stats().waiting, requests.len());
        assert!(requests.iter().all(|request| !request.is_cancelled()));
        drop(requests);
        drop(blocker_permit);
        drop(blocker);
    }

    #[test]
    fn cancelling_one_running_viewer_does_not_cancel_the_other() {
        let scheduler = FsPageLoadScheduler::with_limits(2, 0);
        let first = test_ticket(
            &scheduler,
            100,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let second = test_ticket(
            &scheduler,
            200,
            0,
            FsPageLoadPriority::High,
            FsPageLoadContract::Sequential,
        );
        let first_permit = first.waiter().acquire_cancellable().unwrap();
        let second_permit = second.waiter().acquire_cancellable().unwrap();
        first.cancel();

        assert!(first.is_cancelled());
        assert!(!second.is_cancelled());
        assert_eq!(scheduler.stats().cancelling, 1);
        assert_eq!(scheduler.stats().running, 1);
        drop((first_permit, second_permit));
        assert_eq!(scheduler.stats(), FsPageLoadSchedulerStats::default());
        drop((first, second));
    }
