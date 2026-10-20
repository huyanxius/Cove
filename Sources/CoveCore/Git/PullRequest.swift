import Foundation

/// 当前分支的 PR，来自 `gh pr view --json number,title,state,url,isDraft,statusCheckRollup`。
public struct PullRequest: Equatable, Sendable {
    public let number: Int
    public let title: String
    /// OPEN / MERGED / CLOSED。
    public let state: String
    public let url: URL
    public let isDraft: Bool
    public let checks: [Check]

    public struct Check: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let state: State
        public let link: URL?

        public enum State: Equatable, Sendable {
            case pending, passed, failed, skipped
        }
    }

    public static let jsonFields = "number,title,state,url,isDraft,statusCheckRollup"

    public var failing: [Check] { checks.filter { $0.state == .failed } }
    public var pending: Bool { checks.contains { $0.state == .pending } }

    public static func parse(_ json: String) -> PullRequest? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["number"] as? Int,
              let url = (object["url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let checks = (object["statusCheckRollup"] as? [[String: Any]] ?? []).compactMap(check)
        return PullRequest(number: number, title: object["title"] as? String ?? "", state: object["state"] as? String ?? "OPEN",
                           url: url, isDraft: object["isDraft"] as? Bool ?? false, checks: checks)
    }

    /// statusCheckRollup 里混着两种：GitHub Actions 的 CheckRun（status + conclusion）和
    /// 老式 commit status 的 StatusContext（state）。
    private static func check(_ item: [String: Any]) -> Check? {
        if let name = item["name"] as? String {
            let link = (item["detailsUrl"] as? String).flatMap(URL.init(string:))
            guard item["status"] as? String == "COMPLETED" else { return Check(name: name, state: .pending, link: link) }
            switch item["conclusion"] as? String {
            case "SUCCESS", "NEUTRAL": return Check(name: name, state: .passed, link: link)
            case "SKIPPED": return Check(name: name, state: .skipped, link: link)
            default: return Check(name: name, state: .failed, link: link)
            }
        }
        if let name = item["context"] as? String {
            let link = (item["targetUrl"] as? String).flatMap(URL.init(string:))
            switch item["state"] as? String {
            case "SUCCESS": return Check(name: name, state: .passed, link: link)
            case "PENDING", "EXPECTED": return Check(name: name, state: .pending, link: link)
            default: return Check(name: name, state: .failed, link: link)
            }
        }
        return nil
    }
}

/// Cove 替用户发给 Agent 的几段话。集中放在这里，方便统一改口径，也方便测。
/// 只描述要做的事和该看的地方，怎么做交给 Agent 和用户自己的技能（比如仓库约定的提交流程）。
public enum AgentPrompts {
    public static func fixChecks(_ pr: PullRequest) -> String {
        let names = pr.failing.map(\.name).joined(separator: "、")
        return "PR #\(pr.number) 的检查没过：\(names)。用 `gh pr checks \(pr.number)` 和 `gh run view --log-failed` 看失败日志，"
            + "找到原因后修复，本地验证通过再提交并推送到当前分支。"
    }

    public static let commitChanges = "看一下当前工作区所有未提交的改动，按这个仓库的提交约定拆成合适的提交并写好提交信息，提交前先给我看草稿。"

    public static let openPullRequest = "为当前分支创建 PR：按仓库的 PR 模板和约定写标题与描述，创建前先给我看草稿。"

    /// diff 上的行内评论，一次打包发出去。
    public static func review(file: String, comments: [ReviewComment]) -> String {
        var text = "我在 `\(file)` 的改动上留了这些意见，请逐条处理：\n"
        for comment in comments {
            let location = comment.line.map { "第 \($0) 行" } ?? "（已删除的行）"
            text += "\n- \(location) `\(comment.code.trimmingCharacters(in: .whitespaces))`：\(comment.note)"
        }
        return text
    }
}

public struct ReviewComment: Equatable, Sendable, Identifiable {
    public let id = UUID()
    /// 新文件里的行号；评论落在删除行上时为 nil。
    public let line: Int?
    public let code: String
    public let note: String

    public init(line: Int?, code: String, note: String) {
        self.line = line
        self.code = code
        self.note = note
    }

    public static func == (a: ReviewComment, b: ReviewComment) -> Bool {
        a.line == b.line && a.code == b.code && a.note == b.note
    }
}
