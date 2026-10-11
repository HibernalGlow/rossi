// swiftc -O script/probe_macos_gpu_present.swift -o /tmp/rossi-gpu-probe
// /tmp/rossi-gpu-probe --library rust/gpu_present/target/release/librossi_gpu_present.dylib --output /tmp/rossi-gpu-probe.json
// 测量 Release 原生库写入真实 IOSurface CVPixelBuffer 的时间，不含 Flutter 合成或屏幕刷新。
import AppKit
import CoreVideo
import CryptoKit
import Darwin
import Foundation

typealias FnCreate = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> UnsafeMutableRawPointer?
typealias FnStatus = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32
typealias FnOpen = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UInt8>?, Int) -> Int32
typealias FnShow = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt8>?, Int, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
typealias FnPrefetch = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
typealias FnStats = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32
typealias FnDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void

private let usage = """
Usage: rossi-gpu-probe [--library path] [--output report.json] [--source folder-or-cbz]
                       [--target WIDTHxHEIGHT] [--source-size WIDTHxHEIGHT]
                       [--cold count] [--warm count] [--compare-clear] [--compare-library path]
Defaults: Release dylib, /tmp/rossi-gpu-probe.json, two synthetic 4096x3072 PNGs,
          target 2560x1600, 8 cold samples, 60 cached samples.
--compare-clear alternates cached shows with/without the old full-buffer clear.
--compare-library alternates cold shows with a reference dylib and compares pixels.
"""
if CommandLine.arguments.contains("--help") { print(usage); exit(0) }
private var options: [String: String] = [:]
private let valueOptions = ["--library", "--output", "--source", "--target", "--source-size", "--cold", "--warm", "--compare-library"]
private var argumentIndex = 1
while argumentIndex < CommandLine.arguments.count {
    let key = CommandLine.arguments[argumentIndex]
    if key == "--compare-clear" {
        options[key] = "true"
        argumentIndex += 1
    } else {
        guard valueOptions.contains(key), argumentIndex + 1 < CommandLine.arguments.count,
              !CommandLine.arguments[argumentIndex + 1].hasPrefix("--") else {
            fputs("Invalid argument: \(key)\n\(usage)\n", stderr)
            exit(2)
        }
        options[key] = CommandLine.arguments[argumentIndex + 1]
        argumentIndex += 2
    }
}
private func argument(_ name: String, default fallback: String) -> String {
    options[name] ?? fallback
}
private func size(_ value: String) -> (Int, Int) {
    let parts = value.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
          (1...16384).contains(width), (1...16384).contains(height) else {
        fputs("Invalid size: \(value)\n", stderr)
        exit(2)
    }
    return (width, height)
}
private func sampleCount(_ option: String, default fallback: String) -> Int {
    let value = argument(option, default: fallback)
    guard let count = Int(value), (2...100000).contains(count) else {
        fputs("Invalid sample count for \(option): \(value)\n", stderr)
        exit(2)
    }
    return count
}

private func distribution(_ values: [Double]) -> [String: Any] {
    let sorted = values.sorted()
    func percentile(_ p: Double) -> Double {
        sorted[max(0, Int(ceil(Double(sorted.count) * p)) - 1)]
    }
    return ["samples": values.count, "p50Ms": percentile(0.5), "p95Ms": percentile(0.95),
            "p99Ms": percentile(0.99), "minMs": sorted.first!, "maxMs": sorted.last!, "valuesMs": values]
}

