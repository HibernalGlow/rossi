import Accelerate
import CoreML

class MultiArrayModel: ImageProcessingModel {
    private let mlmodel: MLModel
    private let inputName: String
    private let outputName: String
    private let shape: [NSNumber]
    private let blockSize: Int
    private let shrinkSize: Int
    private let scale: Int
    private let outputCrop: Int
    private let inputBias: Float

    required init(model: MLModel, config: [String: Any]) {
        self.mlmodel = model
        self.inputName = (config["inputName"] as? String) ?? "input"
        self.outputName = (config["outputName"] as? String) ?? "output"
        self.blockSize = (config["blockSize"] as? Int) ?? 256
        self.shrinkSize = (config["shrinkSize"] as? Int) ?? 0
        self.scale = (config["scale"] as? Int) ?? 2
        self.outputCrop = (config["outputCrop"] as? Int) ?? 0
        self.inputBias = (config["inputBias"] as? NSNumber)?.floatValue ?? 0.00196078411
        if let customShape = config["shape"] as? [Int] {
            self.shape = customShape.map { NSNumber(value: $0) }
        } else {
            self.shape = [1, 3, NSNumber(value: blockSize), NSNumber(value: blockSize)]
        }
    }

    func process(_ image: CGImage) async -> CGImage? {
        let inputType = mlmodel.modelDescription.inputDescriptionsByName[inputName]?
            .multiArrayConstraint?.dataType ?? .float32
        guard inputType == .float32 || inputType == .float16 else { return nil }
        let width = image.width
        let height = image.height
        let channels = 4
        let contentBlockSize = self.blockSize - shrinkSize * 2
        let outScale = scale

        // Pad image dimensions to multiples of the content block so that tiles
        // never overlap in the output. The extra area is filled by reflecting
        // the source image, matching Real-CUGAN's reference tiling behaviour.
        let paddedWidth = ((width + contentBlockSize - 1) / contentBlockSize) * contentBlockSize
        let paddedHeight = ((height + contentBlockSize - 1) / contentBlockSize) * contentBlockSize

        let outWidth = paddedWidth * outScale
        let outHeight = paddedHeight * outScale
        let outBlockSize = contentBlockSize * outScale

        // set up pool of buffers
        // 输入准备与预测只需双缓冲，不按 CPU 核数预分配。
        let poolSize = 2
        let blockAndShrink = contentBlockSize + 2 * shrinkSize
        var bufferPool: [MLMultiArray] = (0..<poolSize).compactMap { _ in
            try? MLMultiArray(shape: shape, dataType: inputType)
        }
        guard bufferPool.count == poolSize else { return nil }
        let bufferSemaphore = DispatchSemaphore(value: poolSize)
        let bufferPoolLock = NSLock()

        func getBuffer() -> MLMultiArray {
            bufferSemaphore.wait()
            bufferPoolLock.lock()
            let buffer = bufferPool.removeLast()
            bufferPoolLock.unlock()
            return buffer
        }

        func returnBuffer(_ buffer: MLMultiArray) {
            bufferPoolLock.lock()
            bufferPool.append(buffer)
            bufferPoolLock.unlock()
            bufferSemaphore.signal()
        }

        // expand image by the shrink size using reflection
        let expwidth = paddedWidth + 2 * shrinkSize
        let expheight = paddedHeight + 2 * shrinkSize
        let expanded = image.expandReflect(
            shrinkSize: shrinkSize,
            paddedWidth: paddedWidth,
            paddedHeight: paddedHeight,
            bias: inputBias
        )

        // calculate image block rects over the padded canvas
        let rects = calculateRects(width: paddedWidth, height: paddedHeight, blockSize: contentBlockSize)

        // feed expanded image data into blocks of MLMultiArrays
        let multiArrayStream = AsyncStream<(Int, MLMultiArray)> { continuation in

            Task.detached {
                for (i, rect) in rects.enumerated() {
                    let x = Int(rect.origin.x)
                    let y = Int(rect.origin.y)
                    let multi = getBuffer()
                    let floatPtr = multi.dataPointer.assumingMemoryBound(to: Float32.self)
                    let halfPtr = multi.dataPointer.assumingMemoryBound(to: Float16.self)
                    let inChannelStride = multi.strides[1].intValue
                    let inRowStride = multi.strides[2].intValue
                    for yExp in y..<(y + blockAndShrink) {
                        guard yExp >= 0 else { continue }
                        let inY = yExp - y
                        let srcYBase = yExp * expwidth
                        for xExp in x..<(x + blockAndShrink) {
                            guard xExp >= 0 else { continue }
                            let inX = xExp - x
                            let base = inY * inRowStride + inX
                            let srcIdx = srcYBase + xExp
                            for channel in 0..<3 {
                                let value = expanded[srcIdx + expwidth * expheight * channel]
                                let target = base + inChannelStride * channel
                                if inputType == .float16 {
                                    halfPtr[target] = Float16(value)
                                } else {
                                    floatPtr[target] = Float32(value)
                                }
                            }
                        }
                    }
                    continuation.yield((i, multi))
                }
                continuation.finish()
            }
        }

        // 限制尚未拼接的预测输出，4× 每块很大，不能无限积压张量。
        let predictionSlots = PredictionSlots()

        // feed image block arrays into the model
        let predictionStream = AsyncStream<(Int, MLMultiArray?)> { [inputName, outputName] continuation in
            Task.detached {
                for await (i, multi) in multiArrayStream {
                    await predictionSlots.acquire()
                    let prediction = try? self.mlmodel.prediction(inputName: inputName, outputName: outputName, input: multi)
                    // 失败不能把输入张量冒充输出，否则 2x/4x 拼接会越界。
                    continuation.yield((i, prediction))
                    returnBuffer(multi)
                }
                continuation.finish()
            }
        }

        // 顺序消费预测，直接逐行写入 RGBA；避免整块复制、每块/通道分配
        // 多个临时数组，以及任务组并发修改 Swift Array 的数据竞争。
        var imgData = [UInt8](repeating: 0, count: outWidth * outHeight * channels)
        var multiplied = [Float32](repeating: 0, count: outBlockSize)
        var clipped = [Float32](repeating: 0, count: outBlockSize)
        var multiplier: Float32 = 255
        var minimum: Float32 = 0
        var maximum: Float32 = 255
        var failed = false
        for await (i, output) in predictionStream {
            guard let prediction = output,
                  (prediction.dataType == .float32 || prediction.dataType == .float16),
                  prediction.shape.count == 4,
                  prediction.shape[1].intValue >= 3,
                  prediction.shape[2].intValue >= outBlockSize + 2 * outputCrop,
                  prediction.shape[3].intValue >= outBlockSize + 2 * outputCrop else {
                failed = true
                await predictionSlots.release()
                continue
            }
            let rect = rects[i]
            let originX = Int(rect.origin.x) * outScale
            let originY = Int(rect.origin.y) * outScale
            let data = prediction.dataPointer.assumingMemoryBound(to: Float32.self)
            let halfData = prediction.dataPointer.assumingMemoryBound(to: Float16.self)
            let channelStride = prediction.strides[1].intValue
            let rowStride = prediction.strides[2].intValue
            let pixelStride = prediction.strides[3].intValue
            imgData.withUnsafeMutableBufferPointer { destination in
                for channel in 0..<3 {
                    for y in 0..<outBlockSize {
                        let sourceOffset = channel * channelStride + (y + outputCrop) * rowStride + outputCrop * pixelStride
                        let source = data.advanced(by: sourceOffset)
                        let target = destination.baseAddress!.advanced(by:
                            ((originY + y) * outWidth + originX) * channels + channel)
                        if prediction.dataType == .float16 {
                            for x in 0..<outBlockSize {
                                multiplied[x] = Float32(halfData[sourceOffset + x * pixelStride]) * multiplier
                            }
                        } else {
                            vDSP_vsmul(source, vDSP_Stride(pixelStride), &multiplier,
                                       &multiplied, 1, vDSP_Length(outBlockSize))
                        }
                        vDSP_vclip(&multiplied, 1, &minimum, &maximum,
                                   &clipped, 1, vDSP_Length(outBlockSize))
                        vDSP_vfixu8(&clipped, 1, target, vDSP_Stride(channels),
                                    vDSP_Length(outBlockSize))
                    }
                }
            }
            await predictionSlots.release()
        }
        if failed { return nil }

        // create final cgimage from imgData buffer
        guard
            let cfbuffer = CFDataCreate(nil, &imgData, outWidth * outHeight * channels),
            let dataProvider = CGDataProvider(data: cfbuffer)
        else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue // skip alpha
        guard let fullImage = CGImage(
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * channels,
            bytesPerRow: outWidth * channels,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: CGColorRenderingIntent.defaultIntent
        ) else {
            return nil
        }

        // Crop back to the original image dimensions (padded area was only added
        // to make the tile grid fit exactly).
        let cropRect = CGRect(
            x: 0,
            y: 0,
            width: width * outScale,
            height: height * outScale
        )
        return fullImage.cropping(to: cropRect)
    }

