import CoreML
import CoreImage
import Vision

class ImageModel: ImageProcessingModel {
    private let model: MLModel

    required init?(model: MLModel, config: [String: Any]) {
        self.model = model
    }

    func process(_ image: CGImage) async throws -> CGImage {
        let vnModel: VNCoreMLModel
        do {
            vnModel = try VNCoreMLModel(for: model)
        } catch {
            throw CoreMLUpscaleError.processingFailed("Vision 包装 CoreML 模型失败：\(error)")
        }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw CoreMLUpscaleError.processingFailed("Vision 推理失败：\(error)")
        }

        guard let result = request.results?.first as? VNPixelBufferObservation else {
            throw CoreMLUpscaleError.processingFailed("Image 型模型没有产出像素缓冲")
        }

        let output = CIImage(cvImageBuffer: result.pixelBuffer)
        guard let cgImage = output.cgImage else {
            throw CoreMLUpscaleError.processingFailed("Image 型模型的像素缓冲无法转成 CGImage")
        }
        return cgImage
    }
}
