import Foundation

/// Claude Code 会话 JSONL 里一行记录对 Cove 有意义的部分。
///
/// 这层只做「翻译」，不做判断：一行 user 记录可能是人类输入、工具结果或本地命令回显，
/// 这里把它们拆成不同事件；「现在算不算在等人」这类推断留给 `ActivityTracker`。
/// JSONL 格式是 CLI 的内部实现、随版本演进，所以解析一律宽松：不认识的字段忽略，
/// 不认识的行给 `.other`，永远不抛错。
public enum TranscriptEvent: Equatable, Sendable {
    /// 用户用 `/rename` 或 `-n` 起的名字，优先级最高。
    case customTitle(String)
    /// CLI 自动生成的标题，同一会话会反复重写，取最后一条。
    case aiTitle(String)
    /// 人真正敲下的一条消息。工具结果、`isMeta` 注入、子 agent 的提示都不算。
    case humanPrompt(text: String, timestamp: Date?, cwd: String?, gitBranch: String?)
    /// assistant 行拆出的单个内容块。`stopReason` 属于整条消息，每个块都带一份。
    case assistant(AssistantBlock, stopReason: String?, timestamp: Date?)
    /// 工具执行完毕。`taskID` 只在 TaskCreate 的结果里有，用来把任务编号对回调用。
    case toolResult(toolUseID: String, isError: Bool, taskID: String?, timestamp: Date?)
    /// assistant 行上的模型 ID（如 `claude-opus-5-5`），每行都带，tracker 只留最新的真实模型。
    case model(String)
    /// 用户按 Esc 打断了回合。CLI 把它记成一条 user 文本 `[Request interrupted by user…]`，
    /// 长得像人话，但不是——不能算进标题和消息数，也意味着轮到人了。
    case interrupted(timestamp: Date?)
    /// 会话累计统计，CLI 周期性整体重写，不是增量。
    case cost(linesAdded: Int, linesRemoved: Int, costUSD: Double)
    case other

    public static func parse(_ line: some StringProtocol) -> [TranscriptEvent] {
        guard let data = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return [.other] }

        switch type {
        case "custom-title":
            return (object["customTitle"] as? String).map { [.customTitle($0)] } ?? [.other]
        case "ai-title":
            return (object["aiTitle"] as? String).map { [.aiTitle($0)] } ?? [.other]
        case "cost-state":
            return [.cost(
                linesAdded: object["totalLinesAdded"] as? Int ?? 0,
                linesRemoved: object["totalLinesRemoved"] as? Int ?? 0,
                costUSD: object["totalCostUSD"] as? Double ?? 0
            )]
        case "user":
            return parseUser(object)
        case "assistant":
            return parseAssistant(object)
        default:
            return [.other]
        }
    }

    private static func parseUser(_ object: [String: Any]) -> [TranscriptEvent] {
        let timestamp = date(object["timestamp"])
        let content = (object["message"] as? [String: Any])?["content"]

        if let blocks = content as? [[String: Any]] {
            let results: [TranscriptEvent] = blocks.compactMap { block in
                guard block["type"] as? String == "tool_result",
                      let id = block["tool_use_id"] as? String else { return nil }
                let taskID = ((object["toolUseResult"] as? [String: Any])?["task"] as? [String: Any])?["id"] as? String
                return .toolResult(toolUseID: id, isError: block["is_error"] as? Bool ?? false,
                                   taskID: taskID, timestamp: timestamp)
            }
            if !results.isEmpty { return results }
        }

        // 走到这里的才可能是人类输入；子 agent（sidechain）和系统注入（meta）排除。
        if object["isMeta"] as? Bool == true || object["isSidechain"] as? Bool == true { return [.other] }
        let text: String
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
        } else {
            return [.other]
        }
        // `<command-name>`、`<local-command-stdout>` 之类是 CLI 回显斜杠命令，不是人话。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[Request interrupted by user") { return [.interrupted(timestamp: timestamp)] }
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return [.other] }
        return [.humanPrompt(text: trimmed, timestamp: timestamp,
                             cwd: object["cwd"] as? String, gitBranch: object["gitBranch"] as? String)]
    }

    private static func parseAssistant(_ object: [String: Any]) -> [TranscriptEvent] {
        guard let message = object["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else { return [.other] }
        let stop = message["stop_reason"] as? String
        let timestamp = date(object["timestamp"])
        let events: [TranscriptEvent] = blocks.compactMap { block in
            switch block["type"] as? String {
            case "text":
                return .assistant(.text(block["text"] as? String ?? ""), stopReason: stop, timestamp: timestamp)
            case "thinking", "redacted_thinking":
                return .assistant(.thinking, stopReason: stop, timestamp: timestamp)
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                return .assistant(.toolUse(id: id, name: name, input: ToolInput(block["input"])),
                                  stopReason: stop, timestamp: timestamp)
            default:
                return nil
            }
        }
        guard !events.isEmpty else { return [.other] }
        if let model = message["model"] as? String { return [.model(model)] + events }
        return events
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { isoFormatter.date(from: $0) }
    }
}

public enum AssistantBlock: Equatable, Sendable {
    case text(String)
    case thinking
    case toolUse(id: String, name: String, input: ToolInput)
}

/// 工具入参里的顶层字符串字段。状态条和改动列表只用得到路径、命令、描述这类字符串，
/// 嵌套结构（比如 MultiEdit 的 edits 数组）一概不保留，免得把整段代码搬进内存。
public struct ToolInput: Equatable, Sendable {
    public var fields: [String: String]
    /// TodoWrite 的整张清单（它每次都重写全部条目）；其他工具为空。
    public var todos: [TodoItem] = []

    public struct TodoItem: Equatable, Sendable {
        public let content: String
        public let status: String
    }

    public init(_ fields: [String: String]) { self.fields = fields }

    init(_ raw: Any?) {
        var fields: [String: String] = [:]
        let object = raw as? [String: Any] ?? [:]
        for (key, value) in object {
            if let string = value as? String { fields[key] = string }
        }
        self.fields = fields
        todos = (object["todos"] as? [[String: Any]] ?? []).compactMap { item in
            guard let content = item["content"] as? String else { return nil }
            return TodoItem(content: content, status: item["status"] as? String ?? "pending")
        }
    }

    public subscript(_ key: String) -> String? { fields[key] }
}
