// swiftc macos/Runner/GpuPresentWorkScheduler.swift test/macos/gpu_present_scheduler_test.swift -o /tmp/gpu-present-scheduler-test
import Foundation

@main
struct SchedulerTests {
    static func main() {
        checkOrder(kinds: [.prepare, .prepare, .display, .display], expected: [2, 3, 0, 1])
        checkOrder(kinds: [.prepare, .ordered, .display, .prepare, .display], expected: [0, 1, 2, 4, 3])
        checkOrder(kinds: [.prepare, .display, .ordered, .display], expected: [1, 0, 2, 3])
        checkConcurrentProducers()
        print("GPU scheduler: display priority, ordering boundaries and concurrent submissions passed")
    }

    static func checkOrder(kinds: [GpuPresentWorkScheduler.Kind], expected: [Int]) {
        let scheduler = GpuPresentWorkScheduler()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        var order: [Int] = []
        // 模拟不可抢占的原生任务，确保后续任务排齐后才选择下一项。
        group.enter()
        scheduler.async(kind: .prepare) { _ in
            started.signal()
            precondition(release.wait(timeout: .now() + 5) == .success)
            group.leave()
        }
        precondition(started.wait(timeout: .now() + 5) == .success)
        for (i, kind) in kinds.enumerated() {
            group.enter()
            scheduler.async(kind: kind) { waitMs in
                precondition(waitMs >= 0)
                order.append(i)
                group.leave()
            }
        }
        release.signal()
        precondition(group.wait(timeout: .now() + 5) == .success)
        precondition(order == expected, "Unexpected order: \(order), wanted \(expected)")
    }

    static func checkConcurrentProducers() {
        let scheduler = GpuPresentWorkScheduler()
        let group = DispatchGroup()
        let outputLock = NSLock()
        var executed = Set<Int>()
        var active = 0
        var maxActive = 0
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            group.enter()
            scheduler.async(kind: i % 3 == 0 ? .display : .prepare) { _ in
                outputLock.lock()
                active += 1
                maxActive = max(maxActive, active)
                precondition(executed.insert(i).inserted, "Executed twice: \(i)")
                outputLock.unlock()
                // 给其他生产者入队的机会，检测 drain 停止/重启时是否丢任务。
                Thread.sleep(forTimeInterval: 0.0001)
                outputLock.lock()
                active -= 1
                outputLock.unlock()
                group.leave()
            }
        }
        precondition(group.wait(timeout: .now() + 5) == .success)
        precondition(executed.count == 400)
        precondition(maxActive == 1)
    }
}
