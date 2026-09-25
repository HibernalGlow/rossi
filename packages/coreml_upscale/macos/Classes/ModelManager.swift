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
        let compiledUrl = try await MLModel.compileModel(at: fileURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let mlModel = try MLModel(contentsOf: compiledUrl, configuration: configuration)

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

    func clearCache() {
        imageModelCache.removeAll()
    }
}
