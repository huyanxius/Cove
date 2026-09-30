import Foundation

/// Cove 界面和某个 CLI 对话用的协议。三个 CLI 各说各的格式，这里统一翻译成 `StreamEvent`，
/// 于是 `ChatLog` 和对话视图不用知道对面是谁。
///
/// 全部是值类型的状态机：喂进一行输出，吐出界面事件和要写回 stdin 的行（比如 JSON-RPC 的
/// 应答）。不碰进程、不碰线程，所以每种格式都能拿实测样本逐行测。
public protocol ChatProtocol: Sendable {
    /// 连上之后先写的行：握手、开线程之类。
    mutating func opening() -> [String]
    mutating func receive(_ line: String) -> ChatStep
    mutating func send(_ text: String) -> [String]
    mutating func interrupt() -> [String]
    mutating func answer(_ request: PermissionRequest, allow: Bool) -> [String]
    /// 对面支持中途打断。不支持的，界面上就不给停止按钮。
    var canInterrupt: Bool { get }

    var controls: ChatControls { get }
    mutating func setModel(_ value: String) -> ControlChange
    mutating func setEffort(_ level: String) -> ControlChange
    mutating func setMode(_ id: String) -> ControlChange
    /// CLI 自己给这个会话的 ID（codex 的线程 ID、agy 的对话 ID），拿到后 Cove 用它认领会话；
    /// claude 的 ID 是 Cove 预先指定的，这里为 nil。
    var externalID: String? { get }
}

public struct ChatStep: Equatable, Sendable {
    public var events: [StreamEvent] = []
    /// 要写回 stdin 的行，每行以 `\n` 结尾。
    public var replies: [String] = []

    public init(events: [StreamEvent] = [], replies: [String] = []) {
        self.events = events
        self.replies = replies
    }
}

// MARK: - claude

/// claude 的 stream-json：见 `StreamEvent` / `StreamInput`。
public struct ClaudeChatProtocol: ChatProtocol {
    private var counter = 0
    public private(set) var controls = ChatControls()

    /// `effort`：用户 settings.json 里的 `effortLevel`。协议不回报当前强度，只能从这里起步。
    public init(effort: String? = nil) {
        controls.effort = effort
        controls.model = "default"
        controls.modes = PermissionMode.allCases.map(\.rawValue)
    }

    public var canInterrupt: Bool { true }
    public var externalID: String? { nil }

    public mutating func opening() -> [String] { [StreamInput.initialize(requestID: nextID())] }

    public mutating func receive(_ line: String) -> ChatStep {
        let events = StreamEvent.parse(line)
        for event in events {
            switch event {
            case let .sessionInfo(models, mode):
                controls.models = models
                controls.mode = mode ?? controls.mode
                refreshEffortLevels()
            case let .permissionMode(mode):
                controls.mode = mode
            default:
                break
            }
        }
        return ChatStep(events: events)
    }

    public mutating func setModel(_ value: String) -> ControlChange {
        controls.model = value
        refreshEffortLevels()
        return .send([StreamInput.setModel(value, requestID: nextID())])
    }

    public mutating func setEffort(_ level: String) -> ControlChange {
        controls.effort = level
        return .send([StreamInput.setEffort(level, requestID: nextID())])
    }

    /// 当前模式等 claude 应答（或 status 事件）回来才改，切换被拒时界面不会显示成已切换。
    public mutating func setMode(_ id: String) -> ControlChange {
        guard let mode = PermissionMode(rawValue: id) else { return .send([]) }
        return .send([StreamInput.setPermissionMode(mode, requestID: nextID())])
    }

    private mutating func refreshEffortLevels() {
        controls.effortLevels = controls.models.first { $0.value == controls.model }?.effortLevels ?? []
    }

    public mutating func send(_ text: String) -> [String] { [StreamInput.userMessage(text)] }

    public mutating func interrupt() -> [String] { [StreamInput.interrupt(requestID: nextID())] }

    public mutating func answer(_ request: PermissionRequest, allow: Bool) -> [String] {
        [StreamInput.permission(requestID: request.requestID, allow: allow, rawInput: request.rawInput)]
    }

    private mutating func nextID() -> String {
        counter += 1
        return "cove-\(counter)"
    }
}

// MARK: - codex