private func syntheticImage(at url: URL, width: Int, height: Int, seed: Int) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32)!
    let pixels = bitmap.bitmapData!
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bitmap.bytesPerRow + x * 4
            pixels[offset] = UInt8((x + seed * 61) % 256)
            pixels[offset + 1] = UInt8((y + seed * 37) % 256)
            pixels[offset + 2] = UInt8((x / 8 + y / 8) % 256)
            pixels[offset + 3] = 255
        }
    }
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let library = argument("--library", default: "rust/gpu_present/target/release/librossi_gpu_present.dylib")
let output = argument("--output", default: "/tmp/rossi-gpu-probe.json")
let (width, height) = size(argument("--target", default: "2560x1600"))
let (sourceWidth, sourceHeight) = size(argument("--source-size", default: "4096x3072"))
let coldCount = sampleCount("--cold", default: "8")
let warmCount = sampleCount("--warm", default: "60")
let compareClear = options["--compare-clear"] == "true"
// 每个库持有自己的设备和缓存；两边同步完成后才切到另一边，不并发跑 GPU。
final class NativePresenter {
    let dylib: UnsafeMutableRawPointer
    let handle: UnsafeMutableRawPointer
    let open: FnOpen
    let show: FnShow
    let stats: FnStats
    let destroy: FnDestroy
    var error = [UInt8](repeating: 0, count: 4096)
    private var closed = false
    init(library: String, width: Int, height: Int) {
        guard let loaded = dlopen(library, RTLD_NOW | RTLD_LOCAL) else { fatalError(String(cString: dlerror())) }
        dylib = loaded
        func symbol<T>(_ name: String, _ type: T.Type) -> T {
            guard let pointer = dlsym(loaded, name) else { fatalError("Missing symbol: \(name)") }
            return unsafeBitCast(pointer, to: type)
        }
        open = symbol("rossi_gpu_present_open", FnOpen.self)
        show = symbol("rossi_gpu_present_show_into_buffer", FnShow.self)
        stats = symbol("rossi_gpu_present_stats", FnStats.self)
        destroy = symbol("rossi_gpu_present_destroy", FnDestroy.self)
        let create = symbol("rossi_gpu_present_create", FnCreate.self)
        let status = symbol("rossi_gpu_present_status", FnStatus.self)
        let prefetch = symbol("rossi_gpu_present_set_prefetch", FnPrefetch.self)
        guard let pointer = create(UInt32(width), UInt32(height), &error, error.count) else { fatalError("Create failed") }
        handle = pointer
        let deadline = Date().addingTimeInterval(10)
        while status(handle, &error, error.count) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        precondition(status(handle, &error, error.count) == 1, String(cString: error))
        precondition(prefetch(handle, 0) == 0)
    }
    func close() {
        guard !closed else { return }
        closed = true
        destroy(handle)
        dlclose(dylib)
    }
    deinit { close() }
}
let primary = NativePresenter(library: library, width: width, height: height)
defer { primary.close() }
let referenceLibrary = argument("--compare-library", default: "")
let reference = referenceLibrary.isEmpty ? nil : NativePresenter(library: referenceLibrary, width: width, height: height)
defer { reference?.close() }

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("rossi-gpu-probe-\(UUID().uuidString)")
let input = argument("--source", default: "")
let source: URL
if input.isEmpty {
    source = temporary
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for i in 0..<2 {
        try autoreleasepool { try syntheticImage(at: source.appendingPathComponent("\(i).png"),
            width: sourceWidth, height: sourceHeight, seed: i) }
    }
} else {
    source = URL(fileURLWithPath: input)
}
defer { if input.isEmpty { try? FileManager.default.removeItem(at: temporary) } }
func openSource(_ runtime: NativePresenter = primary) -> Int {
    let path = Array(source.path.utf8)
    let count = runtime.open(runtime.handle, path, path.count, &runtime.error, runtime.error.count)
    precondition(count >= 2, "Need two raster pages: \(String(cString: runtime.error))")
    return Int(count)
}
let pageCount = openSource()
let attributes: [CFString: Any] = [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
    kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
    kCVPixelBufferMetalCompatibilityKey: true,
]
var optionalBuffer: CVPixelBuffer?
precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
    attributes as CFDictionary, &optionalBuffer) == kCVReturnSuccess)
