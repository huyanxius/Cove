import AppKit
import CoveCore
import SwiftUI

/// 检查器里的 Git 区：分支与同步、工作区改动、提交、PR 与 CI。
///
/// 对标 VS Code 的源代码管理面板加 GitHub Pull Requests 扩展里最常用的那几下，
/// 再加上 Cove 独有的一步：把「写提交信息」「修 CI」这类活直接交给当前会话里的 Agent。
struct GitSection: View {
    let session: LiveSession
    let repo: GitRepo
    @Environment(AppModel.self) private var model
    @State private var message = ""
    @State private var showAllFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Git")
                Spacer()
                if let busy = repo.busy {
                    Text(busy).font(CoveFont.ui(11)).foregroundStyle(SwiftUI.Color.coveT3)
                }
                if repo.isRepository {
                    Button {
                        model.newSession(in: URL(fileURLWithPath: repo.root ?? session.cwd), cli: .claude, inWorktree: true)
                    } label: {
                        Image(systemName: "square.split.2x1").font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .help("在新工作树里开一个并行的 Claude 会话（⇧⌘N）")
                }
                Button {
                    Task { await repo.refresh(fetch: true, pullRequestNow: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10.5))
                }
                .buttonStyle(.borderless)
                .help("刷新（含 git fetch 和 PR 状态）")
            }
            .frame(height: 20)
            .padding(.bottom, 8)

            if !repo.hasLoaded {
                note("读取中…")
            } else if let status = repo.status {
                branchRow(status)
                if let error = repo.lastError {
                    Text(error)
                        .font(CoveFont.ui(11.5))
                        .foregroundStyle(SwiftUI.Color.coveDel)
                        .lineLimit(3)
                        .padding(.top, 6)
                }
                files(status)
                commitBox(status)
                pullRequest(status)
            } else {
                note("这个文件夹不是 Git 仓库。")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .task(id: session.id) {
            while !Task.isCancelled {
                await repo.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: 分支

    private func branchRow(_ status: RepoStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 10.5)).foregroundStyle(SwiftUI.Color.coveT3)
            Text(status.branch ?? "分离 HEAD")
                .font(CoveFont.mono(12))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .lineLimit(1)
                .truncationMode(.middle)
            if status.ahead > 0 { Text("↑\(status.ahead)").font(CoveFont.mono(11)).foregroundStyle(SwiftUI.Color.coveT2) }
            if status.behind > 0 { Text("↓\(status.behind)").font(CoveFont.mono(11)).foregroundStyle(SwiftUI.Color.coveT2) }
            Spacer(minLength: 4)
            if status.behind > 0 {
                small("拉取") { Task { await repo.pull() } }
            }
            if status.branch != nil, status.upstream == nil || status.ahead > 0 {
                small(status.upstream == nil ? "发布" : "推送") { Task { await repo.push() } }
            }
            if let web = repo.webURL {
                Menu {
                    Button("仓库主页") { NSWorkspace.shared.open(web) }
                    if let branch = status.branch, status.upstream != nil {
                        Button("当前分支") { NSWorkspace.shared.open(GitHubRemote.branchURL(repo: web, branch: branch)) }
                    }
                    Button("Issues") { NSWorkspace.shared.open(web.appendingPathComponent("issues")) }
                    Button("Actions") { NSWorkspace.shared.open(web.appendingPathComponent("actions")) }
                } label: {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("在 GitHub 上打开")
            }
        }
        .disabled(repo.busy != nil)
    }

    // MARK: 改动

    @ViewBuilder
    private func files(_ status: RepoStatus) -> some View {
        if status.files.isEmpty {
            note("工作区是干净的。").padding(.top, 8)
        } else {
            let visible = showAllFiles ? status.files : Array(status.files.prefix(8))
            VStack(alignment: .leading, spacing: 1) {
                ForEach(visible) { file in
                    fileRow(file)
                }
                if status.files.count > visible.count {
                    Button("还有 \(status.files.count - visible.count) 个") { showAllFiles = true }
                        .buttonStyle(.link)
                        .font(CoveFont.ui(11.5))
                        .padding(.top, 2)
                }
            }
            .padding(.top, 8)
        }
    }

    private func fileRow(_ file: RepoStatus.FileStatus) -> some View {
        let name = (file.path as NSString).lastPathComponent
        let folder = (file.path as NSString).deletingLastPathComponent
        let delta = repo.deltas[file.path]
        return Button {
            session.openDiff(repo.absolutePath(file.path))
        } label: {
            HStack(spacing: 6) {
                Text(file.badge)
                    .font(CoveFont.mono(10.5, weight: .semibold))
                    .foregroundStyle(badgeColor(file.kind))
                    .frame(width: 12)
                Text(name).font(CoveFont.ui(12)).foregroundStyle(SwiftUI.Color.coveT1).lineLimit(1)
                Text(folder).font(CoveFont.ui(11)).foregroundStyle(SwiftUI.Color.coveT3).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 4)
                if let delta {
                    Text("+\(delta.added)").font(CoveFont.mono(10.5)).foregroundStyle(SwiftUI.Color.coveAdd)
                    Text("−\(delta.removed)").font(CoveFont.mono(10.5)).foregroundStyle(SwiftUI.Color.coveDel)
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path)
    }

    private func badgeColor(_ kind: RepoStatus.FileStatus.Kind) -> SwiftUI.Color {
        switch kind {
        case .added, .untracked: .coveAdd
        case .deleted, .conflicted: .coveDel
        case .modified, .renamed: .coveAccent
        }
    }

    // MARK: 提交

    @ViewBuilder
    private func commitBox(_ status: RepoStatus) -> some View {
        if !status.files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TextField("提交信息", text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(CoveFont.ui(12))
                    .lineLimit(1...4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SwiftUI.Color.coveRaisedLine))
                HStack(spacing: 6) {
                    Button("提交全部") {
                        Task { if await repo.commitAll(message: message) { message = "" } }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo.busy != nil)
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                    Button("让 Agent 提交") { session.send(AgentPrompts.commitChanges) }
                        .disabled(!session.isRunning)
                        .help("把「整理改动、写提交信息」交给当前会话，它会按仓库约定先给你看草稿")
                    Spacer()
                }
                .controlSize(.small)
            }
            .padding(.top, 10)
        }
    }

