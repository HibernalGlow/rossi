// MultiArrayModel 拼接前布局判据的门禁 —— 这条判据误判的代价是**整批图全红**
// （2026-09-28 线上：RealCUGAN 2× 在 macOS 上逐块报「输出只有 292032 个元素，
// 按 strides 需要 299512，拒绝越界拼接」，一页都出不来），或者反过来放行越界读、
// 把别的内存当像素画进图里。这里把实测数字钉成回归用例。
//
// 这里没有 Swift 测试框架，跑法是直接编成可执行文件（断言全过才返回 0）：
//   cd packages/coreml_upscale/macos/Classes && \
//     xcrun -sdk macosx swiftc -parse-as-library -o /tmp/block_guard_harness \
//       ../../test/MultiArrayBlockGuardHarness.swift \
//       MultiArrayModel.swift ImageProcessingModel.swift ImageModel.swift ModelManager.swift CompiledModelCache.swift \
//     && /tmp/block_guard_harness
//
// ios/ 那份 MultiArrayModel.swift 与 macos/ 逐字节相同，验一份等于验两份。

import CoreML

@main
struct MultiArrayBlockGuardHarness {
    /// 线上 RealCUGAN 2× 的参数：blockSize 192 - 2×shrinkSize 18 = 156 内容块，输出 312。
    static let outBlock = 312
    static let shape = [1, 3, 312, 312]

    static func main() {
        section("1) 线上实测：ANE 输出的行对齐 padding 必须放行")
        // 头文件里 count 的定义就是 shape 乘积（逻辑元素数），这两行是那批日志的数字。
        ok(3 * 312 * 312 == 292032, "count 292032 = 3×312×312，是逻辑元素数")
        ok(2 * 99840 + 311 * 320 + 311 + 1 == 299512, "旧判据按 strides 算出的上界是 299512")
        ok(292032 < 299512, "所以旧的 count 判据必然每块都误杀 —— 这就是那次全线报错的原因")
        // ANE 后端实测：strides 的行步幅 320（312 向上对齐），真实存储 299520 个元素。
        let aneStrides = [299520, 99840, 320, 1]
        ok(rejection(shape: shape, strides: aneStrides, storageBytes: 299520 * 4, bytes: 4) == nil,
           "按真实存储 299520×4 字节判 → 放行")
        // 同一个模型在 cpuOnly 后端没有 padding，count 恰好等于所需元素数。
        let denseStrides = [292032, 97344, 312, 1]
        ok(rejection(shape: shape, strides: denseStrides, storageBytes: 292032 * 4, bytes: 4) == nil,
           "CPU 后端：无 padding、count == 所需 → 放行")

        section("2) 容量判据的边界：刚好够 / 差一个元素")
        ok(rejection(shape: shape, strides: denseStrides, storageBytes: 292032 * 4, bytes: 4) == nil,
           "存储刚好等于所需 → 放行")
        let shortStorage = rejection(shape: shape, strides: denseStrides,
                                     storageBytes: 292031 * 4, bytes: 4)
        ok(shortStorage != nil, "少一个元素 → 拒绝（\(shortStorage ?? "放行了！")）")
        let wrongElementSize = rejection(shape: shape, strides: denseStrides,
                                         storageBytes: 292032 * 2, bytes: 4)
        ok(wrongElementSize != nil,
           "float32 输出按 float16 的字节数算 → 拒绝（\(wrongElementSize ?? "放行了！")）")
        ok(rejection(shape: shape, strides: denseStrides, storageBytes: nil, bytes: 4) == nil,
           "老系统（macOS 12.3 / iOS 15.4 以下）拿不到存储大小 → 合法布局仍放行")

        section("3) 错布局与错形状必须拒绝")
        let interleaved = rejection(shape: shape, strides: [292032, 1, 936, 3],
                                    storageBytes: 292032 * 4, bytes: 4)
        ok(interleaved?.contains("不是 NCHW 行主序") == true,
           "channel-last 视图 → 拒绝（\(interleaved ?? "放行了！")）")
        let nonPositive = rejection(shape: shape, strides: [292032, 0, 312, 1],
                                    storageBytes: 292032 * 4, bytes: 4)
        ok(nonPositive?.contains("不是 NCHW 行主序") == true,
           "非正 strides → 拒绝（\(nonPositive ?? "放行了！")）")
        let tooSmall = rejection(shape: shape, strides: denseStrides,
                                 storageBytes: 292032 * 4, bytes: 4, outBlock: 320)
        ok(tooSmall?.contains("拼接要求") == true, "输出比要求小（312 < 320）→ 拒绝（\(tooSmall ?? "放行了！")）")
        ok(rejection(shape: [1, 3, 312], strides: [292032, 97344, 312],
                     storageBytes: 292032 * 4, bytes: 4) != nil, "不是 4 维 → 拒绝")
        ok(rejection(shape: [1, 2, 312, 312], strides: [194688, 97344, 312, 1],
                     storageBytes: 194688 * 4, bytes: 4) != nil, "通道不足 3 → 拒绝")
        let cropped = rejection(shape: shape, strides: denseStrides, storageBytes: 292032 * 4,
                                bytes: 4, crop: 64)
        ok(cropped != nil, "要求 312+2×64 宽（ESRGAN 那类带上下文输出）而输出只有 312 → 拒绝（\(cropped ?? "放行了！")）")

        section("4) 真张量对照（macOS 15+ 能按 strides 构造 padding 张量）")
        if #available(macOS 15.0, *) {
            do {
                let array = try MLMultiArray(shape: shape, dataType: .float32, strides: aneStrides)
                ok(array.strides.map { $0.intValue } == aneStrides, "初始器如实保留 padding strides")
                ok(array.count == 292032, "真张量的 count 仍是逻辑元素数 292032")
                var bytes = 0
                array.withUnsafeBytes { bytes = $0.count }
                ok(bytes >= 299512 * 4,
                   "真张量的存储 \(bytes) 字节 ≥ strides 需要的 \(299512 * 4)")
                ok(rejection(shape: array.shape.map { $0.intValue },
                             strides: array.strides.map { $0.intValue },
                             storageBytes: bytes, bytes: 4) == nil,
                   "真张量过判据 → 放行")
            } catch {
                ok(false, "构造 padding 张量失败：\(error)")
            }
        } else {
            print("  skip- 本机低于 macOS 15，构造不了 padding 张量（这一节不参与判定）")
        }
    }

    private static func rejection(
        shape: [Int],
        strides: [Int],
        storageBytes: Int?,
        bytes: Int,
        outBlock: Int = outBlock,
        crop: Int = 0
    ) -> String? {
        MultiArrayModel.blockLayoutRejection(
            shape: shape,
            strides: strides,
            storageBytes: storageBytes,
            bytesPerElement: bytes,
            outBlockSize: outBlock,
            outputCrop: crop)
    }

    private static func section(_ title: String) { print("\n\(title)") }

    private static func ok(_ cond: Bool, _ msg: String) {
        if cond {
            print("  ok  - \(msg)")
        } else {
            FileHandle.standardError.write(Data("  FAIL- \(msg)\n".utf8))
            exit(1)
        }
    }
}
