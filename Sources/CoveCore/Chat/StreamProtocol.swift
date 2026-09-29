import Foundation

/// Cove 界面模式下和 claude 对话用的协议：`claude -p --input-format stream-json
/// --output-format stream-json`，一行一个 JSON，双向走 stdin / stdout。
///
/// 这是 Agent SDK 用的同一套协议，不是 Cove 发明的。和终端模式的关系：进程仍是原版
/// claude，会话照样写进同一份 JSONL，所以两种界面之间切换就是用同一个 ID `--resume`。
/// 代价是 TUI 专属的交互（`/model` 选择器、`/config` 面板这类）在这个模式下不存在。
///
/// 解析同样宽松：认不出的行（包括登录 shell 往 stdout 打的横幅）一律丢掉，不报错。
public enum StreamEvent: Equatable, Sendable {
    /// user / assistant 行，结构和 JSONL 相同，交给 `TranscriptEvent` 解析。
    case transcript(TranscriptEvent)
    /// 一个内容块开始流式输出。
    case blockStart(BlockKind)
    /// 正文的增量文字。thinking 的增量不显示原文（CLI 本来也只给估算的 token 数）。
    case textDelta(String)
    /// claude 要用一个需要批准的工具，等 Cove 回 `StreamInput.permission`。
    case permission(PermissionRequest)
    /// 可用的斜杠命令：初始化应答里一次，技能 / 插件变化后 `commands_changed` 再给一次。
    case commands([SlashCommand])
    /// 初始化应答里的会话信息：可选模型、当前权限模式。
    case sessionInfo(models: [ModelOption], permissionMode: String?)
    /// `set_permission_mode` 生效后的模式（应答里一次，`system/status` 里再报一次）。
    case permissionMode(String)
    /// 控制请求被拒绝，比如没开放跳过权限时切到 `bypassPermissions`。
    case controlError(String)
    /// 5h / 7d 额度。只填 `UsageSnapshot` 里的额度字段。
    case usage(UsageSnapshot)
    /// 上下文占用：`tokens` 是最近一次请求送进模型的总量（输入 + 缓存读 + 缓存写），来自 assistant 行；
    /// `window` 是模型的上下文窗口，来自 `result` 行的 `modelUsage`。两者分开到，各自可能为 nil。
    case context(tokens: Int?, window: Int?)
    /// 一轮结束（`result` 行）。`error` 非 nil 表示这一轮失败了。
    case turnFinished(error: String?, costUSD: Double?, apiDuration: TimeInterval?)

    public enum BlockKind: Equatable, Sendable {
        case text, thinking, toolUse
    }

