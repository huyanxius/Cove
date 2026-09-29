import Foundation

/// 会话记录的备份。
///
/// claude 按 `cleanupPeriodDays`（默认 30 天）静默删除旧的 JSONL，删了就再也 resume 不了。
/// Cove 把 `~/.claude/projects` 下的顶层 JSONL 按原来的相对路径镜像到自己的目录里：
/// 新的、变了的（大小或修改时间不同）才拷；原件被删了，备份留着，不跟着删。
/// 复原就是按同一个相对路径拷回去，claude 的 `--resume` 照常能找到。
public struct TranscriptArchive: Sendable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    public static var defaultDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cove/Transcripts")
    }

    /// 返回这一轮新拷的文件数。
    @discardableResult
    public func sync() -> Int {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var copied = 0
        for project in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
            let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: Array(keys))) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let target = destination.appendingPathComponent(project.lastPathComponent).appendingPathComponent(file.lastPathComponent)
                let original = try? file.resourceValues(forKeys: keys)
                let backup = try? target.resourceValues(forKeys: keys)
                // 时间比到毫秒：写回修改时间时文件系统会丢掉亚微秒的部分，严格相等永远不成立。
                if let backup, backup.fileSize == original?.fileSize,
                   let a = backup.contentModificationDate, let b = original?.contentModificationDate,
                   abs(a.timeIntervalSince(b)) < 0.001 { continue }
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target)
                guard (try? fm.copyItem(at: file, to: target)) != nil else { continue }
                // 拷贝不保留修改时间的话，下一轮会以为又变了。
                if let date = original?.contentModificationDate {
                    try? fm.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
                }
                copied += 1
            }
        }
        return copied
    }

    /// 备份里有、原处已经没有的会话文件（被 CLI 清理掉的）。
    public func orphans() -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for project in (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "jsonl" {
                let original = source.appendingPathComponent(project.lastPathComponent).appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: original.path) { result.append(file) }
            }
        }
        return result
    }

    /// 把一份备份拷回原处，返回原处的路径。
    public func restore(_ backup: URL) throws -> URL {
        let original = source.appendingPathComponent(backup.deletingLastPathComponent().lastPathComponent)
            .appendingPathComponent(backup.lastPathComponent)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: original.path) {
            try FileManager.default.copyItem(at: backup, to: original)
        }
        return original
    }
}
