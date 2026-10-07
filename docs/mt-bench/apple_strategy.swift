// Apple 系统翻译的**策略 × 投递方式**对表：快多少、以及**翻出来的还是不是同一句**。
//
// 为什么是策略而不是并发：SDK 在 macOS 26.4 上加了 `TranslationSession.Strategy`
// （`highFidelity` / `lowLatency`），这是官方给的速度档；而本仓的生产桥已经是「一页一次整批」，
// 再谈并发只是换投递方式。两件事都要数，但策略那条可能一下省掉一半。
//
// 三条纪律照本仓一贯口径：
// 1. **交替轮次**：一轮跑完全部组合再进下一轮，取每组合的最小值 —— 机器上有别人的活，
//    单轮绝对数不可信，同一轮内的相对差才可信；
// 2. **译文必须比对**：`lowLatency` 若改了输出，那就不是免费的 —— 成品页缓存指纹必须加一维，
//    否则「同参数不同译文」会静默发生（这条是本 ADR 一路在防的）。
// 3. **先报负载**：打印 `vm.loadavg`。
//
// 跑法：swiftc -O apple_strategy.swift -o apple_strategy && ./apple_strategy <corpus.json> [轮数]

import Foundation
import Translation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("用法：apple_strategy <corpus.json> [轮数]\n".data(using: .utf8)!)
    exit(2)
}
let rounds = args.count >= 3 ? (Int(args[2]) ?? 3) : 3

struct Item: Decodable { let id: Int; let kind: String; let ja: String }
guard let raw = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
      let items = try? JSONDecoder().decode([Item].self, from: raw) else {
    print("读不了语料：\(args[1])")
    exit(1)
}
let texts = items.map(\.ja)
let ja = Locale.Language(identifier: "ja")
let zh = Locale.Language(identifier: "zh-Hans")

func makeSession(_ s: TranslationSession.Strategy) -> TranslationSession {
    TranslationSession(installedSource: ja, target: zh, preferredStrategy: s)
}

/// 整批一次（= 生产桥的形态）。
func oneBatch(_ session: TranslationSession) async -> [String] {
    let r = try? await session.translations(from: texts.map { TranslationSession.Request(sourceText: $0) })
    return (r ?? []).map(\.targetText)
}

/// 逐条并发：一页 15 块各发一次，看框架内部到底给不给并行。
func perLine(_ session: TranslationSession) async -> [String] {
    await withTaskGroup(of: (Int, String).self) { g in
        for (i, t) in texts.enumerated() {
            g.addTask {
                let r = try? await session.translate(t)
                return (i, r?.targetText ?? "")
            }
        }
        var out = [String](repeating: "", count: texts.count)
        for await (i, v) in g { out[i] = v }
        return out
    }
}

/// 分片并发：每片 5 条，片与片并发。介于两种极端之间。
func shards(_ session: TranslationSession, size: Int) async -> [String] {
    await withTaskGroup(of: (Int, [String]).self) { g in
        var base = 0
        var part = 0
        while base < texts.count {
            let slice = Array(texts[base..<min(base + size, texts.count)])
            let b = base
            part += 1
            g.addTask {
                let r = try? await session.translations(from: slice.map { TranslationSession.Request(sourceText: $0) })
                return (b, (r ?? []).map(\.targetText))
            }
            base += size
        }
        var out = [String](repeating: "", count: texts.count)
        for await (b, partOut) in g {
            for (k, v) in partOut.enumerated() where b + k < out.count { out[b + k] = v }
        }
        return out
    }
}

func timed(_ body: () async -> [String]) async -> (Int, [String]) {
    let t = Date()
    let out = await body()
    return (Int(Date().timeIntervalSince(t) * 1000), out)
}

func probe() async {
    let st = await LanguageAvailability().status(from: ja, to: zh)
    guard st == .installed else { print("语言对没装（\(st)）"); exit(1) }

    let combos: [(String, TranslationSession.Strategy, (TranslationSession) async -> [String])] = [
        ("highFidelity·整批", .highFidelity, { await oneBatch($0) }),
        ("lowLatency·整批", .lowLatency, { await oneBatch($0) }),
        ("highFidelity·逐条并发", .highFidelity, { await perLine($0) }),
        ("lowLatency·逐条并发", .lowLatency, { await perLine($0) }),
        ("lowLatency·分片5", .lowLatency, { await shards($0, size: 5) }),
    ]
    var best: [String: Int] = [:]
    var outputs: [String: [String]] = [:]
    for r in 1...rounds {
        for (name, strategy, run) in combos {
            let session = makeSession(strategy)
            let (ms, out) = await timed { await run(session) }
            best[name] = min(best[name] ?? .max, ms)
            if outputs[name] == nil { outputs[name] = out }
            print("轮\(r) \(name)：\(ms) ms")
        }
    }
    print("\n=== 最小值（\(texts.count) 条语料，\(rounds) 轮）===")
    for (name, ms) in best.sorted(by: { $0.value < $1.value }) {
        print("\(name)：\(ms) ms（\(Double(ms) / Double(texts.count)) ms/条）")
    }
    let ref = outputs["highFidelity·整批"] ?? []
    print("\n=== 译文是否与「highFidelity·整批」逐字相同 ===")
    for (name, out) in outputs where name != "highFidelity·整批" {
        let diff = (0..<min(out.count, ref.count)).filter { out[$0] != ref[$0] }
        print("\(name)：\(diff.count)/\(ref.count) 条不同")
        for i in diff.prefix(4) {
            print("   #\(i) 「\(items[i].ja)」**高**：\(ref[i])\n        **\(name)**：\(out[i])")
        }
    }
}

await probe()