/// `codex app-server`：换行分隔的 JSON-RPC，也是官方 Codex App 和 VS Code 插件用的协议。
///
/// 流程：`initialize` → `initialized` → `thread/start`（或 `thread/resume`）→ 每条消息一个
/// `turn/start`。线程还没开好时用户就发了消息，先排队，线程就绪后合并成一轮发出。
/// 审批是服务端反过来发的请求（`item/commandExecution/requestApproval` 等），
/// 应答要带原样的请求 id，所以 id 按原始 JSON 片段存着。
public struct CodexChatProtocol: ChatProtocol {
    private let cwd: String
    private let resumeID: String?
    private var nextRequest = 0
    private var initializeID = -1
    private var threadRequestID = -1
    public private(set) var threadID: String?
    private var turnID: String?
    private var queued: [String] = []
    /// 已经开始流式输出的 agentMessage 条目，第一段增量前补一个 `blockStart`。
    private var streaming: Set<String> = []
    /// fileChange 条目的首个文件路径：审批请求里只有条目 id。
    private var changePaths: [String: String] = [:]
    /// 审批请求 id → 原始 JSON 片段（数字或字符串）。
    private var approvals: [String: String] = [:]
    private var modelListID = -1
    private var rateLimitsRequestID = -1
    public private(set) var controls = ChatControls()
    /// 用户选过的设置。codex 的 `turn/start` 接受这几项覆盖，对这一轮和之后都生效，
    /// 所以只是记下来，下一条消息带上；nil 表示用 codex 自己的配置。
    private var modelOverride: String?
    private var effortOverride: String?
    private var modeOverride: String?

    /// 三档对应官方 Codex App 的叫法：只读 / 自动（可写工作区，越界询问）/ 完全访问。
    public static let modes = ["read-only", "auto", "full-access"]

    public init(cwd: String, resume: String?, model: String? = nil, effort: String? = nil, mode: String? = nil) {
        self.cwd = cwd
        self.resumeID = resume
        modelOverride = model
        effortOverride = effort
        modeOverride = mode.flatMap { Self.modes.contains($0) ? $0 : nil }
        controls.modes = Self.modes
        controls.model = model
        controls.effort = effort
        controls.mode = modeOverride
    }

    public var canInterrupt: Bool { true }
    public var externalID: String? { threadID }

    public mutating func setModel(_ value: String) -> ControlChange {
        modelOverride = value
        controls.model = value
        refreshEffortLevels()
        return .send([])
    }

    public mutating func setEffort(_ level: String) -> ControlChange {
        effortOverride = level
        controls.effort = level
        return .send([])
    }

    public mutating func setMode(_ id: String) -> ControlChange {
        guard Self.modes.contains(id) else { return .send([]) }
        modeOverride = id
        controls.mode = id
        return .send([])
    }

    private mutating func refreshEffortLevels() {
        controls.effortLevels = controls.models.first { $0.value == controls.model }?.effortLevels ?? []
    }

    /// 权限档位 → `approvalPolicy` + `sandboxPolicy`。
    static func policy(_ mode: String) -> (approval: String, sandbox: [String: Any]) {
        switch mode {
        case "read-only": ("on-request", ["type": "readOnly"])
        case "full-access": ("never", ["type": "dangerFullAccess"])
        default: ("on-request", ["type": "workspaceWrite"])
        }
    }

    /// 线程应答里的沙箱 → 档位。
    static func mode(fromSandbox sandbox: Any?) -> String? {
        let type = (sandbox as? [String: Any])?["type"] as? String ?? sandbox as? String
        switch type {
        case "readOnly", "read-only": return "read-only"
        case "workspaceWrite", "workspace-write": return "auto"
        case "dangerFullAccess", "danger-full-access": return "full-access"
        default: return nil
        }
    }

    public mutating func opening() -> [String] {
        initializeID = nextID()
        return [request(initializeID, "initialize", ["clientInfo": ["name": "cove", "title": "Cove", "version": "1.0"]])]
    }

    public mutating func send(_ text: String) -> [String] {
        guard let threadID else {
            queued.append(text)
            return []
        }
        return [turnStart(threadID, text)]
    }

    public mutating func interrupt() -> [String] {
        guard let threadID, let turnID else { return [] }
        return [request(nextID(), "turn/interrupt", ["threadId": threadID, "turnId": turnID])]
    }