    public static func parse(_ line: some StringProtocol) -> [StreamEvent] {
        guard line.first == "{", let data = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "user", "assistant":
            var events = TranscriptEvent.parse(line).filter { $0 != .other }.map(StreamEvent.transcript)
            if type == "assistant", let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any] {
                let total = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
                if total > 0 { events.append(.context(tokens: total, window: nil)) }
            }
            return events
        case "stream_event":
            return parseStreamEvent(object["event"] as? [String: Any] ?? [:])
        case "control_request":
            return PermissionRequest(object).map { [.permission($0)] } ?? []
        case "control_response":
            let response = object["response"] as? [String: Any]
            if response?["subtype"] as? String == "error" {
                return [.controlError(response?["error"] as? String ?? "请求被拒绝")]
            }
            let body = response?["response"] as? [String: Any]
            var events: [StreamEvent] = []
            if let list = commands(body?["commands"]) { events.append(.commands(list)) }
            if let models = body?["models"] as? [[String: Any]] {
                events.append(.sessionInfo(models: models.compactMap(ModelOption.init),
                                           permissionMode: body?["current_permission_mode"] as? String))
            } else if let mode = body?["mode"] as? String {
                events.append(.permissionMode(mode))
            }
            return events
        case "system" where object["subtype"] as? String == "commands_changed":
            return commands(object["commands"]).map { [.commands($0)] } ?? []
        case "system" where object["subtype"] as? String == "status":
            return (object["permissionMode"] as? String).map { [.permissionMode($0)] } ?? []
        case "rate_limit_event":
            return usage(object["rate_limit_info"] as? [String: Any]).map { [.usage($0)] } ?? []
        case "result":
            let failed = object["is_error"] as? Bool ?? false
            let error = failed ? (object["result"] as? String ?? object["subtype"] as? String ?? "出错了") : nil
            let duration = (object["duration_api_ms"] as? Double).map { $0 / 1000 }
            var events: [StreamEvent] = []
            let windows = (object["modelUsage"] as? [String: Any] ?? [:]).values
                .compactMap { ($0 as? [String: Any])?["contextWindow"] as? Int }
            if let window = windows.max() { events.append(.context(tokens: nil, window: window)) }
            events.append(.turnFinished(error: error, costUSD: object["total_cost_usd"] as? Double, apiDuration: duration))
            return events
        default:
            return []
        }
    }

    private static func parseStreamEvent(_ event: [String: Any]) -> [StreamEvent] {
        switch event["type"] as? String {
        case "content_block_start":
            switch (event["content_block"] as? [String: Any])?["type"] as? String {
            case "text": return [.blockStart(.text)]
            case "thinking", "redacted_thinking": return [.blockStart(.thinking)]
            case "tool_use": return [.blockStart(.toolUse)]
            default: return []
            }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String else { return [] }
            return [.textDelta(text)]
        default:
            return []
        }
    }

    private static func commands(_ value: Any?) -> [SlashCommand]? {
        guard let list = value as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return SlashCommand(name: name, description: item["description"] as? String ?? "",
                                argumentHint: item["argumentHint"] as? String ?? "")
        }
    }

    private static func usage(_ info: [String: Any]?) -> UsageSnapshot? {
        guard let windows = info?["unifiedWindows"] as? [String: Any] else { return nil }
        func window(_ key: String) -> (Double?, Date?) {
            let w = windows[key] as? [String: Any]
            return ((w?["utilization"] as? Double).map { ($0 * 1000).rounded() / 10 },
                    (w?["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) })
        }
        var usage = UsageSnapshot()
        (usage.fiveHourPercent, usage.fiveHourResetsAt) = window("five_hour")
        (usage.sevenDayPercent, usage.sevenDayResetsAt) = window("seven_day")
        return usage
    }
}

/// 一次待批准的工具调用。`rawInput` 原样留着：批准时协议要求把入参回传（`updatedInput`），
/// 而 `ToolInput` 只保留了顶层字符串，回传它会把 Edit 的 old/new 之外的结构弄丢。
public struct PermissionRequest: Equatable, Sendable {
    public let requestID: String
    public let toolName: String
    public let toolUseID: String?
    /// CLI 给的一句话说明（Write 是文件名，Bash 是命令描述）。
    public let summary: String
    public let input: ToolInput
    public let rawInput: String

    public init(requestID: String, toolName: String, toolUseID: String?, summary: String,
                input: ToolInput, rawInput: String) {
        self.requestID = requestID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.summary = summary
        self.input = input
        self.rawInput = rawInput
    }

    init?(_ object: [String: Any]) {
        guard let id = object["request_id"] as? String, let request = object["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool", let tool = request["tool_name"] as? String else { return nil }
        let raw = request["input"] ?? [String: Any]()
        let data = (try? JSONSerialization.data(withJSONObject: raw)) ?? Data("{}".utf8)
        self.init(requestID: id, toolName: tool, toolUseID: request["tool_use_id"] as? String,
                  summary: request["description"] as? String ?? "", input: ToolInput(raw),
                  rawInput: String(decoding: data, as: UTF8.self))
    }
}

/// 模型菜单里的一项，来自初始化应答。`value` 是 `set_model` 要的值（`default`、`opus`……）。
public struct ModelOption: Equatable, Sendable, Identifiable {
    public var id: String { value }
    public let value: String
    public let displayName: String
    public let description: String

    public init(value: String, displayName: String, description: String) {
        self.value = value
        self.displayName = displayName
        self.description = description
    }

    init?(_ object: [String: Any]) {
        guard let value = object["value"] as? String else { return nil }
        self.init(value: value, displayName: object["displayName"] as? String ?? value,
                  description: object["description"] as? String ?? "")
    }
}

/// 权限模式。`rawValue` 就是 settings / 协议里用的值。和官方桌面端一样只列交互里用得上的五种，
/// `dontAsk` 是给脚本用的，不列。
public enum PermissionMode: String, CaseIterable, Identifiable, Sendable {
    case `default`, acceptEdits, plan, auto, bypassPermissions

    public var id: String { rawValue }
}

public struct SlashCommand: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let argumentHint: String

    public init(name: String, description: String, argumentHint: String) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
    }

    /// 输入框里正在敲命令名（`/` 开头、还没有空格）时的候选；敲到参数部分就不再提示。
    /// `__` 开头的是 CLI 内部命令（只在服务端拉起的会话里有用），`(removed)` 是已废弃的，都不列。
    public static func matches(_ commands: [SlashCommand], draft: String) -> [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return [] }
        let prefix = draft.dropFirst().lowercased()
        return commands.filter {
            !$0.name.hasPrefix("__") && !$0.description.hasPrefix("(removed)")
                && $0.name.lowercased().hasPrefix(prefix)
        }
    }
}

