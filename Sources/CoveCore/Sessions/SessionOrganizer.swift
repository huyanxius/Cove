import Foundation

/// 用户对侧栏会话做的整理：置顶、归档、改名。只存在 Cove 里，不改任何 CLI 的记录——
/// 归档和改名都能撤回，CLI 那边看到的会话原封不动。
public struct SessionMarks: Codable, Equatable, Sendable {
    public var pinned: Set<String> = []
    public var archived: Set<String> = []
    /// 会话 ID → 用户起的名字，优先于 CLI 生成的标题。
    public var titles: [String: String] = [:]

    public init() {}

    /// 会话被删掉之后，把它的整理记录一起清掉。
    public mutating func forget(_ id: String) {
        pinned.remove(id)
        archived.remove(id)
        titles.removeValue(forKey: id)
    }
}

/// 侧栏顶部的筛选。
public struct SessionFilter: Equatable, Sendable {
    /// nil = 全部 CLI。
    public var cli: CLIKind?
    /// true 时只看已归档的；false 时已归档的不出现。
    public var archivedOnly = false
    public var query = ""

    public init(cli: CLIKind? = nil, archivedOnly: Bool = false, query: String = "") {
        self.cli = cli
        self.archivedOnly = archivedOnly
        self.query = query
    }
}

/// 把会话分进侧栏的几个区：置顶、临时、其余（其余再由界面按项目分组或平铺）。
/// 每个区内按最近活动倒序。
public enum SessionOrganizer {
    public struct Sections: Equatable, Sendable {
        public var pinned: [SessionSummary] = []
        public var scratch: [SessionSummary] = []
        public var others: [SessionSummary] = []
    }

    public static func organize(_ summaries: [SessionSummary], marks: SessionMarks, filter: SessionFilter,
                                isScratch: (SessionSummary) -> Bool) -> Sections {
        let query = filter.query.trimmingCharacters(in: .whitespaces)
        var sections = Sections()
        let visible = summaries
            .map { summary -> SessionSummary in
                var summary = summary
                if let title = marks.titles[summary.id], !title.isEmpty { summary.title = title }
                return summary
            }
            .filter { summary in
                (filter.cli == nil || summary.cli == filter.cli)
                    && marks.archived.contains(summary.id) == filter.archivedOnly
                    && (query.isEmpty || summary.title.localizedCaseInsensitiveContains(query)
                        || (summary.cwd ?? "").localizedCaseInsensitiveContains(query))
            }
            .sorted { $0.lastActivity > $1.lastActivity }
        for summary in visible {
            // 归档视图里不再区分置顶和临时：那里只是一个待找回的列表。
            if !filter.archivedOnly && marks.pinned.contains(summary.id) {
                sections.pinned.append(summary)
            } else if !filter.archivedOnly && isScratch(summary) {
                sections.scratch.append(summary)
            } else {
                sections.others.append(summary)
            }
        }
        return sections
    }

    /// 在终端里恢复这个会话的命令，右键「复制恢复命令」用。
    public static func resumeCommand(for summary: SessionSummary) -> String {
        let args = summary.cli.arguments(resume: summary.id).map(ClaudeLaunch.shellQuote).joined(separator: " ")
        let command = "\(summary.cli.executable) \(args)"
        guard let cwd = summary.cwd else { return command }
        return "cd \(ClaudeLaunch.shellQuote(cwd)) && \(command)"
    }
}
