import Foundation

/// `MLModel.compileModel(at:)` 产物的缓存：放在**模型旁边**的 `.coreml_compiled/`。
///
/// 为什么要自己管这两件事：
/// - 以前每次 `loadModel` 都重新编译一遍，冷启动必付一次几百毫秒到几秒；
/// - 编译产物默认落在系统临时目录，而 macOS 每天清临时目录 —— 缓存活不过一次清理，
///   清不掉时反而在 `$TMPDIR` 里堆一堆孤儿 `.mlmodelc`。
///
/// 缓存键是「模型名 + 字节数 + 源文件 mtime」：换权重必然改这两个数，所以不必为
/// 几百 MB 的文件算哈希；同一模型的旧键在装新产物时一并清掉。
enum CompiledModelCache {
    private static let dirName = ".coreml_compiled"

    /// 该模型当前权重对应的缓存目录（不保证存在）。
    static func cachedURL(for source: URL) -> URL {
        return cacheRoot(for: source)
            .appendingPathComponent("\(stem(of: source))__\(signature(of: source)).mlmodelc")
    }

    /// 权重指纹 = 「字节总数_包目录 mtime」。
    ///
    /// `.mlpackage` 是个目录包，只看包目录自己会漏掉「只换了里面的 weight.bin」这种
    /// 情况 —— 那会**静默用旧编译产物**，所以目录要按包内文件的总字节数算（一个包总共
    /// 三五个文件，遍历可忽略）。口径与 OCR 那侧一致：拿长度当版本代理，不算哈希。
    private static func signature(of source: URL) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let size: Int
        if fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue {
            size = (fm.enumerator(at: source, includingPropertiesForKeys: [.fileSizeKey])?
                .compactMap { url in
                    guard let url = url as? URL else { return nil }
                    return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                }
                .reduce(0) { $0 + ($1 ?? 0) }) ?? 0
        } else {
            size = ((try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int) ?? 0
        }
        let mtime = Int(
            (try? source.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(size)_\(mtime)"
    }

    /// 编译产物是否像一份能用完的 `.mlmodelc`（非空目录）。
    ///
    /// 只做粗判：真不灵由调用方 `MLModel(contentsOf:)` 抛错后再重编译兜底。
    static func isUsable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        return (entries?.isEmpty == false)
    }

    /// 把 `compileModel` 的临时产物搬进缓存，并清掉同一模型的旧键。返回最终路径。
    static func install(compiled: URL, for source: URL) throws -> URL {
        let fm = FileManager.default
        let destination = cachedURL(for: source)
        let root = destination.deletingLastPathComponent()
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.moveItem(at: compiled, to: destination)
        prune(in: root, stalePrefix: "\(stem(of: source))__", keeping: destination)
        return destination
    }

    private static func cacheRoot(for source: URL) -> URL {
        source.deletingLastPathComponent().appendingPathComponent(dirName)
    }

    /// `.mlpackage` / `.mlmodel` 都取去扩展名后的名字，避免不同模型撞同一个前缀。
    private static func stem(of source: URL) -> String {
        source.deletingPathExtension().lastPathComponent
    }

    /// 只清「同一个模型」的旧键 —— 前缀带 `__` 分隔符，免得名字互为前缀的两个模型互相误删。
    private static func prune(in dir: URL, stalePrefix: String, keeping keep: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for entry in entries
        where entry.lastPathComponent != keep.lastPathComponent
            && entry.pathExtension == "mlmodelc"
            && entry.deletingPathExtension().lastPathComponent.hasPrefix(stalePrefix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
