import Foundation

/// 侧栏里的一条会话。只描述「这是哪次对话」，不描述「它现在在干什么」——
/// 后者属于 `ActivityTracker`，只对打开着的会话维护。
public struct SessionSummary: Identifiable, Hashable, Sendable {
    /// 即 JSONL 文件名，也是 `claude --resume` 要的那个 ID。
    public let id: String
    public let fileURL: URL
    public var title: String
    /// 取自记录里的 `cwd` 字段。不要从 projects 下的目录名反推：那个编码把 `/`、`.`、
    /// 中文都压成了 `-`，`/Users/me/my-app` 和 `/Users/me/my/app` 会撞成同一个名字。
    public var cwd: String?
    public var gitBranch: String?
    /// 文件修改时间，而不是最后一条消息的时间戳：CLI 写标题、写统计也算活动。
    public var lastActivity: Date
    public var promptCount: Int

    public var projectName: String {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown"
    }
}

public enum SessionSummarizer {
    static let titleLimit = 80

    public static func summarize(id: String, fileURL: URL, modified: Date,
                                 lines: some Sequence<Substring>) -> SessionSummary? {
        var customTitle: String?
        var aiTitle: String?
        var firstPrompt: String?
        var cwd: String?
        var branch: String?
        var prompts = 0

        for line in lines {
            for event in TranscriptEvent.parse(line) {
                switch event {
                case let .customTitle(title): customTitle = title
                case let .aiTitle(title): aiTitle = title
                case let .humanPrompt(text, _, promptCwd, promptBranch):
                    prompts += 1
                    if firstPrompt == nil { firstPrompt = text }
                    cwd = promptCwd ?? cwd
                    branch = promptBranch ?? branch
                default: break
                }
            }
        }

        guard let title = customTitle ?? aiTitle ?? firstPrompt.map(flatten) else { return nil }
        return SessionSummary(id: id, fileURL: fileURL, title: title, cwd: cwd, gitBranch: branch,
                              lastActivity: modified, promptCount: prompts)
    }

    static func flatten(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return words.count > titleLimit ? String(words.prefix(titleLimit)) + "…" : words
    }
}
