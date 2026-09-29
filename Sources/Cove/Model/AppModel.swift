import AppKit
import CoveCore
import Observation

/// 整个窗口的状态：侧栏里的会话、打开着的会话、当前选中哪一个。
@MainActor
@Observable
final class AppModel {
    struct ProjectGroup: Identifiable {
        var id: String { key }
        /// 以 cwd 分组；同名目录（两个不同位置的 `app`）不会被合并。
        let key: String
        let name: String
        let sessions: [SessionSummary]
        let hiddenCount: Int
    }

    private(set) var sessions: [SessionSummary] = []
    private(set) var live: [String: LiveSession] = [:]
    private(set) var hasLoaded = false
    var selection: String? {
        didSet {
            guard let selection, selection != oldValue else { return }
            unread.remove(selection)
            open(selection)
        }
    }
    var searchText = ""
    var showInspector = true
    var expandedGroups: Set<String> = []

    /// 置顶、归档、改名：只记在 Cove 里（见 `SessionMarks`），改完立刻存。
    private(set) var marks: SessionMarks = AppModel.loadMarks() {
        didSet { Self.saveMarks(marks) }
    }
    /// 侧栏顶部的 CLI 筛选；nil = 全部。
    var cliFilter: CLIKind?
    /// 只看已归档的会话。
    var showingArchive = false
    /// 按项目分组，还是全部按时间平铺。
    var groupByProject = UserDefaults.standard.object(forKey: "groupByProject") as? Bool ?? true {
        didSet { UserDefaults.standard.set(groupByProject, forKey: "groupByProject") }
    }
    /// 在你没看着的时候跑完、或卡在批准上的会话，侧栏亮一个点，点开就灭。
    private(set) var unread: Set<String> = []

    @ObservationIgnored let archive = TranscriptArchive(source: SessionIndexer.defaultRoot,
                                                        destination: TranscriptArchive.defaultDestination)
    @ObservationIgnored lazy var indexer = SessionIndexer(root: SessionIndexer.defaultRoot, archive: archive)
    @ObservationIgnored private var lastBackup = Date.distantPast
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let groupPreviewCount = 8

    var selectedLive: LiveSession? { selection.flatMap { live[$0] } }

