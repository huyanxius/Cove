import Foundation

/// Cove 界面里中栏那一列对话：把 `StreamEvent` 折叠成一条条可显示的条目。
///
/// 和 `ActivityTracker` 分工：tracker 只回答「现在在干什么、改了哪些文件」，给状态条和
/// 检查器用；这里保留完整的对话顺序，给对话视图用。两者吃同一种事件，互不依赖。
///
/// 恢复旧会话时，stream-json 不会把历史再吐一遍，历史从 JSONL 读（`init(history:)`）——
/// JSONL 的 user / assistant 行和流里的同名行结构一样，走同一个 `apply`。
public struct ChatLog: Sendable {
    public private(set) var items: [ChatItem] = []
    /// 正在流式输出、还没收到完整块的正文。收到完整的 text 块后清空，由正式条目替代。
    public private(set) var draft: String?
    /// 从发出消息到这一轮的 `result` 之间为 true。
    public private(set) var isWorking = false

    public init() {}

    public init(history lines: some Sequence<some StringProtocol>) {
        for line in lines {
            for event in TranscriptEvent.parse(line) where event != .other { apply(.transcript(event)) }
        }
        isWorking = false
        draft = nil
        for index in items.indices {
            // 历史里没等到结果的工具调用（被打断、进程被杀）不该一直转圈。
            if case var .tool(call) = items[index].kind, call.state == .running {
                call.state = .done
                items[index].kind = .tool(call)
            }
        }
    }

    /// 用户从 Cove 的输入框发出一条消息。stream-json 不回显用户消息，所以这里直接记。
    public mutating func addPrompt(_ text: String) {
        append(.prompt(text))
        isWorking = true
    }

    public var lastReply: String? {
        for item in items.reversed() {
            if case let .reply(text) = item.kind { return text }
        }
        return nil
    }

    public var pendingPermission: PermissionRequest? {
        for item in items.reversed() {
            if case let .permission(request, nil) = item.kind { return request }
        }
        return nil
    }

    public mutating func answer(_ requestID: String, allowed: Bool) {
        guard let index = items.lastIndex(where: {
            if case let .permission(request, nil) = $0.kind { return request.requestID == requestID }
            return false
        }), case let .permission(request, _) = items[index].kind else { return }
        items[index].kind = .permission(request, answer: allowed ? .allowed : .denied)
    }

    public mutating func apply(_ event: StreamEvent) {
        switch event {
        case .blockStart(.text):
            draft = ""
        case .blockStart:
            break
        case let .textDelta(text):
            draft = (draft ?? "") + text
        case let .permission(request):
            append(.permission(request, answer: nil))
        case let .turnFinished(error, _, _):
            isWorking = false
            draft = nil
            if let error { append(.notice(error)) }
        case let .transcript(transcript):
            apply(transcript)
        case .commands, .usage, .sessionInfo, .permissionMode, .context:
            break
        }
    }

    private mutating func apply(_ event: TranscriptEvent) {
        switch event {
        case let .humanPrompt(text, _, _, _):
            append(.prompt(text))
            isWorking = true
        case let .assistant(.text(text), stopReason, _):
            draft = nil
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { append(.reply(trimmed)) }
            if stopReason == "end_turn" { isWorking = false }
        case let .assistant(.toolUse(id, name, input), _, _):
            append(.tool(ToolCall(id: id, activity: ToolActivity.describe(name: name, input: input),
                                  filePath: input["file_path"] ?? input["notebook_path"], state: .running)))
        case let .toolResult(id, isError, _, _):
            guard let index = items.lastIndex(where: { if case let .tool(call) = $0.kind { call.id == id } else { false } }),
                  case var .tool(call) = items[index].kind else { return }
            call.state = isError ? .failed : .done
            items[index].kind = .tool(call)
        case .interrupted:
            isWorking = false
            draft = nil
            append(.notice("已中断"))
        case .assistant(.thinking, _, _), .customTitle, .aiTitle, .model, .cost, .other:
            break
        }
    }

    private mutating func append(_ kind: ChatItem.Kind) {
        items.append(ChatItem(id: items.count, kind: kind))
    }
}

public struct ChatItem: Identifiable, Equatable, Sendable {
    /// 在列表里的序号。条目只追加、不删除，所以序号稳定，可以直接当 SwiftUI 的 id。
    public let id: Int
    public var kind: Kind

    public enum Kind: Equatable, Sendable {
        case prompt(String)
        case reply(String)
        case tool(ToolCall)
        case permission(PermissionRequest, answer: PermissionAnswer?)
        /// 中断、报错这类不属于任何一方的提示。
        case notice(String)
    }
}

public enum PermissionAnswer: Equatable, Sendable {
    case allowed, denied
}

public struct ToolCall: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, done, failed }

    public let id: String
    public let activity: ToolActivity
    /// 文件类工具的绝对路径，对话视图里点它打开 diff。
    public let filePath: String?
    public var state: State
}