/// Cove 往 claude stdin 写的行。每行以 `\n` 结尾，拿来直接写进管道。
public enum StreamInput {
    public static func userMessage(_ text: String) -> String {
        line(["type": "user", "message": ["role": "user", "content": text]])
    }

    /// 握手：不发它 claude 也能工作，但拿不到斜杠命令列表。
    public static func initialize(requestID: String) -> String {
        line(["type": "control_request", "request_id": requestID, "request": ["subtype": "initialize"]])
    }

    public static func setPermissionMode(_ mode: PermissionMode, requestID: String) -> String {
        line(["type": "control_request", "request_id": requestID,
              "request": ["subtype": "set_permission_mode", "mode": mode.rawValue]])
    }

    public static func setModel(_ value: String, requestID: String) -> String {
        line(["type": "control_request", "request_id": requestID, "request": ["subtype": "set_model", "model": value]])
    }

    /// 相当于终端里按 Esc：打断当前这一轮。
    public static func interrupt(requestID: String) -> String {
        line(["type": "control_request", "request_id": requestID, "request": ["subtype": "interrupt"]])
    }

    public static func permission(requestID: String, allow: Bool, rawInput: String) -> String {
        let decision: [String: Any]
        if allow {
            let input = (try? JSONSerialization.jsonObject(with: Data(rawInput.utf8))) ?? [String: Any]()
            decision = ["behavior": "allow", "updatedInput": input]
        } else {
            decision = ["behavior": "deny", "message": "用户在 Cove 里拒绝了这次操作。"]
        }
        return line(["type": "control_response",
                     "response": ["subtype": "success", "request_id": requestID, "response": decision]])
    }

    private static func line(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

extension ClaudeLaunch {
    /// Cove 界面模式的启动参数。`--permission-prompt-tool stdio` 让需要批准的工具调用变成
    /// stdout 上的 `can_use_tool` 请求；不加的话 `-p` 模式会直接拒绝。
    /// `allowBypass` 只是允许会话中途切到「跳过权限」，不会默认跳过——不带它时 claude 拒绝这个切换。
    public static func streamArguments(_ mode: Mode, settingsJSON: String? = nil, allowBypass: Bool = false) -> [String] {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json",
                         "--verbose", "--include-partial-messages"]
        if allowBypass { arguments.append("--allow-dangerously-skip-permissions") }
        if let settingsJSON { arguments += ["--settings", settingsJSON] }
        arguments += ["--permission-prompt-tool", "stdio"]
        switch mode {
        case let .new(id): arguments += ["--session-id", id]
        case let .resume(id): arguments += ["--resume", id]
        }
        return arguments
    }
}
