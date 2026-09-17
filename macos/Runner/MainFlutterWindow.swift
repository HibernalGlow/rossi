import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var gpuPresentBridge: GpuPresentBridgeMac?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    gpuPresentBridge = GpuPresentBridgeMac(
      textureRegistry: flutterViewController.engine,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    // 注册真 HDR（EDR）画面视图工厂。
    //
    // Flutter 的外部纹理通路在 macOS 引擎里把像素格式写死为 8 位 BGRA，
    // 物理上不可能承载超过 SDR 白点的亮度，所以真 HDR 必须走原生平台视图。
    // 注册之后 Dart 侧用 AppKitView(viewType: 'rossi/hdr_surface') 就能拿到
    // 一个带扩展线性浮点图层、且与 Flutter 图层树共用同一套 zPosition 的原生视图。
    if let bridge = gpuPresentBridge {
      let registrar = flutterViewController.registrar(forPlugin: "RossiHdrView")
      let factory = RossiHdrViewFactory(bridge: bridge)
      registrar.register(factory, withId: "rossi/hdr_surface")
      NSLog("[MainFlutterWindow] 已注册 EDR 平台视图工厂 rossi/hdr_surface")
    }

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
