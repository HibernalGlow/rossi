// CompiledModelCache 的门禁 —— 缓存键与淘汰范围。这是整块改动里最容易「静默错」的地方：
// 键算重了就会拿旧的编译产物去跑新权重，画面上完全看不出来。
//
// 这里没有 Swift 测试框架，跑法是直接编成可执行文件（断言全过才返回 0）：
//   cd packages/coreml_upscale/macos/Classes && \
//     xcrun -sdk macosx swiftc -parse-as-library -o /tmp/cmc_harness \
//       ../../test/CompiledModelCacheHarness.swift CompiledModelCache.swift \
//     && /tmp/cmc_harness
//
// 只依赖 Foundation；ios/ 那份 CompiledModelCache.swift 与 macos/ 逐字节相同，验一份等于验两份。

import Foundation

@main
struct CompiledModelCacheHarness {
    static func main() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("cmc_harness_\(UUID().uuidString)")
        try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 一个假的 `.mlpackage`：目录包，权重在里面那个文件里。
        let modelDir = tmp.appendingPathComponent("super_resolution/coreml_models/MacOS-iOS")
        try! fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let model = modelDir.appendingPathComponent("RealCUGAN_2x.mlpackage")
        try! fm.createDirectory(at: model, withIntermediateDirectories: true)
        let weight = model.appendingPathComponent("weight.bin")

        section("1) 缓存键")
        try! "w".write(to: weight, atomically: true, encoding: .utf8)
        let first = CompiledModelCache.cachedURL(for: model)
        ok(first.lastPathComponent.hasPrefix("RealCUGAN_2x__"),
           "键以「模型名__」开头：\(first.lastPathComponent)")
        ok(CompiledModelCache.cachedURL(for: model) == first, "同一份权重，两次算出的键相同")
        // 只换包里面的权重：包目录自己的字节数与 mtime 都不动，键必须照样变。
        try! "a-completely-different-weight-tensor".write(to: weight, atomically: true,
                                                          encoding: .utf8)
        ok(CompiledModelCache.cachedURL(for: model) != first,
           "换了包里面的权重 → 键必须变，否则会拿旧编译产物跑新权重")

        section("2) isUsable")
        ok(!CompiledModelCache.isUsable(first), "不存在 → 不可用")
        let current = CompiledModelCache.cachedURL(for: model)
        try! fm.createDirectory(at: current, withIntermediateDirectories: true)
        ok(!CompiledModelCache.isUsable(current), "空目录 → 不可用（上次编译被中断）")
        try! "m".write(to: current.appendingPathComponent("core.mlmodel"), atomically: true,
                       encoding: .utf8)
        ok(CompiledModelCache.isUsable(current), "有内容 → 可用")

        section("3) install 与淘汰范围")
        let root = current.deletingLastPathComponent()
        let otherKey = seed(root.appendingPathComponent("waifu2x_photo__1_1.mlmodelc"))
        let lookalike = seed(root.appendingPathComponent("RealCUGAN_2x_extra__9_9.mlmodelc"))
        let sameModelOld = seed(root.appendingPathComponent("RealCUGAN_2x__123_456.mlmodelc"))
        let fresh = tmp.appendingPathComponent("compilebox/new.mlmodelc")
        try! fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        try! "spec".write(to: fresh.appendingPathComponent("core.mlmodel"), atomically: true,
                          encoding: .utf8)

        let installed = try! CompiledModelCache.install(compiled: fresh, for: model)
        // 比较一律用 `.path`：`appendingPathComponent` 在目录已存在时会带尾斜杠，
        // 两个指向同一个目录的 URL 可以 `==` 为 false（ModelManager 因此用标志位判来源）。
        ok(installed.path == current.path, "装到当前这把键：\(installed.path == current.path)")
        ok(CompiledModelCache.isUsable(installed), "装完即可用")
        ok(!fm.fileExists(atPath: fresh.path), "临时产物被搬走，不在 $TMPDIR 留孤儿")
        ok(!fm.fileExists(atPath: sameModelOld.path), "同模型的旧键被清掉")
        ok(fm.fileExists(atPath: lookalike.path), "名字互为前缀的另一个模型不被误删")
        ok(fm.fileExists(atPath: otherKey.path), "别的模型的缓存不动")
    }

    private static func seed(_ dir: URL) -> URL {
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! "x".write(to: dir.appendingPathComponent("f"), atomically: true, encoding: .utf8)
        return dir
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
