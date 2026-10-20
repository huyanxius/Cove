/// `git diff` 输出的一行。行号跟着 hunk 头走：删除行只有旧行号，新增行只有新行号。
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable {
        /// `diff --git`、`index`、`---`/`+++`、`\ No newline…` 这类说明性的行。
        case meta
        case hunk
        case added
        case removed
        case context
    }

    public let kind: Kind
    /// 去掉首列 `+`/`-`/空格之后的内容；meta 和 hunk 行保留原文。
    public let text: String
    public let oldLine: Int?
    public let newLine: Int?
}

public enum UnifiedDiff {
    public static func parse(_ text: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var old = 0
        var new = 0
        var inHunk = false

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                (old, new) = hunkStarts(line)
                inHunk = true
                result.append(DiffLine(kind: .hunk, text: line, oldLine: nil, newLine: nil))
            } else if !inHunk || line.hasPrefix("\\") || line.hasPrefix("diff --git") {
                if line.hasPrefix("diff --git") { inHunk = false }
                if line.isEmpty && result.isEmpty { continue }
                result.append(DiffLine(kind: .meta, text: line, oldLine: nil, newLine: nil))
            } else if line.hasPrefix("+") {
                result.append(DiffLine(kind: .added, text: String(line.dropFirst()), oldLine: nil, newLine: new))
                new += 1
            } else if line.hasPrefix("-") {
                result.append(DiffLine(kind: .removed, text: String(line.dropFirst()), oldLine: old, newLine: nil))
                old += 1
            } else {
                result.append(DiffLine(kind: .context, text: String(line.dropFirst()), oldLine: old, newLine: new))
                old += 1
                new += 1
            }
        }
        // git 输出以换行结尾，split 会多出一个空行。
        if let last = result.last, last.kind == .context, last.text.isEmpty, text.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    /// `@@ -10,3 +10,4 @@` → (10, 10)。数量省略时（`-5 +5`）同样只取起点。
    private static func hunkStarts(_ header: String) -> (Int, Int) {
        let parts = header.split(separator: " ")
        func start(_ prefix: Character) -> Int {
            guard let token = parts.first(where: { $0.first == prefix }) else { return 0 }
            return Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
        }
        return (start("-"), start("+"))
    }
}
