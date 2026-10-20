import Foundation

/// 扫描 `~/.claude/projects`，把每个顶层 JSONL 变成一条 `SessionSummary`。
///
/// 只看 `<root>/<project>/<id>.jsonl` 这一层：更深的 `subagents/` 是子 agent 的独立转录，
/// 不是用户能 resume 的会话。大会话文件可达几十 MB，所以两道闸门：文件没变（mtime+size）
/// 直接用缓存；变了也只经 `JSONLScanner` 预筛出标题行和人类消息行再解码。
public final class SessionIndexer: @unchecked Sendable {
    public let root: URL
    /// 设了就把备份里「原件已删」的会话也列出来。
    public let archive: TranscriptArchive?
    private var cache: [String: (modified: Date, size: Int, summary: SessionSummary?)] = [:]
    private let lock = NSLock()

    public init(root: URL, archive: TranscriptArchive? = nil) {
        self.root = root
        self.archive = archive
    }

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

        for file in archive?.orphans() ?? [] {
            seen.insert(file.path)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if cache[file.path] == nil { cache[file.path] = (modified, 0, Self.summarize(file: file, modified: modified)) }
            if var summary = cache[file.path]?.summary {
                summary.isArchivedOnly = true
                result.append(summary)
            }
        }

        cache = cache.filter { seen.contains($0.key) }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// 按会话 ID 找它的 JSONL。新会话的 cwd 编码规则是 CLI 的内部细节（中文、点号都会被
    /// 压成 `-`），与其复刻它，不如在二十来个项目目录里找同名文件。
    public func transcriptURL(for sessionID: String) -> URL? {
        let fm = FileManager.default
        let name = sessionID + ".jsonl"
        for project in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let candidate = project.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func summarize(file: URL, modified: Date) -> SessionSummary? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        let relevant = JSONLScanner.lines(in: data, matching: JSONLScanner.summaryFilter)
        return SessionSummarizer.summarize(id: file.deletingPathExtension().lastPathComponent,
                                           fileURL: file, modified: modified, lines: relevant)
    }
}
