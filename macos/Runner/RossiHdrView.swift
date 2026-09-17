import Cocoa
import CoreVideo
import FlutterMacOS
import Metal

/// GPU / HDR 通路的文件日志。
///
/// 写文件而不是只靠 `NSLog`：`NSLog` 只在从终端启动时才看得到，
/// 而从 Finder 双击打开的实例它的输出会迷路。这条通路的失败模式
/// （图层没建、接管没成、blit 被拒……）恰恰都是"画面就是黑的，没别的线索"，
/// 所以日志必须无条件生效。
func rossiGpuLog(_ message: String) {
    let line = "[\(Date().timeIntervalSince1970)] pid=\(ProcessInfo.processInfo.processIdentifier) \(message)\n"
    NSLog("[RossiGPU] %@", message)
    let path = "/tmp/breeze_gpu.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// 真 HDR（EDR / Extended Dynamic Range）画面视图。
///
/// # 为什么必须是一个原生平台视图，而不是 Flutter 外部纹理
///
/// Flutter 的 `FlutterTexture` 通路在 macOS 引擎里把像素格式**写死**为
/// `MTLPixelFormatBGRA8Unorm`（见引擎源码
/// `shell/platform/darwin/macos/framework/Source/FlutterExternalTexture.mm`
/// 里 `populateTextureFromRGBAPixelBuffer:` 的 `pixelFormat` 实参）。
/// 8 位无符号归一化纹理的物理上限就是 1.0 —— 无论 Rust 侧着色器算出多亮的数值，
/// 进 Flutter 之前都会被钳回 SDR 白点。所以「真 HDR」在 Flutter 纹理通路上
/// **不可能**成立；那上面能做的只有 SDR 增强（逆色调映射后压回 [0,1]）。
///
/// 这条路绕开 Flutter 合成器：自己起一个 `CAMetalLayer`，打开
/// `wantsExtendedDynamicRangeContent`、颜色空间设为 `extendedLinearSRGB`。
/// 图层里的数值 1.0 对应 SDR 参考白（约 100 nit），**大于 1.0 的部分由 macOS
/// 合成器直接交给显示器的 EDR 头顶空间**（本机外接屏实测 4.36x ≈ 436 nit）。
///
/// # 为什么用平台视图而不是自己往窗口上贴一个 NSView
///
/// 因为它必须和 Flutter 图层树**共用同一套图层顺序**。引擎的
/// `FlutterCompositor` 把每个平台视图容器的 `layer.zPosition` 设成它在图层树里的
/// 下标（`FlutterCompositor.mm`：`container.layer.zPosition = index`），而 Flutter
/// 自己的内容图层用的是同一个下标空间（`FlutterSurfaceManager.mm`：
/// `layer.zPosition = info.zIndex`）。于是：
///
/// 1. 画面位置与尺寸由 Flutter 布局决定（不写死坐标）；
/// 2. 阅读器的顶/底控制栏画在页面**之上**时 zPosition 更大，会正确压在 HDR 画面上，
///    不会被原生图层盖掉。
///
/// 自己往窗口贴 NSView 两条都做不到。
final class RossiHdrView: NSView {
    /// 由桥注入的取帧动作：把第 `index` 页渲染进给定的物理缓冲区。
    /// 返回 `nil` 表示成功，否则是失败原因。
    var onRender: ((_ width: Int, _ height: Int,
                    _ base: UnsafeMutableRawPointer, _ stride: Int,
                    _ index: UInt32) -> String?)?

    /// 当前应该显示的页下标。由 Dart 侧推进来。
    var requestedIndex: UInt32 = 0

    /// 已经渲染过至少一帧（用于区分「还没画」与「画过但尺寸变了」）。
    private(set) var hasFrame = false

    /// 最近一次渲染失败的原因（诊断用）。
    private(set) var lastFailure: String?

    private var metalLayer: CAMetalLayer?
    private let device = MTLCreateSystemDefaultDevice()
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var pixelBuffer: CVPixelBuffer?

    /// 防止 resize → 重渲染 → resize 的自激回路。
    private var isRerendering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        let ml = CAMetalLayer()
        ml.device = device
        // 扩展线性 RGBA16F：唯一能承载 > 1.0 亮度、且被 macOS EDR 直接消费的组合。
        ml.pixelFormat = .rgba16Float
        ml.framebufferOnly = false
        ml.isOpaque = true
        ml.wantsExtendedDynamicRangeContent = true
        ml.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        ml.allowsNextDrawableTimeout = true
        layer = ml
        metalLayer = ml

        if let device = device {
            commandQueue = device.makeCommandQueue()
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }
        rossiGpuLog("RossiHdrView EDR 图层就绪 device=\(device?.name ?? "nil") pixelFormat=rgba16Float colorspace=extendedLinearSRGB")
    }

    // MARK: - 尺寸

    /// 当前视图的物理像素尺寸（Flutter 布局尺寸 × 屏幕缩放）。
    var pixelSize: CGSize {
        let scale = window?.backingScaleFactor ?? 2.0
        let w = max(1, Int((bounds.width * scale).rounded()))
        let h = max(1, Int((bounds.height * scale).rounded()))
        return CGSize(width: w, height: h)
    }

    override func layout() {
        super.layout()
        handleGeometryChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        handleGeometryChange()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        handleGeometryChange()
    }

    /// 尺寸变化后：同步 drawable，并在已经画过内容时按新尺寸重画一次。
    ///
    /// 必须重画：`show_into_buffer` 是按当时的尺寸渲染的，尺寸一变，
    /// 旧缓冲与新 drawable 尺寸不一致，blit 会直接失败（尺寸必须严格相等），
    /// 表现就是拖窗口时画面消失。
    private func handleGeometryChange() {
        guard let ml = metalLayer else { return }
        let size = pixelSize
        if ml.drawableSize != size {
            ml.drawableSize = size
            pixelBuffer = nil
        }
        guard hasFrame, !isRerendering else { return }
        isRerendering = true
        defer { isRerendering = false }
        renderFrame(index: requestedIndex)
    }

    // MARK: - 像素缓冲

    /// 确保存在一块与当前视图同尺寸的 64RGBAHalf（扩展线性半精度浮点）缓冲。
    ///
    /// `kCVPixelFormatType_64RGBAHalf` 是这条链路的关键：每通道 16 位浮点，
    /// 数值上限远高于 1.0，正好承载 Rust 逆色调映射输出的白点倍率。
    /// 用 8 位格式就永远只有 SDR —— 这一点不能妥协。
    func ensurePixelBuffer() -> CVPixelBuffer? {
        let size = pixelSize

        if let buf = pixelBuffer,
           CVPixelBufferGetWidth(buf) == Int(size.width),
           CVPixelBufferGetHeight(buf) == Int(size.height) {
            return buf
        }

        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_64RGBAHalf,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: false,
            kCVPixelBufferCGBitmapContextCompatibilityKey: false,
        ]

        var buf: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_64RGBAHalf,
                                         attrs as CFDictionary,
                                         &buf)
        guard status == kCVReturnSuccess, let created = buf else {
            NSLog("[RossiHdrView] 创建 64RGBAHalf 缓冲失败: CVReturn %d", status)
            return nil
        }
        // 明确标注为线性传递函数 + Rec.709 原色：macOS 合成器据此决定
        // 是否动用 EDR 头顶空间。缺了这两个标注，值 > 1.0 的内容会被当成越界裁掉。
        CVBufferSetAttachment(created, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(created, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_Linear, .shouldPropagate)
        CVBufferSetAttachment(created, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)

        pixelBuffer = created
        rossiGpuLog("RossiHdrView 分配 HDR 缓冲 \(Int(size.width))x\(Int(size.height)) (64RGBAHalf, extendedLinear)")
        return created
    }

    /// 渲染并上屏一帧。返回 `nil` 表示成功。
    @discardableResult
    func renderFrame(index: UInt32) -> String? {
        requestedIndex = index
        guard let render = onRender else {
            lastFailure = "HDR 视图尚未与呈现器绑定"
            return lastFailure
        }
        guard let buf = ensurePixelBuffer() else {
            lastFailure = "无法分配 HDR 像素缓冲"
            return lastFailure
        }

        CVPixelBufferLockBaseAddress(buf, [])
        guard let base = CVPixelBufferGetBaseAddress(buf) else {
            CVPixelBufferUnlockBaseAddress(buf, [])
            lastFailure = "HDR 像素缓冲基址为空"
            return lastFailure
        }
        let stride = CVPixelBufferGetBytesPerRow(buf)
        let width = CVPixelBufferGetWidth(buf)
        let height = CVPixelBufferGetHeight(buf)

        let failure = render(width, height, base, stride, index)
        CVPixelBufferUnlockBaseAddress(buf, [])

        if let failure = failure {
            lastFailure = failure
            rossiGpuLog("RossiHdrView 渲染失败 index=\(index) size=\(width)x\(height): \(failure)")
            return failure
        }
        lastFailure = nil
        hasFrame = true
        present()
        rossiGpuLog("RossiHdrView 已上屏 index=\(index) size=\(width)x\(height)")
        return nil
    }

    // MARK: - 上屏

    /// 把像素缓冲拷进 EDR drawable 并提交。
    ///
    /// 用 blit 而不是画一个全屏三角形：源缓冲与 drawable 是**同格式同尺寸**的
    /// 纹理，直接拷贝即可 —— 不需要着色器、不需要管线，更重要的是**不引入任何
    /// 色彩转换**：任何多余的转换都会把 > 1.0 的部分重新压回 SDR。
    private func present() {
        guard let ml = metalLayer,
              let textureCache = textureCache,
              let commandQueue = commandQueue,
              let buf = pixelBuffer else {
            return
        }
        let size = pixelSize
        if ml.drawableSize != size {
            ml.drawableSize = size
        }
        guard let drawable = ml.nextDrawable() else {
            rossiGpuLog("RossiHdrView nextDrawable 返回 nil（图层未上屏或尺寸为 0）")
            return
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buf,
            nil,
            .rgba16Float,
            Int(size.width),
            Int(size.height),
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let src = CVMetalTextureGetTexture(cvTexture) else {
            rossiGpuLog("RossiHdrView 无法从像素缓冲建立 Metal 纹理: CVReturn \(status)")
            return
        }

        guard let cmd = commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else {
            rossiGpuLog("RossiHdrView 无法建立 blit 编码器")
            return
        }
        rossiGpuLog("RossiHdrView blit \(src.width)x\(src.height)(\(src.pixelFormat.rawValue)) -> drawable \(drawable.texture.width)x\(drawable.texture.height)(\(drawable.texture.pixelFormat.rawValue))")
        blit.copy(from: src, to: drawable.texture)
        blit.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// 丢弃当前帧（例如切换 HDR 参数、切页前清屏）。
    func invalidateFrame() {
        pixelBuffer = nil
        hasFrame = false
    }

    /// 让当前这一页重新走一遍渲染。
    @discardableResult
    func refresh() -> String? {
        invalidateFrame()
        return renderFrame(index: requestedIndex)
    }

    /// 诊断快照：Dart 侧用它显示「这条通路现在到底有没有在工作」。
    func diagnostics() -> [String: Any] {
        let size = pixelSize
        return [
            "viewId": String(describing: ObjectIdentifier(self)),
            "pixelWidth": Int(size.width),
            "pixelHeight": Int(size.height),
            "drawableWidth": Int(metalLayer?.drawableSize.width ?? 0),
            "drawableHeight": Int(metalLayer?.drawableSize.height ?? 0),
            "hasFrame": hasFrame,
            "requestedIndex": Int(requestedIndex),
            "edrContent": metalLayer?.wantsExtendedDynamicRangeContent ?? false,
            "colorspace": "extendedLinearSRGB",
            "pixelFormat": "rgba16Float",
            "cvsPixelFormat": "64RGBAHalf",
            "lastFailure": lastFailure ?? "",
        ]
    }
}

/// 平台视图工厂：把 `RossiHdrView` 交给 Flutter 布局。
final class RossiHdrViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var bridge: GpuPresentBridgeMac?

    init(bridge: GpuPresentBridgeMac) {
        self.bridge = bridge
        super.init()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let view = RossiHdrView(frame: .zero)
        view.onRender = { [weak bridge] width, height, base, stride, index in
            guard let bridge = bridge else {
                return "HDR 桥已释放"
            }
            return bridge.renderHdrFrame(width: width,
                                         height: height,
                                         base: base,
                                         stride: stride,
                                         index: index)
        }
        bridge?.attachHdrView(view, identifier: viewId)
        rossiGpuLog("RossiHdrView 平台视图已创建 id=\(viewId)")
        return view
    }
}
