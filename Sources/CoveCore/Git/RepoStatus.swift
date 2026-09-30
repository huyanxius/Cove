import Foundation

/// `git status --porcelain=v2 --branch` 的解析结果：检查器 Git 区的数据。
///
/// 和 `ChangeLog` 不是一回事：ChangeLog 只记 Agent 在这个会话里动过的文件，这里是整个工作区——
/// 包括你自己在编辑器里改的、Agent 用 Bash 间接改的，也就是提交时真正会进去的东西。
public struct RepoStatus: Equatable, Sendable {
    /// 分离 HEAD 时为 nil。
    public var branch: String?
    /// 没设上游时为 nil；推送要带 `-u`。
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var files: [FileStatus] = []

    public init() {}

    public struct FileStatus: Equatable, Sendable, Identifiable {
        public var id: String { path }
        /// 相对仓库根的路径；重命名取新路径。
        public let path: String
        public let kind: Kind

        public enum Kind: Equatable, Sendable {
            case modified, added, deleted, renamed, untracked, conflicted
        }

        /// 列表里的单字母标记，和 VS Code 源代码管理面板一致：M A D R U(未跟踪) !(冲突)。
        public var badge: String {
            switch kind {
            case .modified: "M"
            case .added: "A"
            case .deleted: "D"
            case .renamed: "R"
            case .untracked: "U"
            case .conflicted: "!"
            }
        }
    }

    public static func parse(_ output: String) -> RepoStatus {
        var status = RepoStatus()
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                status.ahead = parts.first.flatMap { Int($0.dropFirst()) } ?? 0
                status.behind = parts.dropFirst().first.flatMap { Int($0.dropFirst()) } ?? 0
            } else if line.hasPrefix("? ") {
                status.files.append(FileStatus(path: String(line.dropFirst(2)), kind: .untracked))
            } else if line.hasPrefix("u ") {
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                status.files.append(FileStatus(path: field(line, after: 10), kind: .conflicted))
            } else if line.hasPrefix("1 ") {
                // 1 XY sub mH mI mW hH hI path
                let xy = Array(line.dropFirst(2).prefix(2))
                status.files.append(FileStatus(path: field(line, after: 8), kind: kind(xy)))
            } else if line.hasPrefix("2 ") {
                // 2 XY sub mH mI mW hH hI Xscore path<TAB>origPath
                let rest = field(line, after: 9)
                status.files.append(FileStatus(path: String(rest.split(separator: "\t").first ?? ""), kind: .renamed))
            }
        }
        return status
    }

    /// 跳过前 `count` 个空格分隔的字段，剩下的原样返回（路径里可以有空格）。
    private static func field(_ line: Substring, after count: Int) -> String {
        var rest = line[...]
        for _ in 0..<count {
            guard let space = rest.firstIndex(of: " ") else { return "" }
            rest = rest[rest.index(after: space)...]
        }
        return String(rest)
    }

    private static func kind(_ xy: [Character]) -> FileStatus.Kind {
        if xy.contains("D") { return .deleted }
        if xy.first == "A" { return .added }
        return .modified
    }
}

/// 把 remote 地址换成 GitHub 网页地址。只认 github.com；其他托管返回 nil，界面就不显示 GitHub 按钮。
public enum GitHubRemote {
    public static func webURL(fromRemote remote: String) -> URL? {
        var path: Substring
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("git@github.com:") {
            path = trimmed.dropFirst("git@github.com:".count)
        } else if let url = URL(string: trimmed), url.host == "github.com" {
            path = url.path.dropFirst()
        } else if trimmed.hasPrefix("ssh://git@github.com/") {
            path = trimmed.dropFirst("ssh://git@github.com/".count)
        } else {
            return nil
        }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return URL(string: "https://github.com/\(parts[0])/\(parts[1])")
    }

    public static func branchURL(repo: URL, branch: String) -> URL {
        repo.appendingPathComponent("tree").appendingPathComponent(branch)
    }

    /// GitHub 的「比较并新建 PR」页。
    public static func compareURL(repo: URL, branch: String) -> URL {
        URL(string: repo.absoluteString + "/compare/" + (branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch) + "?expand=1")!
    }
}