    public mutating func answer(_ request: PermissionRequest, allow: Bool) -> [String] {
        guard let raw = approvals.removeValue(forKey: request.requestID) else { return [] }
        return [Self.line("{\"id\":\(raw),\"result\":{\"decision\":\"\(allow ? "accept" : "decline")\"}}")]
    }

    public mutating func receive(_ line: String) -> ChatStep {
        guard line.first == "{", let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ChatStep() }
        let method = object["method"] as? String
        if let method, object["id"] != nil { return serverRequest(method, object) }
        if let method { return notification(method, object["params"] as? [String: Any] ?? [:]) }
        return response(object)
    }

    // MARK: 应答

    private mutating func response(_ object: [String: Any]) -> ChatStep {
        let id = object["id"] as? Int
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "codex 返回了错误"
            return ChatStep(events: [.turnFinished(error: message, costUSD: nil, apiDuration: nil)])
        }
        let result = object["result"] as? [String: Any] ?? [:]
        var step = ChatStep()
        if id == initializeID {
            step.replies.append(Self.line(#"{"jsonrpc":"2.0","method":"initialized"}"#))
            threadRequestID = nextID()
            if let resumeID {
                step.replies.append(request(threadRequestID, "thread/resume", ["threadId": resumeID]))
            } else {
                step.replies.append(request(threadRequestID, "thread/start", ["cwd": cwd]))
            }
            modelListID = nextID()
            step.replies.append(request(modelListID, "model/list", [:]))
            rateLimitsRequestID = nextID()
            step.replies.append(request(rateLimitsRequestID, "account/rateLimits/read", [:]))
        } else if id == modelListID {
            controls.models = (result["data"] as? [[String: Any]] ?? []).compactMap(Self.model)
            if controls.model == nil {
                controls.model = (result["data"] as? [[String: Any]] ?? [])
                    .first { $0["isDefault"] as? Bool == true }.flatMap { ($0["model"] ?? $0["id"]) as? String }
            }
            refreshEffortLevels()
        } else if id == rateLimitsRequestID {
            if let usage = Self.rateLimits(result["rateLimits"] as? [String: Any]) {
                step.events.append(.usage(usage))
            }
        } else if id == threadRequestID, let thread = result["thread"] as? [String: Any] {
            threadID = thread["id"] as? String
            controls.model = modelOverride ?? result["model"] as? String ?? controls.model
            controls.effort = effortOverride ?? result["reasoningEffort"] as? String ?? controls.effort
            controls.mode = modeOverride ?? Self.mode(fromSandbox: result["sandbox"]) ?? controls.mode
            refreshEffortLevels()
            if resumeID != nil { step.events = Self.history(thread) }
            if let threadID, !queued.isEmpty {
                step.replies.append(turnStart(threadID, queued.joined(separator: "\n\n")))
                queued = []
            }
        } else if let turn = result["turn"] as? [String: Any], let id = turn["id"] as? String {
            turnID = id
        }
        return step
    }

    /// 恢复的线程里已有的对话，翻成和实时事件一样的序列；最后补一个「一轮结束」收尾。
    static func history(_ thread: [String: Any]) -> [StreamEvent] {
        var events: [StreamEvent] = []
        for turn in thread["turns"] as? [[String: Any]] ?? [] {
            for item in turn["items"] as? [[String: Any]] ?? [] {
                if item["type"] as? String == "userMessage" {
                    let text = userText(item)
                    if !text.isEmpty { events.append(.transcript(.humanPrompt(text: text, timestamp: nil, cwd: nil, gitBranch: nil))) }
                } else {
                    var paths: [String: String] = [:]
                    events += itemEvents(item, completed: false, paths: &paths)
                    events += itemEvents(item, completed: true, paths: &paths)
                }
            }
        }
        if !events.isEmpty { events.append(.turnFinished(error: nil, costUSD: nil, apiDuration: nil)) }
        return events
    }

    // MARK: 通知

    private mutating func notification(_ method: String, _ params: [String: Any]) -> ChatStep {
        switch method {
        case "item/agentMessage/delta":
            guard let itemID = params["itemId"] as? String, let delta = params["delta"] as? String else { return ChatStep() }
            var events: [StreamEvent] = []
            if !streaming.contains(itemID) {
                streaming.insert(itemID)
                events.append(.blockStart(.text))
            }
            events.append(.textDelta(delta))
            return ChatStep(events: events)
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any], item["type"] as? String != "userMessage" else { return ChatStep() }
            return ChatStep(events: Self.itemEvents(item, completed: method == "item/completed", paths: &changePaths))
        case "turn/started":
            turnID = (params["turn"] as? [String: Any])?["id"] as? String
            return ChatStep()
        case "turn/completed":
            turnID = nil
            let turn = params["turn"] as? [String: Any]
            let error = (turn?["error"] as? [String: Any])?["message"] as? String
            let duration = (turn?["durationMs"] as? Double).map { $0 / 1000 }
            return ChatStep(events: [.turnFinished(error: error, costUSD: nil, apiDuration: duration)])
        case "thread/tokenUsage/updated":
            let usage = params["tokenUsage"] as? [String: Any]
            let last = usage?["last"] as? [String: Any]
            let total = usage?["total"] as? [String: Any]
            var events: [StreamEvent] = []
            if let total {
                var snapshot = UsageSnapshot()
                snapshot.inputTokens = total["inputTokens"] as? Int
                snapshot.outputTokens = total["outputTokens"] as? Int
                snapshot.cacheReadTokens = total["cachedInputTokens"] as? Int
                snapshot.cacheWriteTokens = total["cacheWriteInputTokens"] as? Int
                events.append(.usage(snapshot))
            }
            events.append(.context(tokens: last?["inputTokens"] as? Int, window: usage?["modelContextWindow"] as? Int))
            return ChatStep(events: events)
        case "account/rateLimits/updated":
            return Self.rateLimits(params["rateLimits"] as? [String: Any]).map { ChatStep(events: [.usage($0)]) } ?? ChatStep()
        case "error":
            let message = ((params["error"] as? [String: Any])?["message"] as? String) ?? "codex 报告了一个错误"
            return ChatStep(events: [.notice(message)])
        default:
            return ChatStep()
        }
    }

    /// `model/list` 里的一项。隐藏的模型不进菜单。
    static func model(_ item: [String: Any]) -> ModelOption? {
        guard item["hidden"] as? Bool != true, let value = (item["model"] ?? item["id"]) as? String else { return nil }
        let efforts = (item["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }
        return ModelOption(value: value, displayName: item["displayName"] as? String ?? value,
                           description: item["description"] as? String ?? "", effortLevels: efforts)
    }

    /// codex 的额度窗口按分钟给：300 是 5 小时，10080 是 7 天。
    static func rateLimits(_ limits: [String: Any]?) -> UsageSnapshot? {
        guard let limits else { return nil }
        var usage = UsageSnapshot()
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any], let used = window["usedPercent"] as? Double else { continue }
            let resets = (window["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            switch window["windowDurationMins"] as? Int {
            case 300: (usage.fiveHourPercent, usage.fiveHourResetsAt) = (used, resets)
            case 10080: (usage.sevenDayPercent, usage.sevenDayResetsAt) = (used, resets)
            default: break
            }
        }
        return usage.fiveHourPercent == nil && usage.sevenDayPercent == nil ? nil : usage
    }

    /// 一个 ThreadItem → 工具调用 / 回复事件。开始时报 toolUse，完成时报结果。
    static func itemEvents(_ item: [String: Any], completed: Bool, paths: inout [String: String]) -> [StreamEvent] {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return [] }
        let status = item["status"] as? String
        let failed = status == "failed" || status == "declined" || (item["exitCode"] as? Int).map { $0 != 0 } == true
        func tool(_ name: String, _ fields: [String: String]) -> [StreamEvent] {
            completed
                ? [.transcript(.toolResult(toolUseID: id, isError: failed, taskID: nil, timestamp: nil))]
                : [.transcript(.assistant(.toolUse(id: id, name: name, input: ToolInput(fields)), stopReason: nil, timestamp: nil))]
        }
        switch type {
        case "agentMessage":
            guard completed, let text = item["text"] as? String else { return [] }
            return [.transcript(.assistant(.text(text), stopReason: nil, timestamp: nil))]
        case "commandExecution":
            return tool("Bash", ["command": item["command"] as? String ?? ""])
        case "fileChange":
            let changes = item["changes"] as? [[String: Any]] ?? []
            let path = changes.first?["path"] as? String ?? ""
            paths[id] = path
            let adds = (changes.first?["kind"] as? [String: Any])?["type"] as? String == "add"
                || changes.first?["kind"] as? String == "add"
            return tool(adds ? "Write" : "Edit", ["file_path": path])
        case "mcpToolCall":
            return tool("mcp__\(item["server"] as? String ?? "mcp")__\(item["tool"] as? String ?? "tool")", [:])
        case "webSearch":
            return tool("WebSearch", ["query": item["query"] as? String ?? ""])
        default:
            return []
        }
    }

    private static func userText(_ item: [String: Any]) -> String {
        (item["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    }

    // MARK: 服务端请求

    private mutating func serverRequest(_ method: String, _ object: [String: Any]) -> ChatStep {
        guard let rawID = Self.rawID(object["id"]) else { return ChatStep() }
        let params = object["params"] as? [String: Any] ?? [:]
        let key = "codex-\(rawID)"
        switch method {
        case "item/commandExecution/requestApproval":
            approvals[key] = rawID
            let command = params["command"] as? String ?? ""
            return ChatStep(events: [.permission(PermissionRequest(
                requestID: key, toolName: "Bash", toolUseID: params["itemId"] as? String,
                summary: params["reason"] as? String ?? command, input: ToolInput(["command": command]), rawInput: "{}"))])
        case "item/fileChange/requestApproval":
            approvals[key] = rawID
            let path = (params["itemId"] as? String).flatMap { changePaths[$0] } ?? ""
            return ChatStep(events: [.permission(PermissionRequest(
                requestID: key, toolName: "Edit", toolUseID: params["itemId"] as? String,
                summary: params["reason"] as? String ?? path, input: ToolInput(["file_path": path]), rawInput: "{}"))])
        default:
            // 其他请求（向用户提问、MCP 表单、额外权限……）Cove 还画不出来：明确回绝，别让 codex 干等。
            let reply = Self.line("{\"id\":\(rawID),\"error\":{\"code\":-32601,\"message\":\"Cove does not support \(method) yet\"}}")
            return ChatStep(events: [.notice("codex 发来了 Cove 还不支持的请求（\(method)），已回绝。需要的话切到终端档位处理。")],
                            replies: [reply])
        }
    }

    private static func rawID(_ value: Any?) -> String? {
        if let number = value as? Int { return String(number) }
        if let string = value as? String,
           let data = try? JSONSerialization.data(withJSONObject: [string]),
           let json = String(data: data, encoding: .utf8) { return String(json.dropFirst().dropLast()) }
        return nil
    }

    // MARK: 编码

    private mutating func nextID() -> Int {
        nextRequest += 1
        return nextRequest
    }

    private mutating func turnStart(_ threadID: String, _ text: String) -> String {
        var params: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": text]]]
        if let modelOverride { params["model"] = modelOverride }
        if let effortOverride { params["effort"] = effortOverride }
        if let modeOverride {
            let policy = Self.policy(modeOverride)
            params["approvalPolicy"] = policy.approval
            params["sandboxPolicy"] = policy.sandbox
        }
        return request(nextID(), "turn/start", params)
    }

    private func request(_ id: Int, _ method: String, _ params: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]))
            ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func line(_ json: String) -> String { json + "\n" }
}

