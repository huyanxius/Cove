import AppKit
import CoveCore
import Observation
import SwiftTerm

/// 一个打开着的会话：终端视图、里面的 CLI 进程，以及（claude 才有的）从 JSONL 推断出的实时状态和用量。
///
/// 终端视图由它持有而不是由 SwiftUI 持有，所以切到别的会话时视图只是被摘下来，
/// 进程照跑；切回来再挂上去，滚动位置和屏幕内容都还在。
@MainActor
@Observable
final class LiveSession: Identifiable {
    enum Tab: Hashable {
        case terminal
        case diff(String)
    }

    let id: String
    let cwd: String
    let cli: CLIKind
    var title: String
    let startedAt = Date()

    private(set) var tracker = ActivityTracker() {
        didSet { if tracker.changes != oldValue.changes { refreshFileDeltas() } }
    }
    /// 每个改动文件相对 HEAD 的增删行数，键是绝对路径。随 Agent 的编辑刷新。
    private(set) var fileDeltas: [String: LineDelta] = [:]
    /// 最近一次 statusLine 落盘的用量；只有 claude 会话有。
    private(set) var usage: UsageSnapshot?
    private(set) var isRunning = false
    private(set) var exitCode: Int32?

    /// 输入框里还没发出去的内容，按会话各存一份（M1 再落盘）。
    var draft = ""
    /// 递增一次，输入框就抢一次焦点。
    var focusRequest = 0

    var openDiffs: [String] = []
    var activeTab: Tab = .terminal

    @ObservationIgnored let terminal: LocalProcessTerminalView
    @ObservationIgnored private var tail: JSONLTail?
    @ObservationIgnored private let mode: ClaudeLaunch.Mode
    @ObservationIgnored private let processObserver = ProcessObserver()
    /// 启动时按 App 外观选定，并经 `--settings` 交给 claude。运行中的 TUI 换不了主题，
    /// 所以之后切换外观不改它——新开或恢复的会话才会跟上。
    @ObservationIgnored let tone: TerminalTone

    init(id: String, cwd: String, title: String, mode: ClaudeLaunch.Mode, cli: CLIKind = .claude, indexer: SessionIndexer) {
        self.id = id
        self.cwd = cwd
        self.cli = cli
        self.title = title
        self.mode = mode
        terminal = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.optionAsMetaKey = true
        tone = Palette.isDark(NSApp.effectiveAppearance) ? .dark : .light
        TerminalPalette.apply(tone, to: terminal)

        processObserver.session = self
        terminal.processDelegate = processObserver

        let isResume: Bool
        if case .resume = mode { isResume = true } else { isResume = false }
        guard cli == .claude else { return }
        tail = JSONLTail(settleAfterFirstRead: isResume, locate: { [id] in indexer.transcriptURL(for: id) }) { [weak self] tracker in
            DispatchQueue.main.async { self?.tracker = tracker }
        }
    }

    func start() {
        let shell = Self.loginShell()
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("SHELL=\(shell)")
        let command: (executable: String, args: [String])
        if cli == .claude {
            let settings = ClaudeLaunch.settingsJSON(theme: tone == .dark ? "dark" : "light",
                                                     statusLineCommand: UsageRelay.command)
            command = ClaudeLaunch.shellCommand(shell: shell, claudeArguments: ClaudeLaunch.claudeArguments(mode, settingsJSON: settings))
            environment.append("COVE_SESSION_ID=\(id)")
            if let user = UsageRelay.userStatusLineCommand() { environment.append("COVE_USER_STATUSLINE=\(user)") }
            startUsagePolling()
        } else {
            command = ClaudeLaunch.shellCommand(shell: shell, program: cli.executable, arguments: cli.arguments(resume: nil))
        }
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: environment, execName: nil, currentDirectory: cwd)
        tail?.start()
        // 工作目录不可访问（最常见：macOS 没给 Cove「桌面/文稿」权限）时进程根本起不来，
        // SwiftTerm 不报错，终端就是一片空白。这里把原因直接写进终端。
        guard terminal.process?.running == true else {
            isRunning = false
            exitCode = nil
            terminal.feed(text: "Cove 无法在 \(cwd) 启动 \(cli.executable)。\r\n"
                + "如果它在「桌面」「文稿」或「下载」里，请到 系统设置 → 隐私与安全性 → 完整磁盘取用 里允许 Cove，然后重开这个会话。\r\n")
            return
        }
        isRunning = true
        exitCode = nil
    }

    /// 把输入框内容作为一条消息交给 claude。粘贴和回车分两次写，见 `PasteEncoder`。
    func send(_ text: String) {
        let bracketed = terminal.getTerminal().bracketedPasteMode
        terminal.send(PasteEncoder.paste(text, bracketed: bracketed))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [terminal] in
            terminal.send(PasteEncoder.submit)
        }
    }

    func sendRaw(_ bytes: [UInt8]) {
        terminal.send(bytes)
    }

    var applicationCursor: Bool { terminal.getTerminal().applicationCursor }

    func openDiff(_ path: String) {
        if !openDiffs.contains(path) { openDiffs.append(path) }
        activeTab = .diff(path)
    }

    func closeDiff(_ path: String) {
        openDiffs.removeAll { $0 == path }
        if activeTab == .diff(path) { activeTab = .terminal }
    }

    @ObservationIgnored private var usageTask: Task<Void, Never>?

    private func startUsagePolling() {
        usageTask?.cancel()
        usageTask = Task { [weak self, id] in
            while !Task.isCancelled {
                let snapshot = await Task.detached { UsageRelay.snapshot(for: id) }.value
                if let snapshot, snapshot != self?.usage { self?.usage = snapshot }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func terminate() {
        usageTask?.cancel()
        tail?.stop()
        if isRunning { terminal.terminate() }
    }

    fileprivate func processDidExit(_ code: Int32?) {
        isRunning = false
        exitCode = code
    }

    @ObservationIgnored private var deltaTask: Task<Void, Never>?

    private func refreshFileDeltas() {
        let paths = tracker.changes.files.map(\.path)
        deltaTask?.cancel()
        deltaTask = Task { [weak self] in
            // Agent 连续改几个文件时合并成一次 git 调用。
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let deltas = await Git.numstat(paths: paths)
            guard !Task.isCancelled else { return }
            self?.fileDeltas = deltas
        }
    }

    var totalDelta: LineDelta {
        fileDeltas.values.reduce(LineDelta(added: 0, removed: 0)) {
            LineDelta(added: $0.added + $1.added, removed: $0.removed + $1.removed)
        }
    }

    /// 从 Finder 启动的 App 未必带 SHELL 环境变量，退回到账户记录里的登录 shell。
    static func loginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty { return shell }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell { return String(cString: shell) }
        return "/bin/zsh"
    }
}

/// SwiftTerm 的进程回调不在 actor 体系里，这里转一道回主线程。
private final class ProcessObserver: LocalProcessTerminalViewDelegate {
    weak var session: LiveSession?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in self?.session?.processDidExit(exitCode) }
    }
}