let buffer = optionalBuffer!
precondition(CVPixelBufferGetIOSurface(buffer) != nil, "Expected IOSurface-backed buffer")
func probe(_ runtime: NativePresenter = primary) -> [String: Any] {
    var bytes = [UInt8](repeating: 0, count: 8192)
    precondition(runtime.stats(runtime.handle, &bytes, bytes.count) > 0)
    return try! JSONSerialization.jsonObject(with: Data(String(cString: bytes).utf8)) as! [String: Any]
}
func present(_ index: Int, clear: Bool = false, runtime: NativePresenter = primary) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    precondition(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
    let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    // 可选复现旧桥的重复整帧清零，交替测量以减小不同运行之间的偏差。
    if clear { memset(pointer, 0, stride * height) }
    let result = runtime.show(runtime.handle, UInt32(index), pointer, stride, UInt32(width), UInt32(height), &runtime.error, runtime.error.count)
    precondition(CVPixelBufferUnlockBaseAddress(buffer, []) == kCVReturnSuccess)
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    precondition(result == 0, String(cString: runtime.error))
    return ms
}
func snapshot() -> Data {
    precondition(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    return Data(bytes: CVPixelBufferGetBaseAddress(buffer)!, count: CVPixelBufferGetBytesPerRow(buffer) * height)
}
var cold: [Double] = []
var coldPhases: [[String: Any]] = []
var referenceCold: [Double] = []
var referencePhases: [[String: Any]] = []
var expected: [Int: Data] = [:]
let phaseKeys = ["decodeMs", "renderMs", "totalMs", "cacheBytes", "cacheHit", "prerenderHit",
                 "sourceMipLevels", "sourceGeneratedMipLevels", "sourceTextureTexelBytes"]
for i in 0..<coldCount {
    let index = i % 2
    let runs = reference.map { i % 2 == 0 ? [primary, $0] : [$0, primary] } ?? [primary]
    var pairedFrame: Data?
    for runtime in runs {
        _ = openSource(runtime) // 清页面缓存；操作系统文件缓存及 wgpu 管线可保持热态。
        let elapsed = present(index, runtime: runtime)
        let detail = probe(runtime)
        precondition((detail["prerenderHit"] as? Int) == 0)
        let phases = detail.filter { phaseKeys.contains($0.key) }
        if runtime === primary { cold.append(elapsed); coldPhases.append(phases) }
        else { referenceCold.append(elapsed); referencePhases.append(phases) }
        if i < 2 || reference != nil {
            let frame = snapshot()
            if let other = pairedFrame { precondition(frame == other, "Reference library pixels differ") }
            pairedFrame = frame
            if runtime === primary && i < 2 { expected[index] = frame }
        }
    }
}
_ = openSource()
for i in 0..<2 { _ = present(i) }
var warm: [Double] = []
var warmWithClear: [Double] = []
for i in 0..<warmCount {
    let index = i % 2
    // AB / BA 轮换次序，每组使用同一页、同一 buffer、同一个 Release 原生库。
    let modes = compareClear ? (i % 2 == 0 ? [false, true] : [true, false]) : [false]
    for clear in modes {
        let elapsed = present(index, clear: clear)
        if clear { warmWithClear.append(elapsed) } else { warm.append(elapsed) }
        precondition((probe()["prerenderHit"] as? Int) == 1)
        if i < 2 { precondition(snapshot() == expected[index], "Cached pixels differ") }
    }
}
var report: [String: Any] = [
    "timestamp": ISO8601DateFormatter().string(from: Date()), "library": library,
    "source": input.isEmpty ? "synthetic PNG, two patterned pages" : source.path,
    "sourceSize": input.isEmpty ? "\(sourceWidth)x\(sourceHeight)" : "see probe.sourceWidth/sourceHeight",
    "pageCount": pageCount, "targetSize": "\(width)x\(height)",
    "scope": "CVPixelBuffer lock + native show + unlock; optional cachedWithClear also includes full clear; excludes buffer allocation, Swift queue, MethodChannel, Flutter texture acquisition, composition and physical display",
    "coldDefinition": "page cache cleared per sample; file cache and GPU pipelines may be warm",
    "prefetchEnabled": false, "cachedPixelsEqual": true,
    "coldFrameSHA256": Dictionary(uniqueKeysWithValues: expected.map { index, data in
        (String(index), SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }),
    "cold": distribution(cold), "coldPhases": coldPhases, "cached": distribution(warm), "probe": probe(),
    "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
]
if compareClear { report["cachedWithClear"] = distribution(warmWithClear) }
if let reference {
    report["reference"] = ["library": referenceLibrary, "cold": distribution(referenceCold),
        "coldPhases": referencePhases, "probe": probe(reference), "allPairedColdPixelsEqual": true,
        "method": "AB/BA alternating cold shows, same source and CVPixelBuffer, separate native devices/caches, no concurrent GPU jobs"] as [String: Any]
}
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: output))
let coldSummary = distribution(cold)
let warmSummary = distribution(warm)
print("\(width)x\(height) cold p50/p95: \(coldSummary["p50Ms"]!)/\(coldSummary["p95Ms"]!) ms; cached p50/p95: \(warmSummary["p50Ms"]!)/\(warmSummary["p95Ms"]!) ms; report: \(output)")