// MARK: - agy

/// agy 的 stream-json：输入 `{"event":"user","message":{"role":"user","content":…}}`；
/// 输出 `init`、每一步的 `step_update`（`step_type` 区分回复 / 工具）和每轮末尾的 `result`。
///
/// print 模式下 agy 不发权限请求（按它自己的规则放行或拒绝），也没有打断的办法。
/// 模型、强度、权限档位都只能用启动参数设（`--model` / `--effort` / `--mode`），
/// 所以改任何一项都是 `.relaunch`：这一轮结束后带新参数、用 `--conversation` 重开。
public struct AgyChatProtocol: ChatProtocol {
    public private(set) var conversationID: String?
    private var texts: [Int: String] = [:]
    private var tools: Set<Int> = []
    public private(set) var controls = ChatControls()

    public static let modes = ["default", "accept-edits", "plan"]
    /// `agy models` 回来之前先用这三档。`agy --help` 虽然写着 `low|medium|high|max`，但实测
    /// 1.2.14 没有一个模型带 max：带 `--effort max` 启动会报 invalid model selection 并退出。
    public static let effortLevels = ["low", "medium", "high"]

    /// 这一轮会话已经累计的 token（`result.usage` 逐轮加），重开进程从零算起。
    private var tokens = UsageSnapshot()

