import Foundation

/// 保持原生调用串行；翻页可越过未开始的邻页准备，但不能越过换书或缓存注入。
/// 已开始的任务会执行完毕，避免并发调用 FFI 或销毁仍在使用的 presenter。
final class GpuPresentWorkScheduler {
    enum Kind {
        case display
        case prepare
        case ordered
    }

    private struct Job {
        let kind: Kind
        let enqueuedAt: UInt64
        let execute: (Double) -> Void
    }

    private let worker = DispatchQueue(label: "rossi.gpu_present.mac.worker", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: [Job] = []
    private var running = false

    /// waitMs 只计算 Swift 队列等待，不包括 Rust 渲染、引擎取帧或屏幕刷新。
    func async(kind: Kind = .ordered, execute: @escaping (Double) -> Void) {
        lock.lock()
        pending.append(Job(kind: kind, enqueuedAt: DispatchTime.now().uptimeNanoseconds, execute: execute))
        let needsDrain = !running
        running = true
        lock.unlock()
        if needsDrain {
            worker.async { self.drain() }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                running = false
                lock.unlock()
                return
            }
            // ordered 是顺序边界：其前后的 show、open、注入不能互相穿越。
            let boundary = pending.firstIndex { $0.kind == .ordered } ?? pending.endIndex
            let index = pending[..<boundary].firstIndex { $0.kind == .display } ?? 0
            let job = pending.remove(at: index)
            lock.unlock()
            let waitMs = Double(DispatchTime.now().uptimeNanoseconds - job.enqueuedAt) / 1_000_000
            job.execute(waitMs)
        }
    }
}
