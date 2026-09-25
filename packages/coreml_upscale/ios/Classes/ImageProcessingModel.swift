import CoreML

protocol ImageProcessingModel {
    init?(model: MLModel, config: [String: Any])

    /// 失败必须**说得出是哪一块、为什么**：返回 nil 只能让上层报「没有输出」，
    /// 用户看到的就是一句废话，坏块问题永远查不下去。
    func process(_ image: CGImage) async throws -> CGImage
}