    public init(model: String? = nil, effort: String? = nil, mode: String? = nil) {
        controls.modes = Self.modes
        controls.effortLevels = Self.effortLevels
        controls.model = model
        controls.effort = effort
        controls.mode = mode ?? "default"
        dropUnsupportedEffort()
    }

    public var canInterrupt: Bool { false }
    public var externalID: String? { conversationID }

    public mutating func setModel(_ value: String) -> ControlChange {
        controls.model = value
        refreshEffortLevels()
        return .relaunch
    }

    public mutating func setEffort(_ level: String) -> ControlChange {
        controls.effort = level
        return .relaunch
    }

    public mutating func setMode(_ id: String) -> ControlChange {
        controls.mode = id
        return .relaunch
    }

    /// `agy models` 的结果（没有机器可读格式，是「ID<TAB>名称」一行一个）。
    public mutating func supply(models: [ModelOption]) {
        controls.models = models
        refreshEffortLevels()
    }

    /// 强度跟着模型走：没选模型时按 agy 的默认模型算（实测就是列表第一个 gemini-3.8-flash），
    /// 不认识的模型 ID（比如旧版存下的 `gemini-3.1-pro-high`）保留三档不收窄。
    private mutating func refreshEffortLevels() {
        guard let current = controls.model.map({ id in controls.models.first { $0.value == id } }) ?? controls.models.first
        else { return }
        controls.effortLevels = current.effortLevels
        dropUnsupportedEffort()
    }

