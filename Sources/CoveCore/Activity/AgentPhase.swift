import Foundation

/// 状态条上那一句「它现在在干什么」。
///
/// 只从 JSONL 推断，所以有一个已知盲区：CLI 弹出权限确认时 JSONL 里什么都不写，
/// 这段时间会一直显示为 `running`。精确区分「在跑」和「在等你批」要靠 M2 的 hooks，
/// 这里不去猜——状态条会显示已持续时长，久了人自己会看一眼。
public enum AgentPhase: Equatable, Sendable {
    /// 还没有任何回合（新会话刚打开）。
    case idle
    /// 模型在生成：刚收到人类消息、刚拿到工具结果、或正在流式输出文字。
    case thinking(since: Date?)
    /// 有工具调用发出、结果未回。并行调用时显示最后发出的那个。
    case running(ToolActivity, since: Date?)
    /// 回合以 `end_turn` 结束，轮到人了。
    case awaitingUser(since: Date?)
}

/// 一次工具调用的人话摘要：动词 + 对象，比如「Editing  View.swift」。
public struct ToolActivity: Equatable, Sendable {
    public let toolName: String
    public let verb: String
    public let detail: String

    public init(toolName: String, verb: String, detail: String) {
        self.toolName = toolName
        self.verb = verb
        self.detail = detail
    }

    public static func describe(name: String, input: ToolInput) -> ToolActivity {
        func file(_ key: String = "file_path") -> String {
            input[key].map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        }
        func make(_ verb: String, _ detail: String) -> ToolActivity {
            ToolActivity(toolName: name, verb: verb, detail: detail)
        }

        switch name {
        case "Bash":
            let firstLine = input["command"]?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return make("Running", input["description"] ?? firstLine)
        case "Edit", "MultiEdit": return make("Editing", file())
        case "Write": return make("Writing", file())
        case "NotebookEdit": return make("Editing", file("notebook_path"))
        case "Read": return make("Reading", file())
        case "Grep", "Glob": return make("Searching", input["pattern"] ?? "")
        case "WebFetch": return make("Fetching", input["url"].flatMap { URL(string: $0)?.host } ?? "")
        case "WebSearch": return make("Searching the web", input["query"] ?? "")
        case "Agent", "Task": return make("Delegating", input["description"] ?? "")
        case "TaskCreate", "TaskUpdate": return make("Planning", input["subject"] ?? "")
        case "Skill": return make("Using skill", input["skill"] ?? "")
        default:
            // mcp__<server>__<tool>：server 名本身可能含下划线以外的字符，按双下划线切。
            if name.hasPrefix("mcp__") {
                let parts = name.dropFirst(5).components(separatedBy: "__")
                return make("Using", parts.joined(separator: " · "))
            }
            return make("Using", name)
        }
    }
}