    /// 新会话默认用哪个 CLI；设置页里改。
    var defaultCLI: CLIKind {
        get { CLIKind(rawValue: UserDefaults.standard.string(forKey: "defaultCLI") ?? "") ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultCLI") }
    }

    /// `open -a Cove --args --new <dir>`：启动即在该目录新建会话，给脚本和以后的 `cove` 命令用。
    func handleLaunchArguments(_ arguments: [String] = CommandLine.arguments) {
        // `--open <会话ID> [--diff <文件>]`：打开指定会话（可选直接打开某个文件的 diff），给脚本和验收用。
        if let flag = arguments.firstIndex(of: "--open"), arguments.indices.contains(flag + 1) {
            let id = arguments[flag + 1]
            let diff = arguments.firstIndex(of: "--diff").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            Task { [weak self] in
                await self?.refresh()
                self?.selection = id
                if let diff { self?.live[id]?.openDiff(diff) }
            }
            return
        }
        guard let flag = arguments.firstIndex(of: "--new"), arguments.indices.contains(flag + 1) else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1]).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            newSession(in: url)
        }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.backUpIfDue()
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() async {
        let indexer = indexer
        let scanned = await Task.detached(priority: .utility) {
            indexer.scan() + CodexSessions.scan(database: CodexSessions.defaultDatabase)
                + AgySessions.scan(database: AgySessions.defaultDatabase)
        }.value
        sessions = scanned.sorted { $0.lastActivity > $1.lastActivity }
        hasLoaded = true
        adoptExternalIDs()
        for summary in sessions {
            let title = marks.titles[summary.id] ?? summary.title
            if let session = live[summary.id], session.title != title { session.title = title }
        }
    }

    /// 每 5 分钟把会话记录镜像一次（见 `TranscriptArchive`）。APFS 上是克隆，不额外占空间。
    private func backUpIfDue() async {
        guard UserDefaults.standard.object(forKey: "backupTranscripts") as? Bool ?? true,
              Date.now.timeIntervalSince(lastBackup) > 300 else { return }
        lastBackup = .now
        let archive = archive
        await Task.detached(priority: .background) { archive.sync() }.value
    }

    /// codex / agy 新开的会话起初用的是 Cove 编的 ID（它们不接受外部指定 ID）。等它们把会话
    /// 写进自己的索引，按「同一个 CLI、同一个文件夹、在这个标签页打开之后才出现」认领回来，
    /// 侧栏里就不会一条会话出现两次，之后重开也能恢复。
    private func adoptExternalIDs() {
        let pending = live.values.filter(\.awaitsExternalID).sorted { $0.startedAt < $1.startedAt }
        guard !pending.isEmpty else { return }
        var claimed = Set(live.keys)
        for session in pending {
            let folder = (session.cwd as NSString).resolvingSymlinksInPath
            let match = sessions.last { summary in
                summary.cli == session.cli && !claimed.contains(summary.id)
                    && summary.cwd.map { ($0 as NSString).resolvingSymlinksInPath } == folder
                    && summary.lastActivity >= session.startedAt.addingTimeInterval(-5)
            }
            guard let match else { continue }
            claimed.insert(match.id)
            rekey(session, to: match.id)
        }
    }

    private func rekey(_ session: LiveSession, to newID: String) {
        let oldID = session.id
        live.removeValue(forKey: oldID)
        session.adopt(externalID: newID)
        live[newID] = session
        if selection == oldID { selection = newID }
    }

    /// Cove 界面的 codex / agy 会话一连上就报出自己的会话 ID，直接认领，不用等索引、也不用猜。
    /// 改了只能在启动时设的项（agy 的模型、强度、档位）的会话，这一轮结束后按原会话重开。
    func reconcileChatSessions() {
        for session in Array(live.values) {
            guard let chat = session.chat else { continue }
            if session.awaitsExternalID, let external = chat.externalID, live[external] == nil {
                rekey(session, to: external)
            }
            if chat.needsRelaunch, !chat.log.isWorking, session.isRunning {
                restart(session.id, forceResume: chat.externalID != nil)
            }
        }
    }

    /// 侧栏数据：已落盘的会话 + 刚新建、还没写出 JSONL 的会话（含 codex/agy 这类只在内存里的）。
    private var allSummaries: [SessionSummary] {
        var all = sessions
        let known = Set(all.map(\.id))
        for session in live.values where !known.contains(session.id) {
            all.append(SessionSummary(id: session.id, fileURL: URL(fileURLWithPath: "/dev/null"), title: session.title,
                                      cwd: session.cwd, gitBranch: nil, lastActivity: session.startedAt, promptCount: 0,
                                      cli: session.cli))
        }
        return all
    }

    /// 侧栏的几个区（置顶 / 临时 / 其余），筛选和整理规则见 `SessionOrganizer`。
    var sections: SessionOrganizer.Sections {
        SessionOrganizer.organize(allSummaries, marks: marks,
                                  filter: SessionFilter(cli: cliFilter, archivedOnly: showingArchive, query: searchText)) {
            ScratchSpace.isScratch(cwd: $0.cwd)
        }
    }

    /// 「项目」分区：按文件夹分组的正式会话。
    func groups(_ all: [SessionSummary]) -> [ProjectGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)

        var order: [String] = []
        var buckets: [String: [SessionSummary]] = [:]
        for summary in all {
            // claude 记的是解析过软链的真实路径（/private/tmp/…），面板和命令行给的可能是 /tmp/…，
            // 不统一的话同一个目录会分成两组。
            let key = summary.cwd.map { ($0 as NSString).resolvingSymlinksInPath } ?? "?"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(summary)
        }
        return order.map { key in
            let members = buckets[key] ?? []
            // 搜索时、展开时、或者当前选中项在折叠区里时，全部显示。
            let showAll = !query.isEmpty || expandedGroups.contains(key)
                || members.dropFirst(Self.groupPreviewCount).contains { $0.id == selection }
            let visible = showAll ? members : Array(members.prefix(Self.groupPreviewCount))
            return ProjectGroup(key: key, name: members.first?.projectName ?? key, sessions: visible,
                                hiddenCount: members.count - visible.count)
        }
    }

    func open(_ id: String) {
        if let existing = live[id] {
            existing.focusRequest += 1
            return
        }
        guard let summary = sessions.first(where: { $0.id == id }) else { return }
        // 原件已被 CLI 清理：先从备份拷回原处，--resume 才找得到。
        if summary.isArchivedOnly { _ = try? archive.restore(summary.fileURL) }
        let cwd = summary.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let session = LiveSession(id: id, cwd: cwd, title: marks.titles[id] ?? summary.title, mode: .resume(sessionID: id),
                                  cli: summary.cli, surface: InterfaceMode.current.surface(for: summary.cli), indexer: indexer)
        live[id] = session
        session.start()
        session.focusRequest += 1
    }

    /// `inWorktree`：只对 claude、只在 Git 仓库里有效，让会话在一个新工作树里干活，
    /// 和同一仓库里的其他会话互不踩文件。
    func newSession(in directory: URL, cli: CLIKind? = nil, inWorktree: Bool = false) {
        let cli = cli ?? defaultCLI
        let id = UUID().uuidString.lowercased()
        let folder = directory.resolvingSymlinksInPath().path
        var worktree: (name: String, repoRoot: String)?
        if inWorktree, cli == .claude {
            let top = Git.run(["rev-parse", "--show-toplevel"], in: folder)
            if top.status == 0 {
                worktree = ("cove-" + id.prefix(8), top.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let title = cli == .claude ? (worktree == nil ? "New session" : "New session · 工作树")
            : "\(cli.displayName) · \(directory.lastPathComponent)"
        let session = LiveSession(id: id, cwd: folder, title: title,
                                  mode: .new(sessionID: id), cli: cli, surface: InterfaceMode.current.surface(for: cli),
                                  worktree: worktree, indexer: indexer)
        live[id] = session
        session.start()
        selection = id
        session.focusRequest += 1
    }

    /// 临时会话：在 Cove 的临时目录下新建一个以时间命名的空文件夹，立即开会话。
    func newScratchSession(cli: CLIKind? = nil) {
        guard let folder = try? ScratchSpace.makeFolder() else { return }
        newSession(in: folder, cli: cli)
    }

    /// 在输入框里切换 CLI：同一个文件夹里用另一个 CLI 开新会话（上下文不会带过去）。
    func switchCLI(of session: LiveSession, to cli: CLIKind) {
        guard cli != session.cli else { return }
        newSession(in: URL(fileURLWithPath: session.cwd), cli: cli)
    }

    func chooseDirectoryForNewSession(inWorktree: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Start Session"
        panel.message = "Choose the folder Claude Code should work in."
        if let cwd = selectedLive?.cwd { panel.directoryURL = URL(fileURLWithPath: cwd) }
        if panel.runModal() == .OK, let url = panel.url { newSession(in: url, inWorktree: inWorktree) }
    }

    /// 进程已退出的会话，在原地用同一个 ID 重新 resume。`forceResume`：会话 ID 是 CLI 刚报来的，
    /// 索引里可能还没有它，但它一定能恢复。
    func restart(_ id: String, forceResume: Bool = false) {
        guard let old = live.removeValue(forKey: id) else { return }
        old.terminate()
        // 还没发过消息的会话在 CLI 那边没有记录，恢复会失败，改为新开。claude 用同一 ID 新开；
        // codex / agy 新开后会重新认领。
        let known = forceResume || sessions.contains { $0.id == id } || (old.cli == .claude && indexer.transcriptURL(for: id) != nil)
        let mode: ClaudeLaunch.Mode = known ? .resume(sessionID: id) : .new(sessionID: id)
        let session = LiveSession(id: id, cwd: old.cwd, title: old.title, mode: mode, cli: old.cli,
                                  surface: InterfaceMode.current.surface(for: old.cli), indexer: indexer)
        live[id] = session
        session.start()
        session.focusRequest += 1
    }

    // MARK: 整理

    func isPinned(_ id: String) -> Bool { marks.pinned.contains(id) }
    func isArchived(_ id: String) -> Bool { marks.archived.contains(id) }
    func isUnread(_ id: String) -> Bool { unread.contains(id) }

    func togglePin(_ id: String) {
        if marks.pinned.remove(id) == nil { marks.pinned.insert(id) }
    }

    /// 归档：从侧栏收起，不删任何东西。正在跑的会话一并关掉，和官方桌面端一致。
    func toggleArchive(_ id: String) {
        if marks.archived.remove(id) == nil {
            marks.archived.insert(id)
            marks.pinned.remove(id)
            close(id)
            if selection == id { selection = nil }
        }
    }

    /// 空名字 = 恢复成 CLI 自己的标题。
    func rename(_ id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        marks.titles[id] = trimmed.isEmpty ? nil : trimmed
        live[id]?.title = trimmed.isEmpty ? (sessions.first { $0.id == id }?.title ?? live[id]?.title ?? "") : trimmed
    }

    func toggleUnread(_ id: String) {
        if unread.remove(id) == nil { unread.insert(id) }
    }

    /// 删除：会话文件移进废纸篓（能从废纸篓找回），Cove 的备份也一起挪走。
    /// claude 是 JSONL（连同同名的子 agent 目录），codex 是 rollout 文件，agy 是对话库（连同 -wal / -shm）。
    func delete(_ summary: SessionSummary) {
        close(summary.id)
        if selection == summary.id { selection = nil }
        var files = [summary.fileURL]
        switch summary.cli {
        case .claude:
            files.append(summary.fileURL.deletingPathExtension())
            let project = summary.fileURL.deletingLastPathComponent().lastPathComponent
            files.append(archive.destination.appendingPathComponent(project).appendingPathComponent(summary.fileURL.lastPathComponent))
        case .agy:
            files += ["-wal", "-shm"].map { URL(fileURLWithPath: summary.fileURL.path + $0) }
        case .codex:
            break
        }
        for file in files where file.path != "/dev/null" && FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
        marks.forget(summary.id)
        unread.remove(summary.id)
        Task { await refresh() }
    }

    private static func loadMarks() -> SessionMarks {
        guard let data = UserDefaults.standard.data(forKey: "sessionMarks"),
              let marks = try? JSONDecoder().decode(SessionMarks.self, from: data) else { return SessionMarks() }
        return marks
    }

    private static func saveMarks(_ marks: SessionMarks) {
        if let data = try? JSONEncoder().encode(marks) { UserDefaults.standard.set(data, forKey: "sessionMarks") }
    }

    func close(_ id: String) {
        live.removeValue(forKey: id)?.terminate()
    }

    func terminateAll() {
        for session in live.values { session.terminate() }
    }

    var totalSessionCount: Int { sessions.count }

    /// 右下角显示的用量：只来自当前选中的 claude 会话；codex/agy 没有这份数据，就显示空。
    var latestUsage: UsageSnapshot? {
        guard let session = selectedLive, session.cli == .claude else { return nil }
        return session.usage
    }

    /// 外观变了：claude 的主题在启动时就定了，只能重开会话来跟上。空闲的立刻用同一 ID 重开
    /// （--resume 会把对话原样画回来），正在干活的等这一轮结束——见 `reconcileTones()` 的调用处。
    func reconcileTones() {
        let tone: TerminalTone = Palette.isDark(NSApp.effectiveAppearance) ? .dark : .light
        for session in live.values where session.cli != .claude { session.retint(tone) }
        for session in live.values where session.surface == .terminal && session.cli == .claude
            && session.isRunning && session.tone != tone {
            switch session.tracker.phase {
            case .thinking, .running: continue
            case .idle, .awaitingUser: restart(session.id)
            }
        }
    }
    /// 界面设置在「终端」和「Cove 界面」之间切了：两者是不同的进程，只能用同一个 ID 重开。
    /// 和换主题一样，空闲的立刻重开，正在干活的等这一轮结束（由 3 秒的定时器补上）。
    func reconcileSurfaces() {
        let mode = InterfaceMode.current
        for session in live.values where session.isRunning && session.surface != mode.surface(for: session.cli) {
            let busy: Bool
            if let chat = session.chat {
                busy = chat.log.isWorking
            } else {
                switch session.tracker.phase {
                case .thinking, .running: busy = true
                case .idle, .awaitingUser: busy = false
                }
            }
            if !busy { restart(session.id) }
        }
    }

    /// 把当前会话最后一条回复的原文（Markdown）放进剪贴板。终端里复制会带上硬换行和缩进
    /// （官方仓库里几十个未修的 issue），这里直接取 JSONL 里的原文。
    func copyLastReply() {
        guard let session = selectedLive, session.cli == .claude else { return }
        let text: String?
        if let chat = session.chat {
            text = chat.log.lastReply
        } else if let url = indexer.transcriptURL(for: session.id),
                  let raw = try? String(contentsOf: url, encoding: .utf8) {
            text = ChatLog(history: raw.split(separator: "\n")).lastReply
        } else {
            text = nil
        }
        guard let text else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func checkAttention() {
        for (id, _) in Notifier.shared.observe(Array(live.values), selected: selection)
        where !(NSApp.isActive && selection == id) {
            unread.insert(id)
        }
    }

    var projectCount: Int { Set(sessions.compactMap(\.cwd)).count }
}