    private mutating func dropUnsupportedEffort() {
        if let effort = controls.effort, !controls.effortLevels.contains(effort) { controls.effort = nil }
    }

    /// 强度编在 ID 末尾：`gemini-3.8-flash-high` / `-medium` / `-low` 各占一行，名称带「(High)」。
    /// 合并成一个模型 `gemini-3.8-flash`，档位按低到高排；启动时用 `--model 基础 ID --effort 档位`（实测可用）。
    /// 没有档位后缀的（`claude-sonnet-4-6`）原样保留，不给强度。
    public static func parseModels(_ output: String) -> [ModelOption] {
        var order: [String] = []
        var names: [String: String] = [:]
        var levels: [String: Set<String>] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count == 2, !columns[0].isEmpty, !columns[0].contains(" ") else { continue }
            var id = columns[0], name = columns[1], level: String?
            if let suffix = effortLevels.first(where: { id.hasSuffix("-\($0)") }) {
                id.removeLast(suffix.count + 1)
                name = name.replacingOccurrences(of: " (\(suffix.capitalized))", with: "")
                level = suffix
            }
            if names[id] == nil {
                order.append(id)
                names[id] = name
            }
            if let level { levels[id, default: []].insert(level) }
        }
        return order.map { id in
            ModelOption(value: id, displayName: names[id] ?? id, description: "",
                        effortLevels: effortLevels.filter { levels[id]?.contains($0) == true })
        }
    }

    /// 启动参数。`--print` 必须带参数（空串）并放在最后：agy 会把紧跟在它后面的东西当提示词。
    public static func launchArguments(resume: String?, model: String?, effort: String?, mode: String?) -> [String] {
        var arguments = ["--input-format", "stream-json", "--output-format", "stream-json"]
        if let model { arguments += ["--model", model] }
        if let effort { arguments += ["--effort", effort] }
        if let mode, mode != "default" { arguments += ["--mode", mode] }
        if let resume { arguments += ["--conversation", resume] }
        return arguments + ["--print", ""]
    }

    public mutating func opening() -> [String] { [] }

    public mutating func send(_ text: String) -> [String] {
        let data = (try? JSONSerialization.data(withJSONObject: ["event": "user", "message": ["role": "user", "content": text]]))
            ?? Data("{}".utf8)
        return [String(decoding: data, as: UTF8.self) + "\n"]
    }

    public mutating func interrupt() -> [String] { [] }

    public mutating func answer(_ request: PermissionRequest, allow: Bool) -> [String] { [] }

    public mutating func receive(_ line: String) -> ChatStep {
        guard line.first == "{", let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ChatStep() }
        switch object["event"] as? String {
        case "init":
            conversationID = object["conversation_id"] as? String
            return ChatStep()
        case "step_update":
            return step(object["step_update"] as? [String: Any] ?? [:])
        case "result":
            let result = object["result"] as? [String: Any] ?? [:]
            let failed = result["status"] as? String == "ERROR"
            var events: [StreamEvent] = []
            if let usage = result["usage"] as? [String: Any] {
                func add(_ total: Int?, _ key: String) -> Int { (total ?? 0) + (usage[key] as? Int ?? 0) }
                tokens.inputTokens = add(tokens.inputTokens, "input_tokens")
                tokens.outputTokens = add(tokens.outputTokens, "output_tokens")
                tokens.cacheReadTokens = add(tokens.cacheReadTokens, "cache_read_tokens")
                // agy 不在输出里报模型名，用界面上选中的（没选就是默认的第一个）。
                tokens.modelName = (controls.model.flatMap { id in controls.models.first { $0.value == id } }
                    ?? controls.models.first)?.displayName ?? controls.model
                events.append(.usage(tokens))
            }
            events.append(.turnFinished(error: failed ? (result["error"] as? String ?? "agy 出错了") : nil,
                                        costUSD: nil, apiDuration: result["duration_seconds"] as? Double))
            return ChatStep(events: events)
        default:
            return ChatStep()
        }
    }

    private mutating func step(_ update: [String: Any]) -> ChatStep {
        guard let index = update["step_index"] as? Int else { return ChatStep() }
        let done = update["state"] as? String == "DONE"
        let failed = ["ERROR", "FAILED", "CANCELED"].contains(update["state"] as? String ?? "")
        var events: [StreamEvent] = []
        switch update["step_type"] as? String {
        case "agent_response":
            if let delta = update["text_delta"] as? String {
                if texts[index] == nil {
                    texts[index] = ""
                    events.append(.blockStart(.text))
                }
                texts[index, default: ""] += delta
                events.append(.textDelta(delta))
            }
            if done || failed, let text = texts.removeValue(forKey: index),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                events.append(.transcript(.assistant(.text(text), stopReason: nil, timestamp: nil)))
            }
        case "tool":
            let id = "agy-\(index)"
            if !tools.contains(index) {
                tools.insert(index)
                let info = update["tool_info"] as? [String: Any]
                let (name, input) = Self.tool(update["tool_name"] as? String ?? info?["name"] as? String ?? "tool",
                                              info?["parameters"] as? [String: Any] ?? [:])
                events.append(.transcript(.assistant(.toolUse(id: id, name: name, input: input), stopReason: nil, timestamp: nil)))
            }
            if done || failed {
                events.append(.transcript(.toolResult(toolUseID: id, isError: failed, taskID: nil, timestamp: nil)))
            }
        default:
            break
        }
        return ChatStep(events: events)
    }

    /// agy 的工具名和参数名 → Cove 认识的那套（决定对话里显示「读取 x.swift」还是「调用 view_file」）。
    static func tool(_ name: String, _ parameters: [String: Any]) -> (String, ToolInput) {
        func value(_ keys: [String]) -> String {
            keys.lazy.compactMap { parameters[$0] as? String }.first ?? ""
        }
        let file = value(["AbsolutePath", "TargetFile", "FilePath", "File", "Path"])
        switch name {
        case "view_file", "view_code_item", "view_file_outline": return ("Read", ToolInput(["file_path": file]))
        case "write_to_file": return ("Write", ToolInput(["file_path": file]))
        case "replace_file_content", "multi_replace_file_content", "edit_file": return ("Edit", ToolInput(["file_path": file]))
        case "run_command": return ("Bash", ToolInput(["command": value(["CommandLine", "Command"])]))
        case "grep_search", "codebase_search": return ("Grep", ToolInput(["pattern": value(["Query", "Pattern", "SearchPath"])]))
        case "find_by_name", "list_dir": return ("Glob", ToolInput(["pattern": value(["Pattern", "DirectoryPath", "SearchDirectory"])]))
        case "read_url_content": return ("WebFetch", ToolInput(["url": value(["Url", "URL"])]))
        case "search_web": return ("WebSearch", ToolInput(["query": value(["query", "Query"])]))
        default: return (name, ToolInput([:]))
        }
    }
}
