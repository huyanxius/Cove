/// 会话从「在忙」变成「要人」的那一刻，决定要不要发系统通知。
///
/// 只在变化的那一下报一次：一直停在「等你」不会反复通知。输入是每次轮询看到的状态，
/// 终端档位来自 JSONL 推断的 `AgentPhase`，Cove 界面来自 stream-json，两边都折算成这里的三态。
public struct Attention: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case working, idle, needsApproval
    }

    public enum Event: Equatable, Sendable {
        /// 一轮做完了，轮到人。
        case finished
        /// 卡在权限确认上。
        case needsApproval
    }

    private var last: State?

    public init() {}

    public mutating func observe(_ state: State) -> Event? {
        defer { last = state }
        guard let last, last != state else { return nil }
        switch (last, state) {
        case (_, .needsApproval): return .needsApproval
        case (.working, .idle): return .finished
        default: return nil
        }
    }
}
