/// 一个文件的增删行数。
public struct LineDelta: Equatable, Sendable {
    public var added: Int
    public var removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }
}

/// 解析 `git diff --numstat` 的输出，键是 git 给出的仓库内相对路径。
/// 二进制文件（`-\t-`）没有行数，直接略过；重命名取新路径。
public enum NumStat {
    public static func parse(_ output: String) -> [String: LineDelta] {
        var result: [String: LineDelta] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard columns.count == 3, let added = Int(columns[0]), let removed = Int(columns[1]) else { continue }
            result[newPath(columns[2])] = LineDelta(added: added, removed: removed)
        }
        return result
    }

    /// `src/{old => new}/f.swift` → `src/new/f.swift`；`a.swift => b.swift` → `b.swift`。
    static func newPath(_ path: String) -> String {
        if let open = path.firstIndex(of: "{"), let close = path.firstIndex(of: "}"), open < close,
           let arrow = path.range(of: " => ", range: open..<close) {
            return String(path[..<open]) + String(path[arrow.upperBound..<close]) + String(path[path.index(after: close)...])
        }
        if let arrow = path.range(of: " => ") { return String(path[arrow.upperBound...]) }
        return path
    }
}
