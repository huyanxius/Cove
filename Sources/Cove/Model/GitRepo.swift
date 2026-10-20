import CoveCore
import Foundation
import Observation

/// 一个会话所在仓库的 Git / GitHub 状态，检查器的 Git 区用。
///
/// 本地状态（`git status`）便宜，检查器可见时每 5 秒刷一次；PR 和 CI 要走网络（`gh`），
/// 一分钟一次，推送之后立刻补一次。`git fetch` 不自动跑——它会改远端跟踪分支，由刷新按钮触发。
@MainActor
@Observable
final class GitRepo {
    let cwd: String
    private(set) var root: String?
    private(set) var status: RepoStatus?
    private(set) var deltas: [String: LineDelta] = [:]
    private(set) var webURL: URL?
    private(set) var pullRequest: PullRequest?
    /// 正在跑的动作（「提交中…」），界面据此禁用按钮。
    private(set) var busy: String?
    /// 最近一次失败动作的报错首行，下一次成功后清空。
    private(set) var lastError: String?
    private(set) var hasLoaded = false

    @ObservationIgnored private var lastPRCheck = Date.distantPast

    init(cwd: String) {
        self.cwd = cwd
    }

    var isRepository: Bool { root != nil }

    func absolutePath(_ relative: String) -> String {
        ((root ?? cwd) as NSString).appendingPathComponent(relative)
    }

    func refresh(fetch: Bool = false, pullRequestNow: Bool = false) async {
        let cwd = cwd
        let snapshot = await Task.detached(priority: .utility) { () -> (String?, RepoStatus?, [String: LineDelta], URL?) in
            if fetch { _ = Git.run(["fetch", "--quiet"], in: cwd) }
            let top = Git.run(["rev-parse", "--show-toplevel"], in: cwd)
            guard top.status == 0 else { return (nil, nil, [:], nil) }
            let root = top.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = RepoStatus.parse(Git.run(["status", "--porcelain=v2", "--branch"], in: root).output)
            let deltas = NumStat.parse(Git.run(["diff", "--numstat", "HEAD"], in: root).output)
            let remote = Git.run(["remote", "get-url", "origin"], in: root).output
            return (root, status, deltas, GitHubRemote.webURL(fromRemote: remote))
        }.value
        (root, status, deltas, webURL) = snapshot
        hasLoaded = true
        if webURL != nil, pullRequestNow || Date.now.timeIntervalSince(lastPRCheck) > 60 {
            await refreshPullRequest()
        }
    }

    func refreshPullRequest() async {
        guard let root, status?.branch != nil else { return }
        lastPRCheck = .now
        pullRequest = await Task.detached(priority: .utility) {
            guard let gh = GitHubCLI.path else { return nil }
            let result = Git.exec(gh, ["pr", "view", "--json", PullRequest.jsonFields], in: root)
            return result.status == 0 ? PullRequest.parse(result.output) : nil
        }.value
    }

    /// 暂存全部改动并提交。和 VS Code 源代码管理里「提交」在没有暂存时的行为一致。
    func commitAll(message: String) async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return await perform("提交中…") { root in
            let add = Git.run(["add", "-A"], in: root)
            guard add.status == 0 else { return add }
            return Git.run(["commit", "-m", text], in: root)
        }
    }

    /// 没有上游时推送并建立跟踪（`-u origin HEAD`），也就是「发布分支」。
    func push() async {
        let publish = status?.upstream == nil
        _ = await perform(publish ? "发布中…" : "推送中…") { root in
            Git.run(publish ? ["push", "-u", "origin", "HEAD"] : ["push"], in: root)
        }
        await refreshPullRequest()
    }

    /// 只做快进：有分叉时失败并报出来，交给人决定怎么合，不替人 merge。
    func pull() async {
        _ = await perform("拉取中…") { root in Git.run(["pull", "--ff-only"], in: root) }
    }

    private func perform(_ label: String,
                         _ work: @escaping @Sendable (String) -> (status: Int32, output: String, error: String)) async -> Bool {
        guard let root, busy == nil else { return false }
        busy = label
        let result = await Task.detached(priority: .userInitiated) { work(root) }.value
        busy = nil
        if result.status == 0 {
            lastError = nil
        } else {
            let message = (result.error.isEmpty ? result.output : result.error)
                .split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            lastError = message.map(String.init) ?? "git 失败了（\(result.status)）"
        }
        await refresh()
        return result.status == 0
    }
}

/// `gh` 通常装在 Homebrew 下，从 Finder 启动的 App 的 PATH 里没有它。经登录 shell 找一次，缓存下来。
enum GitHubCLI {
    nonisolated(unsafe) private static var cached: String??

    static var path: String? {
        if let cached { return cached }
        let found = Git.exec(LiveSession.loginShell(), ["-l", "-c", "command -v gh"], in: nil).output
            .split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
        cached = .some(found)
        return found
    }
}
