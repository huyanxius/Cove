import Foundation

/// Agent 自己用 TaskCreate / TaskUpdate 维护的任务清单，也就是「做到哪一步了」。
public struct AgentTask: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    /// CLI 分配的编号（"1"、"2"…），不是 tool_use id。
    public let id: String
    public var subject: String
    public var status: Status
}

public struct TaskBoard: Equatable, Sendable {
    public private(set) var tasks: [AgentTask] = []

    public var completedCount: Int { tasks.filter { $0.status == .completed }.count }
    public var current: AgentTask? { tasks.first { $0.status == .inProgress } }

    public init() {}

    mutating func add(id: String, subject: String) {
        guard !tasks.contains(where: { $0.id == id }) else { return }
        tasks.append(AgentTask(id: id, subject: subject, status: .pending))
    }

    /// TodoWrite 每次交来整张清单，直接整体替换；编号按顺序生成。
    mutating func replaceAll(with todos: [ToolInput.TodoItem]) {
        tasks = todos.enumerated().compactMap { index, todo in
            guard let status = AgentTask.Status(rawValue: todo.status) else { return nil }
            return AgentTask(id: "todo-\(index + 1)", subject: todo.content, status: status)
        }
    }

    mutating func update(id: String, status: String?, subject: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if status == "deleted" {
            tasks.remove(at: index)
            return
        }
        if let status, let parsed = AgentTask.Status(rawValue: status) { tasks[index].status = parsed }
        if let subject, !subject.isEmpty { tasks[index].subject = subject }
    }
}
