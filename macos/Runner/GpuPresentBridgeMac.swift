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
    private typealias FnResize = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnSetPrefetch = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias FnGeneration = @convention(c) (UnsafeMutableRawPointer?) -> UInt64
    private typealias FnStats = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias FnSetHdr = @convention(c) (UnsafeMutableRawPointer?, UInt32, Float, Float, UnsafeMutablePointer<UInt8>?, Int) -> Int32
    private typealias FnOutputBpp = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias FnSetOutputMode = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt8>?, Int) -> Int32

    private var fnCreate: FnCreate?
    private var fnStatus: FnStatus?
    private var fnOpen: FnOpen?
    private var fnShowIntoBuffer: FnShowIntoBuffer?
    private var fnResize: FnResize?
    private var fnSetPrefetch: FnSetPrefetch?
    private var fnGeneration: FnGeneration?
    private var fnStats: FnStats?
    private var fnDestroy: FnDestroy?
    private var fnSetHdr: FnSetHdr?
    private var fnOutputBpp: FnOutputBpp?
    private var fnSetOutputMode: FnSetOutputMode?

    private var currentPixelFormat: OSType = kCVPixelFormatType_32BGRA
    private var currentHdrMode: UInt32 = 0
    private var currentHdrBoost: Float = 1.5
    private var currentHdrPeak: Float = 1.0

    /// 当前接管的 EDR 平台视图。非 nil 时所有呈现都走它（浮点通路）。
    private weak var hdrView: RossiHdrView?
    private var hdrViewIdentifier: Int64 = -1
    /// 期望的底层输出通路：true = 浮点（真 HDR）。
    private var wantsFloatOutput = false

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
        fnResize = unsafeBitCast(dlsym(h, "rossi_gpu_present_resize"), to: FnResize?.self)
        fnSetPrefetch = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_prefetch"), to: FnSetPrefetch?.self)
        fnGeneration = unsafeBitCast(dlsym(h, "rossi_gpu_present_generation"), to: FnGeneration?.self)
        fnStats = unsafeBitCast(dlsym(h, "rossi_gpu_present_stats"), to: FnStats?.self)
        fnDestroy = unsafeBitCast(dlsym(h, "rossi_gpu_present_destroy"), to: FnDestroy?.self)
        fnSetHdr = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_hdr"), to: FnSetHdr?.self)
        fnOutputBpp = unsafeBitCast(dlsym(h, "rossi_gpu_present_output_bpp"), to: FnOutputBpp?.self)
        fnSetOutputMode = unsafeBitCast(dlsym(h, "rossi_gpu_present_set_output_mode"), to: FnSetOutputMode?.self)
    }

    private var framesMarked: Int = 0
    private var currentPageCount: Int = 0

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

        case "stats":
            handleStats(result: result)

        case "setHdr":
            guard let args = call.arguments as? [String: Any],
                  let mode = args["mode"] as? Int else {
                result(FlutterError(code: "bad-arguments", message: "setHdr 需要 mode (0: Off, 1: Extended Linear, 2: SDR Boost)", details: nil))
                return
            }
            let boost = (args["boost"] as? Double) ?? 1.5
            let peak = (args["peak"] as? Double) ?? 1.0
            handleSetHdr(mode: UInt32(mode), boost: Float(boost), peak: Float(peak), result: result)

        case "hdrStatus":
            handleHdrStatus(result: result)

        case "attachHdrView":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad-arguments", message: "attachHdrView 需要 viewId", details: nil))
                return
            }
            handleAttachHdrView(args, result: result)

        case "hdrDiagnostics":
            handleHdrDiagnostics(result: result)

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
            rossiGpuLog("handleInit 创建呈现器 尺寸=\(width)x\(height) handle=\(presenter != nil ? "非空" : "NULL") err=\(String(cString: err))")
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
        rossiGpuLog("handleInit status=\(s) textureId=\(textureId) bufferPool=\(bufferPool != nil ? "有" : "无") pixelFormat=\(currentPixelFormat)")
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

        let bpp = (presenter != nil && fnOutputBpp != nil) ? Int(fnOutputBpp!(presenter)) : 4
        let pixelFormat: OSType = (bpp == 8) ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA

        if bufferPool != nil && targetWidth == width && targetHeight == height && currentPixelFormat == pixelFormat {
            return
        }

        targetWidth = max(1, width)
        targetHeight = max(1, height)
        currentPixelFormat = pixelFormat

        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 2
        ]
        var pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: targetWidth,
            kCVPixelBufferHeightKey: targetHeight,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true
        ]

        if bpp == 8 {
            pixelBufferAttributes[kCVImageBufferColorPrimariesKey] = kCVImageBufferColorPrimaries_ITU_R_709_2
            pixelBufferAttributes[kCVImageBufferTransferFunctionKey] = kCVImageBufferTransferFunction_Linear
        }

        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &newPool)
        if status == kCVReturnSuccess {
            bufferPool = newPool
        }
    }

    private func handleSetHdr(mode: UInt32, boost: Float, peak: Float, result: @escaping FlutterResult) {
        guard let pres = presenter, let setHdr = fnSetHdr else {
            result(FlutterError(code: "not-ready", message: "呈现器尚未就绪", details: nil))
            return
        }

        var effectivePeak = peak
        // 若为扩展线性 HDR 且未明确指定峰值，则从当前显示器查询可用 EDR Headroom
        if mode == 1 && effectivePeak <= 1.0 {
            let edr = NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
            effectivePeak = Float(max(edr, 1.0))
        }

        var err = [UInt8](repeating: 0, count: 1024)
        let rc = setHdr(pres, mode, boost, effectivePeak, &err, err.count)
        if rc == 0 {
            currentHdrMode = mode
            currentHdrBoost = boost
            currentHdrPeak = effectivePeak
            // 重建匹配新格式与色彩空间的缓冲池
            setupPixelBufferPool(width: targetWidth, height: targetHeight)
            result([
                "ok": true,
                "mode": Int(mode),
                "boost": Double(boost),
                "peak": Double(effectivePeak),
                "bpp": (fnOutputBpp != nil) ? Int(fnOutputBpp!(pres)) : 4
            ])
        } else {
            let msg = String(cString: err)
            result(FlutterError(code: "set-hdr-failed", message: msg.isEmpty ? "设置 HDR 失败" : msg, details: nil))
        }
    }

    private func handleHdrStatus(result: @escaping FlutterResult) {
        let maxEdr = NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
        let potentialEdr = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
        let isHdrScreen = potentialEdr > 1.0

        result([
            "hdrSupported": isHdrScreen,
            "maxEdrHeadroom": maxEdr,
            "potentialEdrHeadroom": potentialEdr,
            "currentMode": Int(currentHdrMode),
            "currentBoost": Double(currentHdrBoost),
            "currentPeak": Double(currentHdrPeak),
            "outputBpp": (presenter != nil && fnOutputBpp != nil) ? Int(fnOutputBpp!(presenter)) : 4
        ])
    }

    // MARK: - EDR（真 HDR）平台视图接管

    /// 由 `RossiHdrViewFactory` 在平台视图创建时调用。
    ///
    /// 一接管就把底层呈现器切到浮点通路：`Rgba16Float` 是唯一能承载
    /// 大于 1.0 亮度的格式，而 8 位通路（Flutter 外部纹理）物理上不可能超过 SDR 白点。
    func attachHdrView(_ view: RossiHdrView, identifier: Int64) {
        hdrView = view
        hdrViewIdentifier = identifier
        wantsFloatOutput = true
        rossiGpuLog("attachHdrView id=\(identifier) presenter=\(presenter != nil ? "已就绪" : "尚未就绪")")
        applyOutputMode()
    }

    /// 由 Dart 侧在平台视图销毁时调用，把底层呈现器退回 8 位通路。
    func detachHdrView(identifier: Int64) {
        // 只接受“当前那个”的释放。翻页时旧槽位会 dispose、新槽位会 attach，
        // 两者的跨语言调用是异步的；不做这个身份校验，晚到的 detach 会把新图层踢掉，
        // 现象是翻一页之后 HDR 就不再生效（而日志里看不出谁干的）。
        guard hdrViewIdentifier == identifier else {
            rossiGpuLog("忽略过期的 detachHdrView id=\(identifier)（当前=\(hdrViewIdentifier)）")
            return
        }
        hdrView = nil
        hdrViewIdentifier = -1
        wantsFloatOutput = false
        applyOutputMode()
    }

    /// 把“期望的输出通路”推给底层呈现器。
    ///
    /// 呈现器可能还没建好（创建是异步的），那时先记下意图，
    /// 等它真正要渲染时再推（见 [renderHdrFrame]）。
    @discardableResult
    private func applyOutputMode() -> Bool {
        guard let pres = presenter, let setOutputMode = fnSetOutputMode else { return false }
        var err = [UInt8](repeating: 0, count: 1024)
        let rc = setOutputMode(pres, wantsFloatOutput ? 1 : 0, &err, err.count)
        if rc != 0 {
            let msg = String(cString: err)
            rossiGpuLog("切换输出通路失败: \(msg)(\(rc))")
            return false
        }
        rossiGpuLog("输出通路 = \(wantsFloatOutput ? "RGBA16F 线性浮点（EDR，可真 HDR）" : "BGRA8（Flutter 纹理）")")
        // 通路一变，适配对象也跟着变：浮点要 8 字节宽度的缓冲池，8 位要 4 字节的。
        // 不改就会让 `show_into_buffer` 往一个尺寸不对的缓冲里写（见那边的
        // 行跨步检查），所以这一步是必须的，不是优化。
        refreshPixelBufferPoolForCurrentPath()
        return true
    }

    /// 按当前输出通路的字节数重建像素缓冲池。
    private func refreshPixelBufferPoolForCurrentPath() {
        let bpp = (presenter != nil && fnOutputBpp != nil) ? Int(fnOutputBpp!(presenter)) : 4
        bufferLock.lock()
        let needsRebuild = currentPixelFormat
            != ((bpp == 8) ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA)
        bufferLock.unlock()
        if needsRebuild {
            setupPixelBufferPool(width: targetWidth, height: targetHeight)
        }
    }

    /// 由 `RossiHdrView` 回调：把第 `index` 页渲染进它给的物理缓冲区。
    ///
    /// 缓冲区由视图用 `kCVPixelFormatType_64RGBAHalf` 分配 —— 半精度浮点，
    /// 数值上限远高于 1.0，这是「真 HDR」能出得了 Rust 边界的前提。
    /// 返回 `nil` 表示成功。
    func renderHdrFrame(width: Int,
                        height: Int,
                        base: UnsafeMutableRawPointer,
                        stride: Int,
                        index: UInt32) -> String? {
        guard let pres = presenter, let showInto = fnShowIntoBuffer else {
            return "底层呈现器尚未就绪"
        }
        // 首次渲染前补推一次输出通路：平台视图可能在呈现器就绪之前就建好了。
        applyOutputMode()

        var err = [UInt8](repeating: 0, count: 1024)
        let rc = showInto(pres,
                          index,
                          base.assumingMemoryBound(to: UInt8.self),
                          stride,
                          UInt32(width),
                          UInt32(height),
                          &err,
                          err.count)
        if rc == 0 {
            framesMarked += 1
            return nil
        }
        let msg = String(cString: err)
        return msg.isEmpty ? "HDR 呈现失败（rc=\(rc)）" : msg
    }

    private func handleAttachHdrView(_ args: [String: Any], result: @escaping FlutterResult) {
        let viewId = args["viewId"] as? Int ?? -1
        rossiGpuLog("attachHdrView(Channel) viewId=\(viewId) 当前图层=\(hdrView != nil ? "已挂" : "未挂")")
        if viewId < 0 {
            detachHdrView(identifier: hdrViewIdentifier)
            result(["ok": true, "attached": false])
            return
        }
        // 平台视图的创建回调已经绑定过一次，这里只做确认与通路切换。
        wantsFloatOutput = true
        applyOutputMode()
        result([
            "ok": hdrView != nil,
            "attached": hdrView != nil,
            "viewId": hdrViewIdentifier,
            "outputBpp": (presenter != nil && fnOutputBpp != nil) ? Int(fnOutputBpp!(presenter)) : 4,
        ])
    }

    private func handleHdrDiagnostics(result: @escaping FlutterResult) {
        var payload: [String: Any] = [
            "attached": hdrView != nil,
            "viewId": hdrViewIdentifier,
            "wantsFloatOutput": wantsFloatOutput,
            "outputBpp": (presenter != nil && fnOutputBpp != nil) ? Int(fnOutputBpp!(presenter)) : 4,
            "hdrMode": Int(currentHdrMode),
            "hdrBoost": Double(currentHdrBoost),
            "hdrPeak": Double(currentHdrPeak),
            "screenMaxEdr": Double(NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0),
        ]
        if let view = hdrView {
            payload["view"] = view.diagnostics()
        }
        result(payload)
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
        // ── EDR（真 HDR）通路 ──
        // 平台视图自己带着一个扩展线性浮点图层，由 macOS 合成器直接把
        // 大于 1.0 的部分交给显示器 EDR 头顶空间。这条路上**不经过**
        // Flutter 的纹理合成，所以那边那个 8 位限制在这里不存在。
        if let view = hdrView {
            rossiGpuLog("show index=\(index) → EDR 图层通路")
            // 进 EDR 通路之前先把输出格式摆正：帧长度必须与视图缓冲区一致。
            // 不做这一步就会出现“呈现器写 8 字节、缓冲区只有 4 字节宽”的堆越界。
            wantsFloatOutput = true
            if !applyOutputMode() {
                rossiGpuLog("EDR 通路不可用（切换输出格式失败），本帧改走 Flutter 纹理通路")
            } else {
                let failure = view.renderFrame(index: index)
                if let failure = failure {
                    rossiGpuLog("EDR 呈现失败: \(failure)")
                    result(FlutterError(code: "show-failed", message: failure, details: nil))
                } else {
                    result(true)
                }
                return
            }
        }
        // Flutter 纹理通路：输出必须是 8 位，否则缓冲池宽度对不上。
        if wantsFloatOutput {
            wantsFloatOutput = false
            applyOutputMode()
        }
        rossiGpuLog("show index=\(index) → Flutter 纹理通路")

        guard let pres = presenter, let showInto = fnShowIntoBuffer, let pool = bufferPool else {
            rossiGpuLog("handleShow 前置条件不满足 presenter=\(presenter != nil) showInto=\(fnShowIntoBuffer != nil) pool=\(bufferPool != nil)")
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

            // ── 安全底色填充（对齐 mimageviewer VRAM Clear 策略）──
            // CVPixelBufferPool 复用的内存可能包含上一帧的脏数据。
            // 在 Rust 侧写入之前，先用对应格式的底色填满整块缓冲区，
            // 防止行跨步 Padding 区域或解码未覆盖区域暴露脏显存。
            if let base = baseAddress {
                let totalBytes = bytesPerRow * height
                if self.currentPixelFormat == kCVPixelFormatType_64RGBAHalf {
                    // 浮点线性格式清零即为纯黑
                    memset(base, 0, totalBytes)
                } else {
                    // BGRA 格式：B=0x0A, G=0x05, R=0x05, A=0xFF
                    let pixelPtr = UnsafeMutableRawPointer(base).bindMemory(to: UInt32.self, capacity: totalBytes / 4)
                    let bgra: UInt32 = 0xFF05050A
                    for i in 0..<(totalBytes / 4) {
                        pixelPtr[i] = bgra
                    }
                }
            }

            var err = [UInt8](repeating: 0, count: 1024)
            let rc = showInto(pres, index, baseAddress, bytesPerRow, UInt32(width), UInt32(height), &err, err.count)
            CVPixelBufferUnlockBaseAddress(buffer, [])

            if rc == 0 {
                self.bufferLock.lock()
                self.currentPixelBuffer = buffer
                self.bufferLock.unlock()

                self.framesMarked += 1
                // 通知 Flutter 引擎新帧到达
                if self.textureId >= 0 {
                    self.textureRegistry?.textureFrameAvailable(self.textureId)
                }

                // 依据此前经验：直接在工作线程上应答，不绕道平台任务队列
                result(true)
            } else {
                let msg = String(cString: err)
                result(FlutterError(code: "show-failed", message: msg.isEmpty ? "呈现失败" : msg, details: nil))
            }
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

