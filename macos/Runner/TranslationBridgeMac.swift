//
//  TranslationBridgeMac.swift
//  Runner
//
//  Apple 系统翻译（`Translation` 框架）的 Flutter 桥：`rossi/apple_translation`。
//
//  为什么在 Swift 侧而不是 Rust：这个框架只有 Swift / ObjC 绑定，从 Rust 调它要么自己包
//  ObjC 桥要么引 `objc2`；本仓在 Apple 侧已有同形态先例（`com.breeze.macos/activity`、
//  `GpuPresentBridgeMac`）。
//
//  API 形状是**从 SDK 的 swiftinterface 现读并用探针验过**的（`.local/apple-probe/`）：
//   - `LanguageAvailability.status(from:to:)` → installed / supported / unsupported
//   - `TranslationSession` 唯一的公开构造器是 `init(installedSource:target:)`（macOS 26+），
//     **名字本身就要求语言包已装**；SDK 里没有任何下载入口（`canRequestDownloads` 在本机实测
//     为 false），所以「没装」只能回状态让 Dart 侧引导用户去系统设置，别在这儿试。
//   - 整批一次 `translations(from:)`：漫画一页 15 块，逐条建会话会把 300 ms 变成几秒。
//
import Cocoa
import FlutterMacOS
import Translation

class TranslationBridgeMac: NSObject {
    static let channelName = "rossi/apple_translation"

    override init() {
        super.init()
    }

    func install(on messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: TranslationBridgeMac.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let source = (args["source"] as? String) ?? "ja"
        let target = (args["target"] as? String) ?? "zh-Hans"
        switch call.method {
        case "status":
            status(source: source, target: target, result: result)
        case "translate":
            guard let texts = args["texts"] as? [String] else {
                result(FlutterError(code: "args", message: "translate 需要 texts: [String]", details: nil))
                return
            }
            translate(source: source, target: target, texts: texts, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 语言对状态。**非 macOS 15 一律 `unavailable`**，不要回 `unsupported` ——
    /// 后者意思是「系统认识这个语言对但翻不了」，会让人去翻设置里根本不存在的开关。
    private func status(source: String, target: String, result: @escaping FlutterResult) {
        guard #available(macOS 15.0, *) else {
            reply(["status": "unavailable"], result)
            return
        }
        let ja = Locale.Language(identifier: source)
        let zh = Locale.Language(identifier: target)
        Task {
            let s = await LanguageAvailability().status(from: ja, to: zh)
            let name: String
            switch s {
            case .installed: name = "installed"
            case .supported: name = "supported"
            case .unsupported: name = "unsupported"
            @unknown default: name = "unsupported"
            }
            reply(["status": name], result)
        }
    }

    private func translate(source: String, target: String, texts: [String], result: @escaping FlutterResult) {
        // macOS 26 才有 `init(installedSource:target:)`；更早的系统上这条路根本不存在。
        guard #available(macOS 26.0, *) else {
            result(FlutterError(code: "unavailable", message: "系统翻译需要 macOS 26 及以上（当前系统没有这个 API）", details: nil))
            return
        }
        let src = Locale.Language(identifier: source)
        let dst = Locale.Language(identifier: target)
        let session = TranslationSession(installedSource: src, target: dst)
        Task {
            do {
                let responses = try await session.translations(
                    from: texts.map { TranslationSession.Request(sourceText: $0) }
                )
                // 条数必须等长：Dart 侧按块下标回填，少一条就整页串行（那边也有硬校验，两边都要有）。
                reply(["texts": responses.map { $0.targetText }], result)
            } catch {
                result(FlutterError(code: "translate", message: "系统翻译失败：\(error)", details: nil))
            }
        }
    }

    /// `Task` 里的回调不在主线程，而 Flutter channel 的 result 必须在主线程回。
    private func reply(_ payload: [String: Any], _ result: @escaping FlutterResult) {
        DispatchQueue.main.async { result(payload) }
    }
}
