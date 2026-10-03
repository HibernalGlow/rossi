import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private var activity: NSObjectProtocol?
  private var launchLockFD: Int32 = -1
  private var openIntentChannel: FlutterMethodChannel?
  private var pendingOpenPaths: [String] = []
  private var dartAcceptsOpenPaths = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in NSApp.windows {
        if window.isMiniaturized {
          window.deminiaturize(self)
        } else if !window.isVisible {
          window.setIsVisible(true)
        }
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // MARK: - 访达「打开方式 → Rossi」

  /// 与 `lib/service/open_intent/open_intents.dart` 里那条通道同名。
  private static let openIntentChannelName = "com.breeze.macos/openIntent"

  /// Finder 把选中的文件 / 文件夹交给应用的回调（一次可以选中多个）。
  ///
  /// 为什么不读 `ProcessInfo.arguments`：访达不通过命令行递路径，它发的是 `odoc`
  /// Apple event，命令行里什么都没有。
  ///
  /// `super` 必须留着：`FlutterAppDelegate` 这一层会把该回调转发给注册了的插件。
  override func application(_ application: NSApplication, open urls: [URL]) {
    enqueueOpenPaths(urls.map { $0.path })
    super.application(application, open: urls)
  }

  private func enqueueOpenPaths(_ paths: [String]) {
    let usable = paths.filter { !$0.isEmpty }
    guard !usable.isEmpty else { return }
    pendingOpenPaths.append(contentsOf: usable)
    attachOpenIntentChannelIfNeeded()
    flushOpenPaths()
  }

  /// 只在 Dart 侧确认在听了之后主动推；推不出去就留在队列里等它来取
  /// （`takePending`）。队列不是保险丝 —— Dart 的 `main()` 本来就跑在这条回调之后。
  private func flushOpenPaths() {
    guard dartAcceptsOpenPaths, let channel = openIntentChannel else { return }
    guard !pendingOpenPaths.isEmpty else { return }
    let paths = pendingOpenPaths
    pendingOpenPaths = []
    channel.invokeMethod("openPaths", arguments: paths)
  }

  private func attachOpenIntentChannelIfNeeded() {
    guard openIntentChannel == nil else { return }
    // mainWindow 可能还未就绪，回退到遍历所有 window（与上面那条判据同源）。
    let candidate = NSApp.mainWindow?.contentViewController
      ?? NSApp.windows.first(where: { $0.contentViewController is FlutterViewController })?.contentViewController
    guard let controller = candidate as? FlutterViewController else { return }

    let channel = FlutterMethodChannel(
      name: AppDelegate.openIntentChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "takePending":
        let paths = self.pendingOpenPaths
        self.pendingOpenPaths = []
        self.dartAcceptsOpenPaths = true
        result(paths)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    openIntentChannel = channel
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if launchLockFD == -1 {
      let lockPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/Breeze/.launch.lock")
      let fileManager = FileManager.default
      let lockDir = (lockPath as NSString).deletingLastPathComponent

      if !fileManager.fileExists(atPath: lockDir) {
        try? fileManager.createDirectory(
          atPath: lockDir,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }

      launchLockFD = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      if launchLockFD == -1 || flock(launchLockFD, LOCK_EX | LOCK_NB) != 0 {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        for app in runningApps where app.processIdentifier != getpid() {
          app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
          break
        }
        if launchLockFD != -1 {
          close(launchLockFD)
          launchLockFD = -1
        }
        NSApp.terminate(nil)
        return
      }
    }

    // mainWindow 可能还未就绪，回退到遍历所有 window
    guard let controller = (NSApp.mainWindow?.contentViewController
        ?? NSApp.windows.first(where: { $0.contentViewController is FlutterViewController })?.contentViewController) as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }
    let channel = FlutterMethodChannel(name: "com.breeze.macos/activity", binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startActivity":
        self?.startActivity(result: result)
      case "stopActivity":
        self?.stopActivity(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 让 Dart 那边一起来就能把已经攒下的路径取走（不等到首帧之后再晚一步）。
    attachOpenIntentChannelIfNeeded()

    super.applicationDidFinishLaunching(notification)
  }

  private func startActivity(result: @escaping FlutterResult) {
    if activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(
        options: [
          .userInitiated,
          .idleSystemSleepDisabled,
          .suddenTerminationDisabled
        ],
        reason: "正在后台同步/下载漫画"
      )
    }
    result(true)
  }

  private func stopActivity(result: @escaping FlutterResult) {
    if let activity = activity {
      ProcessInfo.processInfo.endActivity(activity)
      self.activity = nil
    }
    result(true)
  }
}
