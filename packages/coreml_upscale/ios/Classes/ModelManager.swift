import Foundation
import CoreML

enum CoreMLUpscaleError: Error, CustomStringConvertible, LocalizedError {
    case invalidInput(String)
    case modelLoadFailed(String)
    case processingFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .modelLoadFailed(let message):
            return "Model load failed: \(message)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .writeFailed(let message):
            return "Write failed: \(message)"
        }
    }

    /// 插件把错误经 `localizedDescription` 透成 FlutterError 给 Dart。
    /// 只 conform `CustomStringConvertible` 的话，桥成 NSError 后这条消息会被丢光，
    /// Dart 侧只剩「The operation couldn’t be completed. (…) error 2.」。
    var errorDescription: String? { description }
}

actor ModelManager {
    static let shared = ModelManager()

    private var imageModelCache: [String: ImageProcessingModel] = [:]

    func loadModel(fromPath path: String, type: String, config: [String: Any]) async throws -> ImageProcessingModel? {
        if let cached = imageModelCache[path] {
            return cached
        }

        let fileURL = URL(fileURLWithPath: path)
        let cached = CompiledModelCache.cachedURL(for: fileURL)
        var compiledUrl = cached
        let loadedFromCache = CompiledModelCache.isUsable(cached)
        if !loadedFromCache {
            compiledUrl = try CompiledModelCache.install(
                compiled: try await Self.compileModel(at: fileURL), for: fileURL)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let mlModel: MLModel
        do {
            mlModel = try MLModel(contentsOf: compiledUrl, configuration: configuration)
        } catch {
            // 「缓存里那份读不出来」是可能的（上次编译被中断，只剩个空壳）：那种情况
            // 重编译一次。本来就现编译出来的还失败，则别试第二遍。
            // 用标志位而不是比 URL：`appendingPathComponent` 在目录已存在时会带尾斜杠，
            // 两个指向同一个目录的 URL 可以 `==` 为 false。
            guard loadedFromCache else { throw error }
            compiledUrl = try CompiledModelCache.install(
                compiled: try await Self.compileModel(at: fileURL), for: fileURL)
            mlModel = try MLModel(contentsOf: compiledUrl, configuration: configuration)
        }

        let model: ImageProcessingModel?
        switch type.lowercased() {
        case "multiarray":
            model = MultiArrayModel(model: mlModel, config: config)
        case "image":
            model = ImageModel(model: mlModel, config: config)
        default:
            throw CoreMLUpscaleError.modelLoadFailed("Unsupported model type: \(type)")
        }

        if let model {
            imageModelCache[path] = model
        }
        return model
    }

    /// 编译模型：macOS 13 / iOS 16 起走真正的 async 重载，12.x 只有同步版可用。
    ///
    /// 不能直接写 `try await MLModel.compileModel(at:)`：在以 12.0 为下限的目标里
    /// 编译器会解析到**已废弃的同步重载**，await 成了空操作、还报一条
    /// 「no 'async' operations occur within 'await'」；反过来只写 `try`（不 await），
    /// 下限一抬到 13.0 又会因为解析到 async 重载而编译不过 —— 所以这里显式分叉。
    private static func compileModel(at url: URL) async throws -> URL {
        if #available(macOS 13.0, iOS 16.0, *) {
            return try await MLModel.compileModel(at: url)
        }
        let sync: (URL) throws -> URL = MLModel.compileModel(at:)
        return try sync(url)
    }

    func clearCache() {
        imageModelCache.removeAll()
    }
}
