import Foundation

/// 把一个会话的事件流折叠成状态条和检查器要显示的全部内容。
///
/// 按事件顺序逐条 `apply`，既能一次性回放整份 JSONL，也能跟着文件增量追加。
/// 工具调用和它的结果隔着若干行，所以调用先按 tool_use id 挂起，结果回来时再决定
/// 计不计数——失败的 Edit、失败的 TaskCreate 都不该出现在界面上。
public struct ActivityTracker: Sendable {
    public private(set) var phase: AgentPhase = .idle
    public private(set) var board = TaskBoard()
    public private(set) var changes = ChangeLog()
    /// 来自 CLI 的累计统计，包含 Bash 间接造成的改动，所以可能大于 `changes` 能解释的量。
    public private(set) var linesAdded = 0
    public private(set) var linesRemoved = 0

    private var pending: [(id: String, name: String, input: ToolInput, since: Date?)] = []

    public init() {}

    public mutating func apply(_ event: TranscriptEvent) {
        switch event {
        case let .humanPrompt(_, timestamp, _, _):
            pending.removeAll()
            phase = .thinking(since: timestamp)

        case let .assistant(block, stopReason, timestamp):
            switch block {
            case let .toolUse(id, name, input):
                pending.append((id, name, input, timestamp))
                phase = .running(ToolActivity.describe(name: name, input: input), since: timestamp)
            case .text where stopReason == "end_turn":
                pending.removeAll()
                phase = .awaitingUser(since: timestamp)
            case .text, .thinking:
                if pending.isEmpty { phase = .thinking(since: phase.since ?? timestamp) }
            }

        case let .toolResult(id, isError, taskID, timestamp):
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
            let call = pending.remove(at: index)
            if !isError { commit(call.name, call.input, taskID: taskID, at: timestamp) }
            if let latest = pending.last {
                phase = .running(ToolActivity.describe(name: latest.name, input: latest.input), since: latest.since)
            } else {
                phase = .thinking(since: timestamp)
            }

        case let .interrupted(timestamp):
            // 被打断的工具调用之后可能还会补一条结果，但回合已经结束了。
            pending.removeAll()
            phase = .awaitingUser(since: timestamp)

        case let .cost(added, removed, _):
            linesAdded = added
            linesRemoved = removed

        case .customTitle, .aiTitle, .other:
            break
        }
    }

    private mutating func commit(_ name: String, _ input: ToolInput, taskID: String?, at date: Date?) {
        switch name {
        case "Edit", "MultiEdit", "Write":
            if let path = input["file_path"] { changes.record(path: path, isWrite: name == "Write", at: date) }
        case "NotebookEdit":
            if let path = input["notebook_path"] { changes.record(path: path, isWrite: false, at: date) }
        case "TaskCreate":
            if let taskID { board.add(id: taskID, subject: input["subject"] ?? "Task \(taskID)") }
        case "TaskUpdate":
            if let id = input["taskId"] { board.update(id: id, status: input["status"], subject: input["subject"]) }
        default:
            break
        }
    }
}

extension AgentPhase {
    public var since: Date? {
        switch self {
        case .idle: nil
        case let .thinking(since), let .awaitingUser(since), let .running(_, since): since
        }
    }
}
