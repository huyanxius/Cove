import CoveCore
import Foundation
import Observation

/// Cove 界面模式下的 CLI 进程：stdin / stdout 两根管道，一行一个 JSON。说的是哪种格式由
/// `ChatProtocol` 决定（claude 的 stream-json、`codex app-server`、agy 的 stream-json）。
///
/// 仍经用户的登录交互 shell 拉起（alias、PATH、配置目录和终端模式一致）。
/// 交互 shell 读 .zshrc 时可能往 stdout 打横幅，那些不是 JSON 的行在解析时丢掉。
/// 协议是有状态的，所以每一行都回到主线程再交给它，保证按顺序、不并发。
@MainActor
@Observable
final class ChatBridge {
    private(set) var log: ChatLog
    private(set) var commands: [SlashCommand] = []
    private(set) var isRunning = false
    /// 收到过对面的第一行输出。agy 冷启动要半分钟，这之前空白页显示「正在连接」。
    private(set) var connected = false
    /// 正在流式输出的正文按到达批次记下时间，对话视图据此让新到的字模糊渐显。
    /// 只在 `log.draft` 非 nil 时有内容。
    private(set) var draftChunks: [DraftChunk] = []
    /// 模型、强度、权限档位的可选项和当前值，协议维护、这里只是给界面看的副本。
    private(set) var controls = ChatControls()
    /// CLI 自己的会话 ID（codex 线程 / agy 对话），拿到后 `AppModel` 用它认领会话。
    private(set) var externalID: String?
    /// 改了只能在启动时设的项（agy），等这一轮结束按原会话重开。
    private(set) var needsRelaunch = false
    /// 启动时是否带了 `--allow-dangerously-skip-permissions`；没带就不能切到跳过权限（claude）。
    private(set) var bypassAllowed = false
    /// 按过一次 Esc、正在等第二次（见 `escapePressed()`）。
    private(set) var escapeArmed = false
    /// 有操作在等批准时发出的消息：先压着，批准或拒绝之后再发。
    private(set) var heldMessages: [String] = []

    struct DraftChunk {
        let text: String
        let arrived: Date
    }

    /// 进程退出（`exitCode`）或额度 / 模型信息更新时通知 `LiveSession`。
    @ObservationIgnored var onExit: ((Int32) -> Void)?
    @ObservationIgnored var onUsage: ((UsageSnapshot) -> Void)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    /// 上下文占用的两半，分别从 assistant 行和 result 行到达（见 `StreamEvent.context`）。
    /// 第一轮结束前还不知道窗口大小，圆环先空着。
    @ObservationIgnored private var contextTokens: Int?
    @ObservationIgnored private var contextWindow: Int?
    /// stderr 的最后几行：进程一启动就退出（没登录、参数不认）时拿来告诉用户原因。
    @ObservationIgnored private var errorTail = ""

    let cli: CLIKind
    @ObservationIgnored private var proto: any ChatProtocol
    /// 原始往来的日志，`start` 时按会话 ID 建。
    @ObservationIgnored var protocolLog: ProtocolLog?

    init(cli: CLIKind, protocol proto: any ChatProtocol) {
        self.cli = cli
        self.proto = proto
        controls = proto.controls
        log = ChatLog()
    }

    var canInterrupt: Bool { proto.canInterrupt }

    func start(shell: String, program: String, arguments: [String], cwd: String, environment: [String: String]) -> Bool {
        bypassAllowed = arguments.contains("--allow-dangerously-skip-permissions")
        let command = ClaudeLaunch.shellCommand(shell: shell, program: program, arguments: arguments, clearScreen: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let log = protocolLog
        log?.record(.note, "启动 \(program) \(arguments.joined(separator: " "))")
        let reader = LineReader { [weak self] raw in
            guard let line = JSONLine.payload(raw) else { return }
            log?.record(.received, line)
            DispatchQueue.main.async { self?.receive(line) }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in reader.feed(handle.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            if !text.isEmpty { log?.record(.stderr, text) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.errorTail = String((self.errorTail + text).suffix(600))
            }
        }
        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            DispatchQueue.main.async { self?.didExit(status) }
        }

        do {
            try process.run()
        } catch {
            return false
        }
        self.process = process
        input = stdin.fileHandleForWriting
        isRunning = true
        for line in proto.opening() { write(line) }
        return true
    }

    func replaceHistory(_ history: ChatLog) {
        log = history
    }

    /// 在对话里插一条提示（不来自 CLI）。
    func note(_ text: String) {
        log.apply(.notice(text))
    }

    func send(_ text: String) {
        guard isRunning else { return }
        // 等批准的时候插进一条新消息，容易让人忘了上面还卡着一个操作；先压着，选完再发。
        if log.pendingPermission != nil {
            heldMessages.append(text)
            return
        }
        log.addPrompt(text)
        for line in proto.send(text) { write(line) }
    }

    func answer(_ request: PermissionRequest, allow: Bool) {
        log.answer(request.requestID, allowed: allow)
        protocolLog?.record(.note, "权限\(allow ? "允许" : "拒绝")：\(request.toolName) \(request.summary)")
        for line in proto.answer(request, allow: allow) { write(line) }
        guard log.pendingPermission == nil, !heldMessages.isEmpty else { return }
        let held = heldMessages
        heldMessages = []
        send(held.joined(separator: "\n\n"))
    }

    /// 输入框里按 Esc：连按两下（1.2 秒内）才停止。单按一下太容易误触——关输入法候选、
    /// 关弹出菜单都会顺手按 Esc。
    func escapePressed() {
        guard log.isWorking, canInterrupt else { return }
        if escapeArmed {
            escapeArmed = false
            interrupt(source: "Esc 连按两次")
            return
        }
        escapeArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.escapeArmed = false }
    }

