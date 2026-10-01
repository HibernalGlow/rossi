import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var gpuPresentBridge: GpuPresentBridgeMac?
  /// 必须持有：channel handler 里是 `[weak self]`，没人引用就直接被释放，
  /// Dart 侧只会看到一次超时而看不出为什么。
  private var translationBridge: TranslationBridgeMac?

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
    translationBridge = TranslationBridgeMac()
    translationBridge?.install(on: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
