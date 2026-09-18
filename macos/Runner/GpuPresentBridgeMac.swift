import Cocoa
import FlutterMacOS
import CoreVideo

/// Rossi macOS GPU 上屏桥（IOSurface / Metal 零拷贝外部纹理）。
///
/// 实现了 `FlutterTexture` 协议，并对外承接 `rossi/gpu_present` MethodChannel，
/// 与 Windows 端 C++ 实现完全对齐：
/// 1. tryInit(width, height) -> state, textureId
/// 2. open(path) -> pageCount
/// 3. show(index) -> bool
/// 4. setPrefetch(enabled) -> bool
/// 5. stats() -> map
class GpuPresentBridgeMac: NSObject, FlutterTexture {
    private weak var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var presenter: UnsafeMutableRawPointer?

    private var targetWidth: Int = 100
    private var targetHeight: Int = 100
    private var bufferPool: CVPixelBufferPool?
    private var currentPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    private let workerQueue = DispatchQueue(label: "rossi.gpu_present.mac.worker", qos: .userInitiated)
    private var isDisposed = false

    // FFI 函数指针
    private typealias FnCreate = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> UnsafeMutableRawPointer?
    private typealias FnStatus = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnOpen = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnShowIntoBuffer = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt8>?, Int, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnPrepare = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnResize = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnSetPrefetch = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias FnSetOriginalPreview = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias FnSetEnhancedImage = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafePointer<UInt8>?, Int, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnGeneration = @convention(c) (UnsafeMutableRawPointer?) -> UInt64
    private typealias FnStats = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private var fnCreate: FnCreate?
    private var fnStatus: FnStatus?
    private var fnOpen: FnOpen?
    private var fnShowIntoBuffer: FnShowIntoBuffer?
    private var fnPrepare: FnPrepare?
    private var fnResize: FnResize?
    private var fnSetPrefetch: FnSetPrefetch?
    private var fnSetOriginalPreview: FnSetOriginalPreview?
    private var fnSetEnhancedImage: FnSetEnhancedImage?
    private var fnGeneration: FnGeneration?
    private var fnStats: FnStats?
    private var fnDestroy: FnDestroy?

    init(textureRegistry: FlutterTextureRegistry, binaryMessenger: FlutterBinaryMessenger) {
        self.textureRegistry = textureRegistry
        super.init()

        loadSymbols()
        let channel = FlutterMethodChannel(name: "rossi/gpu_present", binaryMessenger: binaryMessenger)
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    deinit {
        isDisposed = true
        if let pres = presenter, let destroy = fnDestroy {
            destroy(pres)
        }
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
        }
    }

    // MARK: - 动态加载符号
    private func loadSymbols() {
        var handle: UnsafeMutableRawPointer? = dlopen(nil, RTLD_NOW)
        if let h = handle, dlsym(h, "rossi_gpu_present_create") != nil {
            NSLog("[GpuPresentBridgeMac] 在当前进程中直接找到 rossi_gpu_present 符号")
        } else {
            handle = nil
            var candidates: [String] = []

            // 1. 环境变量优先（调试支持）
            if let envPath = ProcessInfo.processInfo.environment["ROSSI_GPU_PRESENT_DYLIB"], !envPath.isEmpty {
                candidates.append(envPath)
            }

            // 2. App Bundle Frameworks 目录
            if let frameworksPath = Bundle.main.privateFrameworksPath {
                candidates.append((frameworksPath as NSString).appendingPathComponent("librossi_gpu_present.dylib"))
            }
            candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/librossi_gpu_present.dylib").path)
            if let exeURL = Bundle.main.executableURL {
                candidates.append(exeURL.deletingLastPathComponent().appendingPathComponent("librossi_gpu_present.dylib").path)
                candidates.append(exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks/librossi_gpu_present.dylib").path)
            }

            // 3. 开发环境 target 路径
            let relativePaths = [
                "rust/target/release/librossi_gpu_present.dylib",
                "rust/target/debug/librossi_gpu_present.dylib",
                "../rust/target/release/librossi_gpu_present.dylib",
                "../rust/target/debug/librossi_gpu_present.dylib",
                "../../rust/target/release/librossi_gpu_present.dylib",
                "../../rust/target/debug/librossi_gpu_present.dylib"
            ]
            let cwd = FileManager.default.currentDirectoryPath
            for rel in relativePaths {
                candidates.append((cwd as NSString).appendingPathComponent(rel))
                candidates.append(rel)
            }

            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
                    if let h = dlopen(path, RTLD_NOW) {
                        if dlsym(h, "rossi_gpu_present_create") != nil {
                            handle = h
                            NSLog("[GpuPresentBridgeMac] 成功加载动态库: \(path)")
                            break
                        } else {
                            dlclose(h)
                        }
                    }
                }
            }
        }

