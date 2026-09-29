import CoveCore
import Foundation
import Observation

/// Cove 界面模式下的 claude 进程：stdin / stdout 两根管道，一行一个 JSON（见 `StreamEvent`）。
///
/// 仍经用户的登录交互 shell 拉起（alias、PATH、`CLAUDE_CONFIG_DIR` 和终端模式一致）。
/// 交互 shell 读 .zshrc 时可能往 stdout 打横幅，那些不是 JSON 的行在解析时丢掉。
@MainActor
@Observable
final class ChatBridge {
    private(set) var log: ChatLog
    private(set) var commands: [SlashCommand] = []
    private(set) var isRunning = false
    /// 正在流式输出的正文按到达批次记下时间，对话视图据此让新到的字模糊渐显。
    /// 只在 `log.draft` 非 nil 时有内容。
    private(set) var draftChunks: [DraftChunk] = []
    /// 模型菜单的选项和当前选择（`value`，比如 `default`、`sonnet`）；初始化应答回来前为空。
    private(set) var models: [ModelOption] = []
    private(set) var modelValue = "default"
    private(set) var permissionMode: PermissionMode?

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

    init(history: ChatLog = ChatLog()) {
        log = history
    }

    func start(shell: String, arguments: [String], cwd: String, environment: [String: String]) -> Bool {
        let command = ClaudeLaunch.shellCommand(shell: shell, program: "claude", arguments: arguments, clearScreen: false)
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
            let events = StreamEvent.parse(line)
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { self?.handle(events) }
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
        write(StreamInput.initialize(requestID: nextRequestID()))
        return true
    }

    func replaceHistory(_ history: ChatLog) {
        log = history
    }

    func send(_ text: String) {
        guard isRunning else { return }
        log.addPrompt(text)
        write(StreamInput.userMessage(text))
    }

    func answer(_ request: PermissionRequest, allow: Bool) {
        log.answer(request.requestID, allowed: allow)
        write(StreamInput.permission(requestID: request.requestID, allow: allow, rawInput: request.rawInput))
    }

    func setPermissionMode(_ mode: PermissionMode) {
        write(StreamInput.setPermissionMode(mode, requestID: nextRequestID()))
    }

    /// `set_model` 的应答不带模型名，发出去就当生效；下一条 assistant 行会带上真实模型 ID。
    func setModel(_ option: ModelOption) {
        modelValue = option.value
        write(StreamInput.setModel(option.value, requestID: nextRequestID()))
    }

    func interrupt() {
        guard log.isWorking else { return }
        write(StreamInput.interrupt(requestID: nextRequestID()))
    }

    func terminate() {
        try? input?.close()
        input = nil
        process?.terminate()
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
        return "cove-\(requestCounter)"
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
