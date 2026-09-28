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
        didSet { if let selection, selection != oldValue { open(selection) } }
    }
    var searchText = ""
    var showInspector = true
    var expandedGroups: Set<String> = []

    @ObservationIgnored let indexer = SessionIndexer(root: SessionIndexer.defaultRoot)
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let groupPreviewCount = 8

    var selectedLive: LiveSession? { selection.flatMap { live[$0] } }

    /// `open -a Cove --args --new <dir>`：启动即在该目录新建会话，给脚本和以后的 `cove` 命令用。
    func handleLaunchArguments(_ arguments: [String] = CommandLine.arguments) {
        guard let flag = arguments.firstIndex(of: "--new"), arguments.indices.contains(flag + 1) else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            newSession(in: url)
        }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() async {
        let indexer = indexer
        let scanned = await Task.detached(priority: .utility) { indexer.scan() }.value
        sessions = scanned
        hasLoaded = true
        for summary in scanned {
            if let session = live[summary.id], session.title != summary.title { session.title = summary.title }
        }
    }

    /// 侧栏数据：已落盘的会话 + 刚新建、还没写出 JSONL 的会话。
    var groups: [ProjectGroup] {
        var all = sessions
        let known = Set(all.map(\.id))
        for session in live.values where !known.contains(session.id) {
            all.append(SessionSummary(id: session.id, fileURL: URL(fileURLWithPath: "/dev/null"), title: session.title,
                                      cwd: session.cwd, gitBranch: nil, lastActivity: session.startedAt, promptCount: 0))
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            all = all.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.cwd ?? "").localizedCaseInsensitiveContains(query) }
        }
        all.sort { $0.lastActivity > $1.lastActivity }

        var order: [String] = []
        var buckets: [String: [SessionSummary]] = [:]
        for summary in all {
            let key = summary.cwd ?? "?"
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
        let cwd = summary.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let session = LiveSession(id: id, cwd: cwd, title: summary.title, mode: .resume(sessionID: id), indexer: indexer)
        live[id] = session
        session.start()
        session.focusRequest += 1
    }

    func newSession(in directory: URL) {
        let id = UUID().uuidString.lowercased()
        let session = LiveSession(id: id, cwd: directory.path, title: "New session",
                                  mode: .new(sessionID: id), indexer: indexer)
        live[id] = session
        session.start()
        selection = id
        session.focusRequest += 1
    }

    func chooseDirectoryForNewSession() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Start Session"
        panel.message = "Choose the folder Claude Code should work in."
        if let cwd = selectedLive?.cwd { panel.directoryURL = URL(fileURLWithPath: cwd) }
        if panel.runModal() == .OK, let url = panel.url { newSession(in: url) }
    }

    /// 进程已退出的会话，在原地用同一个 ID 重新 resume。
    func restart(_ id: String) {
        guard let old = live.removeValue(forKey: id) else { return }
        old.terminate()
        let session = LiveSession(id: id, cwd: old.cwd, title: old.title, mode: .resume(sessionID: id), indexer: indexer)
        live[id] = session
        session.start()
        session.focusRequest += 1
    }

    func close(_ id: String) {
        live.removeValue(forKey: id)?.terminate()
    }

    func terminateAll() {
        for session in live.values { session.terminate() }
    }

    var totalSessionCount: Int { sessions.count }
    var projectCount: Int { Set(sessions.compactMap(\.cwd)).count }
}
