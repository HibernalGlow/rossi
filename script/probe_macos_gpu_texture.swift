import Cocoa
import CryptoKit
import FlutterMacOS

/// 独立 Flutter/Metal 窗口：使用生产桥，不加载应用插件、数据或实例锁。
/// 编译和运行方式见 docs/macos_gpu_present_performance.md。
private final class TextureProbeHost: NSObject, NSApplicationDelegate {
    private let bundle: Bundle
    private let output: URL
    private let library: URL
    private let libraryHash: String
    private let configuration: [String: Int]
    private var window: NSWindow?
    private var bridge: GpuPresentBridgeMac?
    private var channel: FlutterMethodChannel?
    private var finished = false

    init(bundle: Bundle, output: URL, library: URL, configuration: [String: Int]) throws {
        self.bundle = bundle
        self.output = output
        self.library = library
        self.libraryHash = try Self.hash(library)
        self.configuration = configuration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let project = FlutterDartProject(precompiledDartBundle: bundle)
        project.dartEntrypointArguments = []
        let controller = FlutterViewController(project: project)
        let hostChannel = FlutterMethodChannel(name: "rossi/gpu_texture_probe", binaryMessenger: controller.engine.binaryMessenger)
        hostChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "config": result(self.configuration)
            case "report":
                guard var report = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "bad-report", message: "Expected a report map", details: nil))
                    return
                }
                report["operatingSystem"] = ProcessInfo.processInfo.operatingSystemVersionString
                report["libraryPath"] = self.library.path
                report["librarySHA256"] = self.libraryHash
                let finalHash = try? Self.hash(self.library)
                report["libraryUnchanged"] = finalHash == self.libraryHash
                if finalHash != self.libraryHash {
                    report["ok"] = false
                    report["libraryError"] = "Library changed during measurement"
                }
                result(true)
                self.finish(report)
            default: result(FlutterMethodNotImplemented)
            }
        }
        channel = hostChannel
        bridge = GpuPresentBridgeMac(textureRegistry: controller.engine, binaryMessenger: controller.engine.binaryMessenger)
        let probeWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        probeWindow.title = "Rossi GPU texture acquisition probe"
        probeWindow.contentViewController = controller
        probeWindow.center()
        probeWindow.makeKeyAndOrderFront(nil)
        window = probeWindow
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.finish(["ok": false, "error": "Flutter texture probe timed out"])
        }
    }

    private func finish(_ report: [String: Any]) {
        guard !finished else { return }
        finished = true
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            print("Texture acquisition report: \(output.path)")
            fflush(stdout)
        } catch {
            fputs("Failed to write report: \(error)\n", stderr)
            exit(2)
        }
        // 只退出本探针进程，给 Dart 报告调用的应答留出一次主线程调度。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(report["ok"] as? Bool == true ? 0 : 1)
        }
    }

    private static func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}

@main
private enum TextureProbeMain {
    static func main() throws {
        var options: [String: String] = [:]
        var index = 1
        let args = CommandLine.arguments
        while index < args.count {
            guard args[index].hasPrefix("--"), index + 1 < args.count else {
                fatalError("Expected --option value pairs")
            }
            options[args[index]] = args[index + 1]
            index += 2
        }
        guard let bundlePath = options["--assets-bundle"], let bundle = Bundle(path: bundlePath),
              let outputPath = options["--output"], let libraryPath = options["--library"] else {
            fatalError("Required: --assets-bundle path --library path --output path")
        }
        func size(_ name: String, fallback: String) -> (Int, Int) {
            let parts = (options[name] ?? fallback).split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2, parts.allSatisfy({ $0 > 0 && $0 <= 16384 }) else {
                fatalError("Invalid \(name) size")
            }
            return (parts[0], parts[1])
        }
        let source = size("--source-size", fallback: "4096x3072")
        let target = size("--target", fallback: "1024x768")
        let samples = Int(options["--warm"] ?? "16") ?? 0
        guard samples > 0 && samples <= 1000 else { fatalError("Invalid --warm") }
        setenv("ROSSI_GPU_PRESENT_DYLIB", libraryPath, 1)
        let host = try TextureProbeHost(
            bundle: bundle, output: URL(fileURLWithPath: outputPath),
            library: URL(fileURLWithPath: libraryPath),
            configuration: ["sourceWidth": source.0, "sourceHeight": source.1,
                            "width": target.0, "height": target.1, "samples": samples]
        )
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = host
        withExtendedLifetime(host) { app.run() }
    }
}
