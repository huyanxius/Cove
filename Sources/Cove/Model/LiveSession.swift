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

    /// codex / agy 新开的会话起初只有 Cove 自己编的 ID，等它们把会话写进自己的索引后，
    /// `AppModel.adoptExternalIDs()` 换成真正的 ID，之后重开才能恢复到同一个会话。
    private(set) var id: String
    let cwd: String
    let cli: CLIKind
    /// 终端里跑 TUI，还是管道里跑 stream-json（Cove 界面）。启动时按设置定下，之后不变；
    /// 设置改了由 `AppModel.reconcileSurfaces()` 用同一个 ID 重开。
    let surface: Surface
    /// Cove 界面模式下的对话进程；终端模式为 nil。
    let chat: ChatBridge?
    /// 会话所在仓库的 Git / GitHub 状态（检查器的 Git 区）。
    let git: GitRepo
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
    /// CLI 画出第一屏之前为 false，中栏这段时间显示咖啡杯加载动画。
    private(set) var hasOutput = false
    private(set) var exitCode: Int32?

    /// 输入框里还没发出去的内容，按会话各存一份（M1 再落盘）。
    var draft = ""
    /// 递增一次，输入框就抢一次焦点。
    var focusRequest = 0
    /// 非 nil 时键盘在 CLI 自己的输入框里（用户在空输入框敲了 `/`），这期间不遮挡 CLI 的输入区。
    private(set) var directInput: DirectInput?

    var openDiffs: [String] = []
    var activeTab: Tab = .terminal

    @ObservationIgnored let terminal: CoveTerminalView
    @ObservationIgnored private var tail: JSONLTail?
    @ObservationIgnored private let mode: ClaudeLaunch.Mode
    @ObservationIgnored private let processObserver = ProcessObserver()
    /// 启动时按 App 外观选定，并经 `--settings` 交给 claude。运行中的 claude 换不了主题，
    /// 外观变了只能重开（见 `AppModel.reconcileTones()`）；codex / agy 用的是终端默认色，
    /// 直接换终端配色就行（`retint(_:)`）。
    @ObservationIgnored private(set) var tone: TerminalTone
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let indexer: SessionIndexer

    /// 在新工作树里开的会话：进程在仓库根目录启动、带 `-w <名字>`，claude 自己建好工作树
    /// 并切进去。`cwd` 这时指向工作树（Git 区、改动列表都看它），它在 claude 启动后才存在。
    @ObservationIgnored private let worktree: (name: String, repoRoot: String)?

    init(id: String, cwd: String, title: String, mode: ClaudeLaunch.Mode, cli: CLIKind = .claude,
         surface: Surface = .terminal, worktree: (name: String, repoRoot: String)? = nil, indexer: SessionIndexer) {
        self.id = id
        self.worktree = worktree
        self.cwd = worktree.map { ClaudeLaunch.worktreePath(repoRoot: $0.repoRoot, name: $0.name) } ?? cwd
        self.cli = cli
        self.surface = surface
        chat = surface == .chat ? ChatBridge() : nil
        git = GitRepo(cwd: cwd)
        self.indexer = indexer
        self.title = title
        self.mode = mode
        terminal = CoveTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.optionAsMetaKey = true
        tone = Palette.isDark(NSApp.effectiveAppearance) ? .dark : .light
        TerminalPalette.apply(tone, to: terminal)

        terminal.onFirstOutput = { [weak self] in self?.hasOutput = true }
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
        if chat != nil { return startChat() }
        let shell = Self.loginShell()
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("SHELL=\(shell)")
        let command: (executable: String, args: [String])
        if cli == .claude {
            let settings = ClaudeLaunch.settingsJSON(theme: tone == .dark ? "dark" : "light",
                                                     statusLineCommand: UsageRelay.command)
            command = ClaudeLaunch.shellCommand(shell: shell, claudeArguments: ClaudeLaunch.claudeArguments(mode, settingsJSON: settings)
                + worktreeArguments)
            environment.append("COVE_SESSION_ID=\(id)")
            if let user = UsageRelay.userStatusLineCommand() { environment.append("COVE_USER_STATUSLINE=\(user)") }
            startUsagePolling()
        } else {
            command = ClaudeLaunch.shellCommand(shell: shell, program: cli.executable, arguments: cli.arguments(resume: resumeID))
        }
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: environment, execName: nil, currentDirectory: launchDirectory)
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

    /// Cove 界面：恢复的会话先从 JSONL 读出历史（stream-json 不会重放），再拉起进程。
    private func startChat() {
        guard let chat else { return }
        chat.onExit = { [weak self] code in self?.processDidExit(code) }
        chat.onUsage = { [weak self] update in
            guard let self else { return }
            let merged = update.merged(over: self.usage)
            if merged != self.usage { self.usage = merged }
        }
        isRunning = true
        exitCode = nil
        let resumeID = self.resumeID
        let indexer = indexer
        Task { [weak self] in
            let history = await Task.detached(priority: .userInitiated) { () -> ChatLog in
                guard let resumeID, let url = indexer.transcriptURL(for: resumeID),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return ChatLog() }
                return ChatLog(history: text.split(separator: "\n"))
            }.value
            guard let self else { return }
            chat.replaceHistory(history)
            var environment = ProcessInfo.processInfo.environment
            environment["COVE_SESSION_ID"] = self.id
            let allowBypass = UserDefaults.standard.bool(forKey: "allowBypassPermissions")
            let arguments = ClaudeLaunch.streamArguments(self.mode, allowBypass: allowBypass) + self.worktreeArguments
            if chat.start(shell: Self.loginShell(), arguments: arguments, cwd: self.launchDirectory, environment: environment) {
                self.hasOutput = true
                self.tail?.start()
                self.startAccountLimits()
            } else {
                self.processDidExit(nil)
            }
        }
    }

    /// Cove 界面没有 statusLine，额度先用其他会话最近报过的值垫着，等第一条 rate_limit_event。
    private func startAccountLimits() {
        Task { [weak self] in
            guard let limits = await Task.detached(operation: { UsageRelay.latestAccountLimits() }).value,
                  let self else { return }
            self.usage = (self.usage ?? UsageSnapshot()).merged(over: limits)
        }
    }

    /// 把输入框内容作为一条消息交给 claude。粘贴和回车分两次写，见 `PasteEncoder`。
    func send(_ text: String) {
        if let chat { return chat.send(text) }
        let bracketed = terminal.getTerminal().bracketedPasteMode
        terminal.send(PasteEncoder.paste(text, bracketed: bracketed))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [terminal] in
            terminal.send(PasteEncoder.submit)
        }
    }

    func sendRaw(_ bytes: [UInt8]) {
        guard let chat else { return terminal.send(bytes) }
        // Cove 界面里没有终端，唯一有意义的透传键是 Esc：打断这一轮。
        if bytes == [0x1B] { chat.interrupt() }
    }

    /// 把键盘交给 CLI 自己的输入框：先写入触发的字符，再让终端成为第一响应者。
    /// 之后终端里的每个按键都过一遍 `DirectInput`，它说该还了就把焦点还给输入框。
    func beginDirectInput(_ bytes: [UInt8], sticky: Bool = false) {
        if !bytes.isEmpty { terminal.send(bytes) }
        directInput = DirectInput(sticky: sticky)
        terminal.window?.makeFirstResponder(terminal)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.terminal.window,
                  event.window?.firstResponder === self.terminal else { return event }
            if self.directInput?.record(KeyStroke(event)) == true {
                // 等这个回车先被终端处理掉再切走焦点。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.endDirectInput() }
            }
            return event
        }
    }

    /// ⌘/：在 Cove 输入框和 CLI 自己的输入框之间来回切。
    func toggleNativeInput() {
        if directInput != nil { endDirectInput() } else { beginDirectInput([], sticky: true) }
    }

    func endDirectInput() {
        guard directInput != nil else { return }
        directInput = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        focusRequest += 1
    }

    /// 外观变了，给不认主题的 CLI 换终端配色。
    func retint(_ tone: TerminalTone) {
        guard cli != .claude, tone != self.tone else { return }
        self.tone = tone
        TerminalPalette.apply(tone, to: terminal)
        terminal.needsDisplay = true
    }

    /// 还没认领到真实 ID 的 codex / agy 新会话。
    var awaitsExternalID: Bool {
        guard cli != .claude, case .new = mode else { return false }
        return !adopted
    }
    @ObservationIgnored private var adopted = false

    func adopt(externalID: String) {
        id = externalID
        adopted = true
    }

    /// 只有新开时才带 `-w`；恢复时进程直接在工作树里启动，claude 从记录里认出它。
    private var worktreeArguments: [String] {
        guard let worktree, case .new = mode else { return [] }
        return ["-w", worktree.name]
    }

    private var launchDirectory: String {
        guard let worktree, case .new = mode else { return cwd }
        return worktree.repoRoot
    }

    private var resumeID: String? {
        if case let .resume(id) = mode { return id }
        return nil
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
                let (snapshot, account) = await Task.detached {
                    (UsageRelay.snapshot(for: id), UsageRelay.latestAccountLimits())
                }.value
                if let self, let base = snapshot ?? account {
                    // 本会话的读数优先；缺的沿用上次，再缺的用账号级最近值补。
                    let merged = base.merged(over: self.usage).merged(over: account)
                    if merged != self.usage { self.usage = merged }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func terminate() {
        chat?.terminate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        usageTask?.cancel()
        tail?.stop()
        if isRunning, chat == nil { terminal.terminate() }
    }

    func processDidExit(_ code: Int32?) {
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
    nonisolated static func loginShell() -> String {
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

/// 记录进程输出的字节数：启动时那串清屏序列只有十几个字节，超过 64 字节才算 CLI 真正画出了东西。
final class CoveTerminalView: LocalProcessTerminalView {
    var onFirstOutput: (() -> Void)?
    private var received = 0

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        guard let callback = onFirstOutput else { return }
        received += slice.count
        if received > 64 {
            onFirstOutput = nil
            DispatchQueue.main.async { callback() }
        }
    }
}
