import Foundation

/// 扫描 `~/.claude/projects`，把每个顶层 JSONL 变成一条 `SessionSummary`。
///
/// 只看 `<root>/<project>/<id>.jsonl` 这一层：更深的 `subagents/` 是子 agent 的独立转录，
/// 不是用户能 resume 的会话。大会话文件可达几十 MB，所以两道闸门：文件没变（mtime+size）
/// 直接用缓存；变了也只经 `JSONLScanner` 预筛出标题行和人类消息行再解码。
public final class SessionIndexer: @unchecked Sendable {
    public let root: URL
    private var cache: [String: (modified: Date, size: Int, summary: SessionSummary?)] = [:]
    private let lock = NSLock()

    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return base.appendingPathComponent("projects")
    }

    public func scan() -> [SessionSummary] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

        var seen: Set<String> = []
        var result: [SessionSummary] = []
        var stale: [(file: URL, modified: Date, size: Int)] = []
        for project in projects {
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: keys) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate else { continue }
                let size = values.fileSize ?? 0
                seen.insert(file.path)
                if let hit = cache[file.path], hit.modified == modified, hit.size == size {
                    if let summary = hit.summary { result.append(summary) }
                } else {
                    stale.append((file, modified, size))
                }
            }
        }

        // 首次扫描时几百个文件互不相干，并发摊到所有核上。
        let fresh = UnsafeMutableBufferPointer<SessionSummary?>.allocate(capacity: stale.count)
        defer { fresh.deallocate() }
        DispatchQueue.concurrentPerform(iterations: stale.count) { index in
            (fresh.baseAddress! + index).initialize(to: Self.summarize(file: stale[index].file, modified: stale[index].modified))
        }
        for (index, entry) in stale.enumerated() {
            cache[entry.file.path] = (entry.modified, entry.size, fresh[index])
            if let summary = fresh[index] { result.append(summary) }
        }

        cache = cache.filter { seen.contains($0.key) }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    static func summarize(file: URL, modified: Date) -> SessionSummary? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        let relevant = JSONLScanner.lines(in: data, matching: JSONLScanner.summaryFilter)
        return SessionSummarizer.summarize(id: file.deletingPathExtension().lastPathComponent,
                                           fileURL: file, modified: modified, lines: relevant)
    }
}
