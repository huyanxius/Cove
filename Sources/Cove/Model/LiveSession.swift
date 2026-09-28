import AppKit
import CoveCore
import Observation
import SwiftTerm

/// 一个打开着的会话：终端视图、里面的 claude 进程，以及从 JSONL 推断出的实时状态。
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
    var title: String
    let startedAt = Date()

    private(set) var tracker = ActivityTracker()
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

    init(id: String, cwd: String, title: String, mode: ClaudeLaunch.Mode, indexer: SessionIndexer) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.mode = mode
        terminal = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.optionAsMetaKey = true
        TerminalPalette.apply(Self.currentTone(), to: terminal)

        processObserver.session = self
        terminal.processDelegate = processObserver

        tail = JSONLTail(locate: { [id] in indexer.transcriptURL(for: id) }) { [weak self] tracker in
            DispatchQueue.main.async { self?.tracker = tracker }
        }
    }

    func start() {
        let shell = Self.loginShell()
        let command = ClaudeLaunch.shellCommand(shell: shell, claudeArguments: ClaudeLaunch.claudeArguments(mode))
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("SHELL=\(shell)")
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: environment, execName: nil, currentDirectory: cwd)
        isRunning = true
        exitCode = nil
        tail?.start()
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

    func terminate() {
        tail?.stop()
        if isRunning { terminal.terminate() }
    }

    fileprivate func processDidExit(_ code: Int32?) {
        isRunning = false
        exitCode = code
    }

    func applyTone() {
        TerminalPalette.apply(Self.currentTone(), to: terminal)
    }

    static func currentTone() -> TerminalTone {
        let settings = SessionIndexer.defaultRoot.deletingLastPathComponent().appendingPathComponent("settings.json")
        let theme = (try? String(contentsOf: settings, encoding: .utf8)).flatMap(TerminalTone.claudeTheme(fromSettings:))
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return TerminalTone.resolve(claudeTheme: theme, systemIsDark: systemIsDark)
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