    // calculate the rects for the image blocks
    private func calculateRects(width: Int, height: Int, blockSize: Int) -> [CGRect] {
        var rects: [CGRect] = []
        let numW = width / blockSize
        let numH = height / blockSize

        // With padded dimensions this always produces a regular non-overlapping grid.
        for i in 0..<numW {
            for j in 0..<numH {
                rects.append(CGRect(x: i * blockSize, y: j * blockSize, width: blockSize, height: blockSize))
            }
        }
        return rects
    }
}

private class MLInput: MLFeatureProvider {
    var input: MLMultiArray
    var featureNames: Set<String>

    func featureValue(for featureName: String) -> MLFeatureValue? {
        MLFeatureValue(multiArray: input)
    }

    init(name: String, input: MLMultiArray) {
        self.input = input
        self.featureNames = [name]
    }
}

private extension MLModel {
    func prediction(inputName: String, outputName: String, input: MLMultiArray) throws -> MLMultiArray? {
        let inputProvider = MLInput(name: inputName, input: input)
        let outFeatures = try self.prediction(from: inputProvider)
        return outFeatures.featureValue(for: outputName)?.multiArrayValue
    }
}

private extension CGImage {
    // Reflect-pad the source image to the requested padded size and then add
    // a surrounding shrink-size border, also by reflection. This matches the
    // "reflect" padding used by Real-CUGAN / waifu2x style models.
    func expandReflect(shrinkSize: Int, paddedWidth: Int, paddedHeight: Int, bias: Float) -> [Float] {

        let exwidth = paddedWidth + 2 * shrinkSize
        let exheight = paddedHeight + 2 * shrinkSize

        // extract rgba pixel data
        var u8Array = [UInt8](repeating: 0, count: width * height * 4)
        u8Array.withUnsafeMutableBytes { u8Pointer in
            let context = CGContext(
                data: u8Pointer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(
                self,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
            )
        }

        var arr = [Float](repeating: 0, count: 3 * exwidth * exheight)

        // 归一化只需 256 个可能值，避免为三个通道分配多份整图浮点数组。
        let values = (0...255).map { UInt8($0) }
        var floats = [Float](repeating: 0, count: 256)
        var normalized = [Float](repeating: 0, count: 256)
        var scale: Float = 1 / 255
        var eta = bias
        vDSP_vfltu8(values, 1, &floats, 1, 256)
        vDSP_vsmsa(&floats, 1, &scale, &eta, &normalized, 1, 256)

        func reflectIndex(_ index: Int, _ length: Int) -> Int {
            if length <= 1 { return 0 }
            var index = index
            while true {
                if index < 0 {
                    index = -index
                }
                if index < length {
                    return index
                }
                index = 2 * (length - 1) - index
            }
        }

        let reflectedX = (0..<exwidth).map { reflectIndex($0 - shrinkSize, width) }
        let reflectedY = (0..<exheight).map { reflectIndex($0 - shrinkSize, height) }
        for channel in 0..<3 {
            let base = channel * exwidth * exheight
            for y in 0..<exheight {
                let srcY = reflectedY[y]
                let srcRow = srcY * width
                let dstRowStart = base + y * exwidth
                for x in 0..<exwidth {
                    let srcX = reflectedX[x]
                    arr[dstRowStart + x] = normalized[Int(u8Array[(srcRow + srcX) * 4 + channel])]
                }
            }
        }

        return arr
    }
}

/// 推理可领先拼接最多两块，挂起生产任务而不阻塞 Swift 协作线程。
private actor PredictionSlots {
    private var available = 2
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func release() {
        if waiting.isEmpty {
            available += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