        guard let h = handle else {
            let err = dlerror() != nil ? String(cString: dlerror()) : "未知原因"
            NSLog("[GpuPresentBridgeMac] 无法定位或打开 librossi_gpu_present.dylib: \(err)")
            return
        }

        fnCreate = unsafeBitCast(dlsym(h, "rossi_gpu_present_create"), to: FnCreate?.self)
        fnStatus = unsafeBitCast(dlsym(h, "rossi_gpu_present_status"), to: FnStatus?.self)
        fnOpen = unsafeBitCast(dlsym(h, "rossi_gpu_present_open"), to: FnOpen?.self)
        fnShowIntoBuffer = unsafeBitCast(dlsym(h, "rossi_gpu_present_show_into_buffer"), to: FnShowIntoBuffer?.self)
        fnPrepare = unsafeBitCast(dlsym(h, "rossi_gpu_present_prepare"), to: FnPrepare?.self)
        fnResize = unsafeBitCast(dlsym(h, "rossi_gpu_present_resize"), to: FnResize?.self)
        fnSetPrefetch = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_prefetch"), to: FnSetPrefetch?.self)
        fnSetOriginalPreview = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_original_preview"), to: FnSetOriginalPreview?.self)
        fnSetEnhancedImage = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_enhanced_image"), to: FnSetEnhancedImage?.self)
        fnGeneration = unsafeBitCast(dlsym(h, "rossi_gpu_present_generation"), to: FnGeneration?.self)
        fnStats = unsafeBitCast(dlsym(h, "rossi_gpu_present_stats"), to: FnStats?.self)
        fnDestroy = unsafeBitCast(dlsym(h, "rossi_gpu_present_destroy"), to: FnDestroy?.self)
    }

    private var framesMarked: Int = 0
    private var currentPageCount: Int = 0
    private var currentDisplayedIndex: UInt32?

    // MARK: - FlutterTexture
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let buffer = currentPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - MethodChannel 调度
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init", "tryInit":
            guard let args = call.arguments as? [String: Any],
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "bad-arguments", message: "init 需要 width 和 height", details: nil))
                return
            }
            handleInit(width: width, height: height, result: result)

        case "status":
            handleStatus(result: result)

        case "open":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "bad-arguments", message: "open 需要 path", details: nil))
                return
            }
            handleOpen(path: path, result: result)

        case "show":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "bad-arguments", message: "show 需要 index", details: nil))
                return
            }
            handleShow(index: UInt32(index), result: result)

        case "setPrefetch":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "bad-arguments", message: "setPrefetch 需要 enabled", details: nil))
                return
            }
            if let pres = presenter, let setPrefetch = fnSetPrefetch {
                _ = setPrefetch(pres, enabled ? 1 : 0)
                result(true)
            } else {
                result(false)
            }

        case "setOriginalPreview":
            guard let args = call.arguments as? [String: Any],
                  let active = args["active"] as? Bool else {
                result(FlutterError(code: "bad-arguments", message: "setOriginalPreview 需要 active", details: nil))
                return
            }
            if let pres = presenter, let setOrig = fnSetOriginalPreview {
                _ = setOrig(pres, active ? 1 : 0)
                // 立即重新渲染并提交新帧，让原图/超分切换毫秒级生效！
                if let idx = currentDisplayedIndex {
                    handleShow(index: idx) { _ in }
                } else if textureId >= 0 {
                    textureRegistry?.textureFrameAvailable(textureId)
                }
                result(true)
            } else {
                result(false)
            }

        case "setEnhancedImage":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let path = args["path"] as? String else {
                result(FlutterError(code: "bad-arguments", message: "setEnhancedImage 需要 index 和 path", details: nil))
                return
            }
            let width = (args["width"] as? Int) ?? targetWidth
            let height = (args["height"] as? Int) ?? targetHeight
            handleSetEnhancedImage(index: UInt32(index), path: path, width: width, height: height, result: result)

        case "stats":
            handleStats(result: result)

        case "prepare":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "bad-arguments", message: "prepare 需要 index", details: nil))
                return
            }
            let width = (args["width"] as? Int) ?? targetWidth
            let height = (args["height"] as? Int) ?? targetHeight
            handlePrepare(index: UInt32(index), width: width, height: height, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleStatus(result: @escaping FlutterResult) {
        let isDylibReady = fnCreate != nil
        var stateStr = "ready"
        var errorStr = ""

        if !isDylibReady {
            stateStr = "failed"
            errorStr = "底层 librossi_gpu_present 动态库未就绪"
        }

        result([
            "state": stateStr,
            "textureId": textureId,
            "width": targetWidth,
            "height": targetHeight,
            "adapter": "Apple Silicon (Metal UMA)",
            "luidKnown": true,
            "error": errorStr
        ])
    }

    private func handleInit(width: Int, height: Int, result: @escaping FlutterResult) {
        guard let create = fnCreate, let status = fnStatus else {
            result([
                "ok": false,
                "state": "failed",
                "error": "底层 dylib 符号未就绪"
            ])
            return
        }

        if presenter == nil {
            var err = [UInt8](repeating: 0, count: 1024)
            presenter = create(UInt32(width), UInt32(height), &err, err.count)
        }

        guard let pres = presenter else {
            result([
                "ok": false,
                "state": "failed",
                "error": "创建呈现器失败"
            ])
            return
        }

        if textureId < 0, let registry = textureRegistry {
            textureId = registry.register(self)
        }

        setupPixelBufferPool(width: width, height: height)

        var err = [UInt8](repeating: 0, count: 1024)
        let s = status(pres, &err, err.count)
        switch s {
        case 1: // Ready
            result([
                "ok": true,
                "state": "ready",
                "textureId": textureId,
                "width": targetWidth,
                "height": targetHeight,
                "adapter": "Apple Silicon (Metal UMA)",
                "luidKnown": true,
                "error": ""
            ])
        case 0: // Loading
            result([
                "ok": false,
                "state": "loading",
                "textureId": textureId,
                "width": targetWidth,
                "height": targetHeight,
                "adapter": "Apple Silicon (Metal UMA)",
                "luidKnown": true,
                "error": ""
            ])
        default:
            let errStr = String(cString: err)
            result([
                "ok": false,
                "state": "failed",
                "error": errStr.isEmpty ? "初始化失败" : errStr
            ])
        }
    }

    private func setupPixelBufferPool(width: Int, height: Int) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        if bufferPool != nil && targetWidth == width && targetHeight == height {
            return
        }

        targetWidth = max(1, width)
        targetHeight = max(1, height)

        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 2
        ]
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: targetWidth,
            kCVPixelBufferHeightKey: targetHeight,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true
        ]

        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &newPool)
        if status == kCVReturnSuccess {
            bufferPool = newPool
        }
    }

    private func handleOpen(path: String, result: @escaping FlutterResult) {
        guard let pres = presenter, let open = fnOpen else {
            result(FlutterError(code: "not-ready", message: "呈现器尚未就绪", details: nil))
            return
        }

        workerQueue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            let pathUtf8 = Array(path.utf8)
            var err = [UInt8](repeating: 0, count: 1024)
            let count = open(pres, pathUtf8, pathUtf8.count, &err, err.count)

            if count >= 0 {
                self.currentPageCount = Int(count)
                result(["pageCount": Int(count)])
            } else {
                let msg = String(cString: err)
                result(FlutterError(code: "open-failed", message: msg, details: nil))
            }
        }
    }

    private func handleShow(index: UInt32, result: @escaping FlutterResult) {
        guard let pres = presenter, let showInto = fnShowIntoBuffer, let pool = bufferPool else {
            result(FlutterError(code: "not-ready", message: "呈现器或缓冲池尚未就绪", details: nil))
            return
        }

        let width = targetWidth
        let height = targetHeight

        workerQueue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                result(FlutterError(code: "buffer-alloc-failed", message: "创建 CVPixelBuffer 失败", details: nil))
                return
            }

            CVPixelBufferLockBaseAddress(buffer, [])
            let baseAddress = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

            // ── 安全零填充（对齐 mimageviewer VRAM Clear 策略）──
            // CVPixelBufferPool 复用的内存可能包含上一帧的脏数据。
            // 在 Rust 侧写入之前，先用深黑底色 0xFF05050A (BGRA) 填满整块缓冲区，
            // 防止行跨步 Padding 区域或解码未覆盖区域暴露红黄绿等假彩色块。
            if let base = baseAddress {
                // BGRA 格式：B=0x0A, G=0x05, R=0x05, A=0xFF
                let totalBytes = bytesPerRow * height
                // 按 4 字节（单像素）填充 BGRA 深黑底色
                let pixelPtr = UnsafeMutableRawPointer(base).bindMemory(to: UInt32.self, capacity: totalBytes / 4)
                let bgra: UInt32 = 0xFF05050A  // BGRA little-endian: B=0x0A G=0x05 R=0x05 A=0xFF
                for i in 0..<(totalBytes / 4) {
                    pixelPtr[i] = bgra
                }
            }

            var err = [UInt8](repeating: 0, count: 1024)
            let rc = showInto(pres, index, baseAddress, bytesPerRow, UInt32(width), UInt32(height), &err, err.count)
            CVPixelBufferUnlockBaseAddress(buffer, [])

            if rc == 0 {
                self.bufferLock.lock()
                self.currentPixelBuffer = buffer
                self.currentDisplayedIndex = index
                self.bufferLock.unlock()

                self.framesMarked += 1
                NSLog("[GpuPresentBridgeMac] handleShow 成功 index=\(index), framesMarked=\(self.framesMarked)")

                // 通知 Flutter 引擎新帧到达（必须在主线程调度，确保事件泵送与 Metal 视图重绘）
                if self.textureId >= 0 {
                    let tid = self.textureId
                    DispatchQueue.main.async {
                        self.textureRegistry?.textureFrameAvailable(tid)
                    }
                }

                // 依据此前经验：直接在工作线程上应答，不绕道平台任务队列
                result(true)
            } else {
                let msg = String(cString: err)
                NSLog("[GpuPresentBridgeMac] handleShow 失败 index=\(index), err=\(msg)")
                result(FlutterError(code: "show-failed", message: msg.isEmpty ? "呈现失败" : msg, details: nil))
            }
        }
    }

    private func handleSetEnhancedImage(index: UInt32, path: String, width: Int, height: Int, result: @escaping FlutterResult) {
        guard let pres = presenter, let setEnhanced = fnSetEnhancedImage else {
            NSLog("[GpuPresentBridgeMac] setEnhancedImage 无法执行: presenter=\(String(describing: presenter)), fnSetEnhancedImage=\(String(describing: fnSetEnhancedImage))")
            result(false)
            return
        }
        workerQueue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            guard let pathData = path.data(using: .utf8) else {
                result(FlutterError(code: "bad-path", message: "路径无法转为 UTF-8", details: nil))
                return
            }

            var err = [UInt8](repeating: 0, count: 1024)
            let rc = pathData.withUnsafeBytes { rawBuffer -> Int32 in
                let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return setEnhanced(pres, index, ptr, pathData.count, UInt32(width), UInt32(height), &err, err.count)
            }

            if rc == 0 {
                NSLog("[GpuPresentBridgeMac] setEnhancedImage 成功注入 index=\(index), currentDisplayed=\(String(describing: self.currentDisplayedIndex))")
                if self.currentDisplayedIndex == index {
                    self.handleShow(index: index) { _ in }
                }
                result(true)
            } else {
                let msg = String(cString: err)
                NSLog("[GpuPresentBridgeMac] setEnhancedImage 失败 (rc=\(rc)): \(msg)")
                result(false)
            }
        }
    }

    /// 只预取某一页：解码 + 生成当前视口尺寸的预渲染帧，**不碰上屏缓冲区**。
    ///
    /// 与 `show` 走同一条工作队列，但**不通知引擎取帧**：它不改变正在显示的内容，
    /// 所以不调 `textureFrameAvailable`。位置在这里（而不是让 Dart 去 show 一下）
    /// 就是为了这个区别 —— 邻页 show 会抢走当前页的纹理，那是红黄闪的成因。
    private func handlePrepare(index: UInt32, width: Int, height: Int, result: @escaping FlutterResult) {
        guard let pres = presenter, let prepare = fnPrepare else {
            result(false)
            return
        }
        workerQueue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            var err = [UInt8](repeating: 0, count: 512)
            let rc = prepare(pres, index, UInt32(width), UInt32(height), &err, err.count)
            if rc != 0 {
                let msg = String(cString: err)
                NSLog("[GpuPresentBridgeMac] 预取第 %u 页失败: %@", index, msg)
            }
            result(rc == 0)
        }
    }

    private func handleStats(result: @escaping FlutterResult) {
        guard let pres = presenter, let stats = fnStats else {
            result([
                "ok": false,
                "state": "failed",
                "error": "呈现器尚未就绪"
            ])
            return
        }
        var buf = [UInt8](repeating: 0, count: 4096)
        let written = stats(pres, &buf, buf.count)
        let jsonStr = written > 0 ? String(cString: buf) : "{}"

        result([
            "ok": true,
            "state": "ready",
            "textureId": textureId,
            "width": targetWidth,
            "height": targetHeight,
            "adapter": "Apple Silicon (Metal UMA)",
            "luidKnown": true,
            "framesMarked": framesMarked,
            "handleOpened": framesMarked,
            "resizes": 0,
            "pageCount": currentPageCount,
            "showAsync": true,
            "showBusyRejected": 0,
            "probe": jsonStr
        ])
    }
}

