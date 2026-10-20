import CoveCore
import SwiftUI

/// 工具栏正中的活动胶囊：这个 Agent 此刻在干什么 | 任务做到哪 | 改了多少行。
/// 三段各自在没有内容时隐藏，所以刚开的会话只剩第一段。
struct ActivityPill: View {
    let session: LiveSession

    var body: some View {
        HStack(spacing: 0) {
            activity
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !session.tracker.board.tasks.isEmpty {
                divider
                tasks.padding(.horizontal, 12)
            }
            let delta = session.totalDelta
            if delta.added + delta.removed > 0 {
                divider
                HStack(spacing: 6) {
                    Text("+\(delta.added)").foregroundStyle(SwiftUI.Color.coveAdd)
                    Text("−\(delta.removed)").foregroundStyle(SwiftUI.Color.coveDel)
                }
                .font(CoveFont.mono(11.5))
                .monospacedDigit()
                .padding(.horizontal, 12)
            }
        }
        .frame(height: 28)
        .frame(minWidth: 380, maxWidth: 640)
        .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SwiftUI.Color.coveRaisedLine))
    }

    private var divider: some View {
        SwiftUI.Color.coveRaisedLine.frame(width: 1)
    }

    @ViewBuilder private var activity: some View {
        let phase = session.tracker.phase
        HStack(spacing: 8) {
            switch SessionState(phase: phase, isRunning: session.isRunning) {
            case .working:
                PixelStep()
            case .waiting:
                PixelDot(state: .waiting)
            case .idle, .ended:
                PixelDot(state: session.isRunning ? .idle : .ended)
            }
            Text(headline(phase))
                .font(CoveFont.ui(12, weight: .semibold))
                .foregroundStyle(session.isRunning ? SwiftUI.Color.coveT1 : SwiftUI.Color.coveT2)
            if session.isRunning, case let .running(tool, _) = phase, !tool.detail.isEmpty {
                Text(tool.detail)
                    .font(CoveFont.mono(11.5))
                    .foregroundStyle(SwiftUI.Color.coveT1)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if session.isRunning, let since = phase.since, isActive(phase) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.elapsed(from: since, to: context.date))
                        .font(CoveFont.mono(11))
                        .foregroundStyle(SwiftUI.Color.coveT3)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tasks: some View {
        let board = session.tracker.board
        return HStack(spacing: 8) {
            TaskCells(tasks: board.tasks)
            if let current = board.current {
                Text(current.subject)
                    .font(CoveFont.ui(12))
                    .foregroundStyle(SwiftUI.Color.coveT2)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            Text("\(board.completedCount)/\(board.tasks.count)")
                .font(CoveFont.mono(11))
                .foregroundStyle(SwiftUI.Color.coveT3)
                .monospacedDigit()
        }
    }

    private func headline(_ phase: AgentPhase) -> String {
        guard session.isRunning else {
            return session.exitCode.map { "已结束 · exit \($0)" } ?? "已结束"
        }
        switch phase {
        case .idle: return "Ready"
        case .thinking: return "Thinking"
        case let .running(tool, _): return tool.verb
        case .awaitingUser: return "等你回复"
        }
    }

    private func isActive(_ phase: AgentPhase) -> Bool {
        switch phase {
        case .thinking, .running: true
        case .idle, .awaitingUser: false
        }
    }

    /// 秒级精度即可：「3s」「1m 12s」「1h 04m」。
    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }
}
