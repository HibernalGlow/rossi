// swiftc macos/Runner/GpuPresentFrameTracker.swift test/macos/gpu_present_frame_tracker_test.swift -o /tmp/gpu-present-frame-tracker-test
import Foundation

@main
struct FrameTrackerTests {
    static func count(_ snapshot: [String: Any], _ key: String) -> UInt64 {
        (snapshot[key] as! NSNumber).uint64Value
    }

    static func checkTime(_ snapshot: [String: Any], _ key: String, _ expected: Double) {
        precondition(abs((snapshot[key] as! Double) - expected) < 0.000001, "Unexpected \(key)")
    }

    static func main() throws {
        checkUnacquiredPublication()
        checkFirstAcquisition()
        checkSupersededFrames()
        checkAcquisitionBeforeNotification()
        checkConcurrentAcquisition()
        try checkConcurrentSnapshots()
        print("GPU frame tracker: publication, actual acquisition, stale notifications, first-acquire timing and concurrency passed")
    }

    static func checkUnacquiredPublication() {
        let tracker = GpuPresentFrameTracker()
        let empty = tracker.snapshot()
        precondition(count(empty, "textureFramesAcquired") == 0)
        precondition(empty["framePageIndex"] is NSNull)
        tracker.acquire(at: 0)
        precondition(count(tracker.snapshot(), "textureCopyCalls") == 0)
        let serial = tracker.publish(index: 7, requestedAt: 1_000_000, at: 4_000_000)
        var values = tracker.snapshot()
        precondition(count(values, "frameSerial") == serial)
        precondition(count(values, "framePageIndex") == 7)
        checkTime(values, "frameRequestToPublishMs", 3)
        precondition(values["framePublishToAcquireMs"] is NSNull)
        precondition(tracker.notify(serial: serial, at: 7_000_000))
        values = tracker.snapshot()
        precondition(count(values, "framesMarked") == 1)
        precondition(count(values, "textureFramesAcquired") == 0,
                     "A notification must not count as an engine acquisition")
        precondition(values["frameRequestToAcquireMs"] is NSNull)
    }

    static func checkFirstAcquisition() {
        let tracker = GpuPresentFrameTracker()
        let serial = tracker.publish(index: 1, requestedAt: 1_000_000, at: 4_000_000)
        precondition(tracker.notify(serial: serial, at: 7_000_000))
        tracker.acquire(at: 11_000_000)
        tracker.acquire(at: 18_000_000)
        precondition(!tracker.notify(serial: serial, at: 20_000_000))
        let values = tracker.snapshot()
        precondition(count(values, "textureFramesAcquired") == 1)
        precondition(count(values, "textureCopyCalls") == 2)
        precondition(count(values, "framesMarked") == 1)
        precondition(values["frameAcquired"] as! Bool)
        precondition(!(values["frameAcquiredBeforeNotification"] as! Bool))
        checkTime(values, "framePublishToAcquireMs", 7)
        checkTime(values, "frameNotifyToAcquireMs", 4)
        checkTime(values, "frameRequestToAcquireMs", 10)
    }

    static func checkSupersededFrames() {
        let tracker = GpuPresentFrameTracker()
        let first = tracker.publish(index: 0, requestedAt: 1, at: 2)
        let second = tracker.publish(index: 1, requestedAt: 3, at: 4)
        precondition(!tracker.notify(serial: first, at: 5))
        precondition(tracker.notify(serial: second, at: 6))
        tracker.acquire(at: 7)
        let third = tracker.publish(index: 2, requestedAt: 8, at: 9)
        let values = tracker.snapshot()
        precondition(count(values, "framesPublished") == 3)
        precondition(count(values, "framesSupersededBeforeAcquire") == 1)
        precondition(count(values, "lastAcquiredFrameSerial") == second)
        precondition(count(values, "frameSerial") == third)
        precondition(!(values["frameAcquired"] as! Bool))
        precondition(values["framePublishToAcquireMs"] is NSNull,
                     "Do not attribute the previous frame's acquisition to the current one")
    }

    static func checkAcquisitionBeforeNotification() {
        let tracker = GpuPresentFrameTracker()
        let serial = tracker.publish(index: 3, requestedAt: 1, at: 2)
        tracker.acquire(at: 3)
        precondition(tracker.snapshot()["frameAcquiredBeforeNotification"] as! Bool)
        precondition(tracker.notify(serial: serial, at: 4))
        let values = tracker.snapshot()
        precondition(values["frameAcquiredBeforeNotification"] as! Bool)
        precondition(values["frameNotifyToAcquireMs"] is NSNull,
                     "An earlier acquisition cannot produce a negative notification delay")
        checkTime(values, "frameRequestToAcquireMs", 0.000002)
    }

    static func checkConcurrentAcquisition() {
        let tracker = GpuPresentFrameTracker()
        let serial = tracker.publish(index: 0, requestedAt: 1, at: 2)
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            _ = tracker.notify(serial: serial, at: 3)
            tracker.acquire(at: UInt64(4 + i))
        }
        let values = tracker.snapshot()
        precondition(count(values, "framesMarked") == 1)
        precondition(count(values, "textureFramesAcquired") == 1)
        precondition(count(values, "textureCopyCalls") == 400)
    }

    static func checkConcurrentSnapshots() throws {
        let tracker = GpuPresentFrameTracker()
        let bufferLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            bufferLock.lock()
            let now = DispatchTime.now().uptimeNanoseconds
            let serial = tracker.publish(index: UInt32(i), requestedAt: now, at: now)
            _ = tracker.notify(serial: serial, at: DispatchTime.now().uptimeNanoseconds)
            tracker.acquire(at: DispatchTime.now().uptimeNanoseconds)
            bufferLock.unlock()
            let values = tracker.snapshot()
            precondition(count(values, "textureFramesAcquired") <= count(values, "framesPublished"))
            precondition(count(values, "framesMarked") <= count(values, "framesPublished"))
            precondition(count(values, "lastAcquiredFrameSerial") <= count(values, "frameSerial"))
        }
        let values = tracker.snapshot()
        precondition(count(values, "framesPublished") == 200)
        precondition(count(values, "textureFramesAcquired") == 200)
        precondition(count(values, "framesSupersededBeforeAcquire") == 0)
        // 保证 NSNull 与 UInt64 计数可以经 MethodChannel 的 JSON probe 传给 Dart。
        let encoded = try JSONSerialization.data(withJSONObject: values)
        let decoded = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(count(decoded, "textureFramesAcquired") == 200)
    }
}
