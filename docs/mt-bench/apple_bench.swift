// Apple 系统翻译在**基准语料**上的跑批：读 corpus.json，逐条送进同一个会话，出 JSONL。
//
// 为什么要单独一个跑批版而不是复用 probe4：probe4 的 16 条是我手挑的，
// 与 llama.cpp 那边用的 33 条（含 3 条真实 OCR 残缺行）不是同一份输入 ——
// 不同输入上的分数不能放在一起排名。这一版读同一个文件，保证可比。
//
// 跑法：swiftc -O probe_bench.swift -o probe_bench && ./probe_bench <corpus.json> <out.jsonl>
import Foundation
import Translation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法：probe_bench <corpus.json> <out.jsonl>\n".data(using: .utf8)!)
    exit(2)
}
let corpusURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

struct Item: Decodable { let id: Int; let kind: String; let ja: String }

guard let raw = try? Data(contentsOf: corpusURL),
      let items = try? JSONDecoder().decode([Item].self, from: raw) else {
    print("读不了语料：\(args[1])")
    exit(1)
}

let availability = LanguageAvailability()
let ja = Locale.Language(identifier: "ja")
let zh = Locale.Language(identifier: "zh-Hans")

func probe() async {
    let st = await availability.status(from: ja, to: zh)
    guard st == .installed else {
        print("语言对没装（\(st)），这一档测不了")
        exit(1)
    }
    let session = TranslationSession(installedSource: ja, target: zh)
    var lines: [String] = []
    // 先整批一次（app 的形态就是一页一次），再逐条计时 —— 两者都要：
    // 整批给「这页要等多久」，逐条给「单块的尾延迟」。
    let batchStart = Date()
    let batch = try? await session.translations(
        from: items.map { TranslationSession.Request(sourceText: $0.ja) })
    let batchMs = Int(Date().timeIntervalSince(batchStart) * 1000)
    print("整批 \(items.count) 条：\(batchMs) ms")
    if let batch {
        for (i, item) in items.enumerated() where i < batch.count {
            let o = batch[i].targetText.replacingOccurrences(of: "\n", with: " ")
            lines.append("{\"system\":\"apple\",\"id\":\(item.id),\"kind\":\"\(item.kind)\",\"ja\":\"\(item.ja)\",\"out\":\"\(o)\",\"ms\":\(batchMs / max(1, items.count)),\"mode\":\"batch\"}")
        }
    }
    // 逐条：含会话预热后的真实单条延迟
    for item in items {
        let t0 = Date()
        let r = try? await session.translations(from: [TranslationSession.Request(sourceText: item.ja)])
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        let o = (r?.first?.targetText ?? "<失败>").replacingOccurrences(of: "\n", with: " ")
        lines.append("{\"system\":\"apple-single\",\"id\":\(item.id),\"kind\":\"\(item.kind)\",\"ja\":\"\(item.ja)\",\"out\":\"\(o)\",\"ms\":\(ms),\"mode\":\"single\"}")
    }
    let joined = lines.joined(separator: "\n") + "\n"
    try? joined.write(to: outURL, atomically: true, encoding: .utf8)
    print("写出 \(lines.count) 行 → \(outURL.path)")
    let singles = lines.compactMap { l -> Int? in
        guard l.contains("\"apple-single\"") else { return nil }
        if let r = l.range(of: "\"ms\":"), let n = Int(l[r.upperBound...].prefix(while: { $0.isNumber })) { return n }
        return nil
    }
    if !singles.isEmpty {
        let sorted = singles.sorted()
        print("单条延迟：中位 \(sorted[sorted.count / 2]) ms，最慢 \(sorted.last ?? 0) ms")
    }
}

await probe()