    func setModel(_ value: String) { apply(proto.setModel(value), note: "模型") }
    func setEffort(_ level: String) { apply(proto.setEffort(level), note: "思考强度") }
    func setMode(_ id: String) { apply(proto.setMode(id), note: "权限档位") }

    /// agy 的模型列表要另外跑 `agy models` 才拿得到，由 `LiveSession` 取回后塞进来。
    func supply(models: [ModelOption]) {
        guard var agy = proto as? AgyChatProtocol else { return }
        agy.supply(models: models)
        proto = agy
        controls = proto.controls
    }

    private func apply(_ change: ControlChange, note label: String) {
        switch change {
        case let .send(lines):
            for line in lines { write(line) }
        case .relaunch:
            if !needsRelaunch {
                log.apply(.notice("\(cli.displayName) 只能在启动时设\(label)：这一轮结束后会按原会话重开，对话不会丢。"))
            }
            needsRelaunch = true
        }
        controls = proto.controls
        ChatPreferences.save(cli, controls)
    }

    /// `source` 记进协议日志：下次出现「不知道谁停的」时一查就知道。
    func interrupt(source: String) {
        guard log.isWorking else { return }
        protocolLog?.record(.note, "中断，来源：\(source)")
        for line in proto.interrupt() { write(line) }
    }

    func terminate() {
        try? input?.close()
        input = nil
        process?.terminate()
    }

    private func receive(_ line: String) {
        connected = true
        let step = proto.receive(line)
        for reply in step.replies { write(reply) }
        if !step.events.isEmpty { handle(step.events) }
        if controls != proto.controls { controls = proto.controls }
        if externalID != proto.externalID { externalID = proto.externalID }
    }

    private func handle(_ events: [StreamEvent]) {
        for event in events {
            switch event {
            case let .commands(list):
                commands = list.sorted { $0.name < $1.name }
            case let .usage(usage):
                onUsage?(usage)
            case let .context(tokens, window):
                if let tokens { contextTokens = tokens }
                if let window { contextWindow = window }
                if let tokens = contextTokens, let window = contextWindow, window > 0 {
                    var usage = UsageSnapshot()
                    usage.contextPercent = (Double(tokens) / Double(window) * 1000).rounded() / 10
                    onUsage?(usage)
                }
            case let .transcript(.model(id)) where !id.hasPrefix("<"):
                var usage = UsageSnapshot()
                usage.modelID = id
                onUsage?(usage)
            case let .turnFinished(_, cost, duration):
                var usage = UsageSnapshot()
                usage.reportedCostUSD = cost
                usage.apiDuration = duration
                onUsage?(usage)
            default:
                break
            }
            log.apply(event)
            if case let .textDelta(text) = event { draftChunks.append(DraftChunk(text: text, arrived: .now)) }
            if log.draft == nil || log.draft == "" { draftChunks.removeAll() }
        }
    }

    private func didExit(_ status: Int32) {
        protocolLog?.record(.note, "进程退出，状态 \(status)")
        isRunning = false
        input = nil
        if status != 0, !errorTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.apply(.turnFinished(error: "\(cli.executable) 退出了（\(status)）：\(errorTail.trimmingCharacters(in: .whitespacesAndNewlines))",
                                    costUSD: nil, apiDuration: nil))
        }
        onExit?(status)
    }

    private func write(_ line: String) {
        protocolLog?.record(.sent, line)
        // 进程已经没了时写管道会触发 SIGPIPE；Cove 启动时已忽略它，这里只需吞掉错误。
        try? input?.write(contentsOf: Data(line.utf8))
    }

}

/// 把管道里零碎到达的字节拼成完整的行。只在 stdout 的读回调线程上用。
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            onLine(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces))
        }
    }
}

/// 用户为 codex / agy 选过的模型、强度、权限档位，新开的会话沿用。claude 不存：它的强度
/// 以用户 settings.json 为准，模型和模式每个会话由 claude 自己报。
enum ChatPreferences {
    static func load(_ cli: CLIKind) -> (model: String?, effort: String?, mode: String?) {
        let defaults = UserDefaults.standard
        return (defaults.string(forKey: key(cli, "model")), defaults.string(forKey: key(cli, "effort")),
                defaults.string(forKey: key(cli, "mode")))
    }

    static func save(_ cli: CLIKind, _ controls: ChatControls) {
        guard cli != .claude else { return }
        let defaults = UserDefaults.standard
        defaults.set(controls.model, forKey: key(cli, "model"))
        defaults.set(controls.effort, forKey: key(cli, "effort"))
        defaults.set(controls.mode, forKey: key(cli, "mode"))
    }

    /// claude 的初始强度：用户 settings.json 里的 `effortLevel`。
    static func claudeEffort() -> String? {
        let url = SessionIndexer.defaultRoot.deletingLastPathComponent().appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["effortLevel"] as? String
    }

    private static func key(_ cli: CLIKind, _ name: String) -> String { "chat.\(cli.rawValue).\(name)" }
}