    // MARK: PR

    @ViewBuilder
    private func pullRequest(_ status: RepoStatus) -> some View {
        if let pr = repo.pullRequest {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    NSWorkspace.shared.open(pr.url)
                } label: {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)").font(CoveFont.mono(11.5)).foregroundStyle(SwiftUI.Color.coveAccent)
                        Text(pr.title).font(CoveFont.ui(12)).foregroundStyle(SwiftUI.Color.coveT1).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(prState(pr)).font(CoveFont.ui(11)).foregroundStyle(SwiftUI.Color.coveT3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在 GitHub 上打开 PR")
                ForEach(pr.checks) { check in
                    HStack(spacing: 6) {
                        Rectangle().fill(checkColor(check.state)).frame(width: 6, height: 6)
                        Text(check.name).font(CoveFont.ui(11.5)).foregroundStyle(SwiftUI.Color.coveT2).lineLimit(1)
                        Spacer()
                        if let link = check.link, check.state == .failed {
                            Button("日志") { NSWorkspace.shared.open(link) }.buttonStyle(.link).font(CoveFont.ui(11))
                        }
                    }
                }
                if !pr.failing.isEmpty {
                    Button("让 Agent 修复失败的检查") { session.send(AgentPrompts.fixChecks(pr)) }
                        .controlSize(.small)
                        .disabled(!session.isRunning)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 12)
        } else if let web = repo.webURL, let branch = status.branch, status.upstream != nil,
                  !["main", "master"].contains(branch) {
            HStack(spacing: 6) {
                Text("这个分支还没有 PR").font(CoveFont.ui(11.5)).foregroundStyle(SwiftUI.Color.coveT3)
                Spacer()
                Menu("创建 PR") {
                    Button("在 GitHub 上创建") { NSWorkspace.shared.open(GitHubRemote.compareURL(repo: web, branch: branch)) }
                    Button("让 Agent 创建") { session.send(AgentPrompts.openPullRequest) }
                        .disabled(!session.isRunning)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(CoveFont.ui(11.5))
            }
            .padding(.top, 12)
        }
    }

    private func prState(_ pr: PullRequest) -> String {
        if pr.isDraft { return "草稿" }
        switch pr.state {
        case "MERGED": return "已合并"
        case "CLOSED": return "已关闭"
        default: return pr.pending ? "检查中" : (pr.failing.isEmpty ? "开放" : "检查未过")
        }
    }

    private func checkColor(_ state: PullRequest.Check.State) -> SwiftUI.Color {
        switch state {
        case .passed: .coveAdd
        case .failed: .coveDel
        case .pending: .coveAccent
        case .skipped: .coveT3
        }
    }

    // MARK: 零件

    private func note(_ text: String) -> some View {
        Text(text).font(CoveFont.ui(12)).foregroundStyle(SwiftUI.Color.coveT3)
    }

    private func small(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).controlSize(.mini).font(CoveFont.ui(11))
    }
}
