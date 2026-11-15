import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 启动时是否已经隐藏过一次窗口。
  ///
  /// window_manager 0.7 起插件不再自带 macOS 原生代码（原来的
  /// `NSWindow.hiddenWindowAtLaunch()` 扩展随之消失），这里内联它原本的行为：
  /// nib 在启动时会 order 一次窗口，此时立刻隐藏，等 Dart 侧
  /// `WindowLogic.initWindow` 摆好尺寸/位置后调用 `show()` 再显示，
  /// 避免启动瞬间出现默认尺寸的窗口闪烁跳动。
  private var didHideAtLaunch = false

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

    installFullscreenTitlebarObservers()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if !didHideAtLaunch {
      didHideAtLaunch = true
      setIsVisible(false)
    }
  }

  // MARK: - 原生全屏期间收走标题栏那条

  /// 原生标题栏容器（红绿灯所在的那一层）。
  ///
  /// `window_manager` 的 macOS 实现（`WindowManager.swift` 的 `setTitleBarStyle`）
  /// 让它一直 `isHidden = false`：平时它是透明的，被 Flutter 那条 40px 自制标题栏
  /// 压在上面，看不出来，所以无害；可一旦进了**原生全屏**、自制标题栏按设计让位，
  /// 它就露出来单独占掉顶部一栏（里面只剩红绿灯），并且吃掉那一行的鼠标事件 ——
  /// 现象就是「全屏了，顶上却多出一条只有红绿灯的栏，还盖住内容第一行」。
  ///
  /// window_manager 自己不管这件事（全屏不是它发起的，用户按绿灯 / ⌃⌘F /
  /// 视图菜单进来的它一概不知情），所以只能在这一层把栏收走。
  private var nativeTitlebarContainer: NSView? {
    standardWindowButton(.closeButton)?.superview?.superview
  }

  private func installFullscreenTitlebarObservers() {
    let center = NotificationCenter.default
    // `willEnter` 就收走：全屏动画放完时已经是干净的一屏；`didEnter` 再补一次，
    // 因为系统在全屏落定后会重新布局标题栏，可能把 `isHidden` 顶回去。
    // 用 selector 形式（不是 block）：它在主线程回调、没有并发捕获问题，
    // 且 macOS 10.11+ 会在本对象释放时自动注销，无需手动摘。
    for (selector, name) in [
      (#selector(handleWillEnterFullScreen(_:)), NSWindow.willEnterFullScreenNotification),
      (#selector(handleDidEnterFullScreen(_:)), NSWindow.didEnterFullScreenNotification),
      (#selector(handleDidExitFullScreen(_:)), NSWindow.didExitFullScreenNotification),
    ] {
      center.addObserver(self, selector: selector, name: name, object: self)
    }
  }

  @objc private func handleWillEnterFullScreen(_ notification: Notification) {
    nativeTitlebarContainer?.isHidden = true
  }

  @objc private func handleDidEnterFullScreen(_ notification: Notification) {
    nativeTitlebarContainer?.isHidden = true
  }

  /// **必须成对**：只做进入那一半，窗口退出全屏后就再没有标题栏与红绿灯了。
  @objc private func handleDidExitFullScreen(_ notification: Notification) {
    nativeTitlebarContainer?.isHidden = false
  }
}
