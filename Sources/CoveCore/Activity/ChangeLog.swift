import Foundation

/// 本会话里 Agent 成功改过的一个文件。
///
/// 这是「Agent 碰过什么」，不是「工作区里有什么改动」：用户手改的文件不在这里，
/// Agent 用 Bash 里的 sed / mv 改的文件也不在这里。要看实际差异，拿 `path` 去跑 git diff。
public struct FileChange: Identifiable, Equatable, Sendable {
    public var id: String { path }
    /// 绝对路径，照搬工具入参。
    public let path: String
    public var editCount: Int
    /// 本会话里第一次出现就是 Write，视为新建。先 Edit 后 Write 的不算。
    public var created: Bool
    public var lastTouched: Date?
}

public struct ChangeLog: Equatable, Sendable {
    /// 最近改动的在前。
    public private(set) var files: [FileChange] = []

    public init() {}

    mutating func record(path: String, isWrite: Bool, at date: Date?) {
        if let index = files.firstIndex(where: { $0.path == path }) {
            var change = files.remove(at: index)
            change.editCount += 1
            change.lastTouched = date ?? change.lastTouched
            files.insert(change, at: 0)
        } else {
            files.insert(FileChange(path: path, editCount: 1, created: isWrite, lastTouched: date), at: 0)
        }
    }
}
