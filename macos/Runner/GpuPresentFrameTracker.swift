import Foundation

/// 记录发布与 Flutter 首次取帧，不将取帧误当成物理屏幕呈现。
/// worker、平台线程和 raster 线程都可能调用，内部状态由同一把锁保护。
final class GpuPresentFrameTracker {
    private struct Frame {
        let serial: UInt64
        let index: UInt32
        let requestedAt: UInt64
        let publishedAt: UInt64
        var notifiedAt: UInt64?
        var acquiredAt: UInt64?
    }

    private let lock = NSLock()
    private var current: Frame?
    private var published: UInt64 = 0
    private var marked: UInt64 = 0
    private var acquired: UInt64 = 0
    private var copyCalls: UInt64 = 0
    private var supersededBeforeAcquire: UInt64 = 0
    private var lastAcquiredSerial: UInt64 = 0

    /// 与 currentPixelBuffer 的替换一起在桥的 bufferLock 中调用。
    func publish(index: UInt32, requestedAt: UInt64, at: UInt64) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if let frame = current, frame.acquiredAt == nil {
            supersededBeforeAcquire += 1
        }
        published += 1
        current = Frame(serial: published, index: index, requestedAt: requestedAt, publishedAt: at)
        return published
    }

    /// 避免已经被新帧替换的主线程回调反复通知同一张当前缓冲区。
    /// 时间戳记录通知调用前的时刻，包含调用本身和引擎调度的等待。
    func notify(serial: UInt64, at: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard current?.serial == serial, current?.notifiedAt == nil else { return false }
        current?.notifiedAt = at
        marked += 1
        return true
    }

    /// 必须在桥的 bufferLock 中，与返回当前缓冲区一起调用。
    /// 重复取同一帧仅增加 copyCalls，不改写首次取帧时刻。
    func acquire(at: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard current != nil else { return }
        copyCalls += 1
        if current?.acquiredAt == nil {
            current?.acquiredAt = at
            acquired += 1
            lastAcquiredSerial = current!.serial
        }
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var values: [String: Any] = [
            "framesPublished": published,
            "framesMarked": marked,
            "textureFramesAcquired": acquired,
            "textureCopyCalls": copyCalls,
            "framesSupersededBeforeAcquire": supersededBeforeAcquire,
            "lastAcquiredFrameSerial": lastAcquiredSerial,
            "frameSerial": current?.serial ?? 0,
            "frameNotified": current?.notifiedAt != nil,
            "frameAcquired": current?.acquiredAt != nil,
        ]
        values["framePageIndex"] = current.map { $0.index as Any } ?? NSNull()
        values["frameAcquiredBeforeNotification"] = current.map { frame in
            guard let acquiredAt = frame.acquiredAt else { return false }
            return frame.notifiedAt.map { acquiredAt < $0 } ?? true
        } ?? false
        values["frameRequestToPublishMs"] = elapsed(current?.requestedAt, current?.publishedAt)
        values["framePublishToNotifyMs"] = elapsed(current?.publishedAt, current?.notifiedAt)
        values["framePublishToAcquireMs"] = elapsed(current?.publishedAt, current?.acquiredAt)
        values["frameNotifyToAcquireMs"] = elapsed(current?.notifiedAt, current?.acquiredAt)
        values["frameRequestToAcquireMs"] = elapsed(current?.requestedAt, current?.acquiredAt)
        return values
    }

    /// 未到达的阶段与先于通知的取帧用 null 表达，不能伪造为 0 ms。
    private func elapsed(_ start: UInt64?, _ end: UInt64?) -> Any {
        guard let start = start, let end = end, end >= start else { return NSNull() }
        return Double(end - start) / 1_000_000
    }
}
