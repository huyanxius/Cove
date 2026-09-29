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
    /// 模型菜单的选项和当前选择（`value`，比如 `default`、`sonnet`）；初始化应答回来前为空。
    private(set) var models: [ModelOption] = []
    private(set) var modelValue = "default"
    private(set) var permissionMode: PermissionMode?
    /// 当前思考强度。协议不回报它，初值取用户 settings.json 里的 `effortLevel`，没设为 nil（显示「默认」）。
    private(set) var effortLevel: String? = ChatBridge.configuredEffort()
    /// 启动时是否带了 `--allow-dangerously-skip-permissions`；没带就不能切到跳过权限。
    private(set) var bypassAllowed = false

    struct DraftChunk {
        let text: String
        let arrived: Date
    }

    /// 进程退出（`exitCode`）或额度 / 模型信息更新时通知 `LiveSession`。
    @ObservationIgnored var onExit: ((Int32) -> Void)?
    @ObservationIgnored var onUsage: ((UsageSnapshot) -> Void)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var requestCounter = 0
    /// 上下文占用的两半，分别从 assistant 行和 result 行到达（见 `StreamEvent.context`）。
    /// 第一轮结束前还不知道窗口大小，圆环先空着。
    @ObservationIgnored private var contextTokens: Int?
    @ObservationIgnored private var contextWindow: Int?
    /// stderr 的最后几行：进程一启动就退出（没登录、参数不认）时拿来告诉用户原因。
    @ObservationIgnored private var errorTail = ""

    let cli: CLIKind
    @ObservationIgnored private var proto: any ChatProtocol

    init(cli: CLIKind, protocol proto: any ChatProtocol) {
        self.cli = cli
        self.proto = proto
        log = ChatLog()
    }

    /// 模型、强度、权限模式这些控制目前只有 claude 的协议支持。
    var supportsSessionControls: Bool { cli == .claude }
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

        let reader = LineReader { [weak self] line in
            guard line.first == "{" else { return }
            DispatchQueue.main.async { self?.receive(line) }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in reader.feed(handle.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
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
        log.addPrompt(text)
        for line in proto.send(text) { write(line) }
    }

    func answer(_ request: PermissionRequest, allow: Bool) {
        log.answer(request.requestID, allowed: allow)
        for line in proto.answer(request, allow: allow) { write(line) }
    }

    func setPermissionMode(_ mode: PermissionMode) {
        guard supportsSessionControls else { return }
        write(StreamInput.setPermissionMode(mode, requestID: nextRequestID()))
    }

    /// `set_model` 的应答不带模型名，发出去就当生效；下一条 assistant 行会带上真实模型 ID。
    func setModel(_ option: ModelOption) {
        guard supportsSessionControls else { return }
        modelValue = option.value
        write(StreamInput.setModel(option.value, requestID: nextRequestID()))
    }

    func setEffort(_ level: String) {
        guard supportsSessionControls else { return }
        effortLevel = level
        write(StreamInput.setEffort(level, requestID: nextRequestID()))
    }

    /// 当前模型支持的强度档位；「default」这一项在初始化应答里同样带着档位。
    var effortLevels: [String] {
        models.first { $0.value == modelValue }?.effortLevels ?? []
    }

    private static func configuredEffort() -> String? {
        let url = SessionIndexer.defaultRoot.deletingLastPathComponent().appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["effortLevel"] as? String
    }

    func interrupt() {
        guard log.isWorking else { return }
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
            case let .sessionInfo(list, mode):
                models = list
                permissionMode = mode.flatMap(PermissionMode.init)
            case let .permissionMode(mode):
                permissionMode = PermissionMode(rawValue: mode)
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
        isRunning = false
        input = nil
        if status != 0, !errorTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.apply(.turnFinished(error: "claude 退出了（\(status)）：\(errorTail.trimmingCharacters(in: .whitespacesAndNewlines))",
                                    costUSD: nil, apiDuration: nil))
        }
        onExit?(status)
    }

    private func write(_ line: String) {
        // 进程已经没了时写管道会触发 SIGPIPE；Cove 启动时已忽略它，这里只需吞掉错误。
        try? input?.write(contentsOf: Data(line.utf8))
    }

    private func nextRequestID() -> String {
        requestCounter += 1
        return "cove-ui-\(requestCounter)"
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
