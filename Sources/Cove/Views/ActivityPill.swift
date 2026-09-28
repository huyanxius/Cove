import CoveCore
import SwiftUI

/// 中栏顶部的一行：这个 Agent 此刻在干什么、干了多久、任务做到第几步、改了多少行。
struct StatusStrip: View {
    let session: LiveSession
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PixelDot(state: PixelDot.State(phase: session.tracker.phase, isRunning: session.isRunning))
            activity
            Spacer(minLength: 16)
            tasks
            lines
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.coveCanvas)
    }

    @ViewBuilder private var activity: some View {
        if !session.isRunning {
            HStack(spacing: 8) {
                Text("Session ended").foregroundStyle(Color.coveInk)
                if let code = session.exitCode {
                    Text("exit \(code)").font(CoveFont.mono(11)).foregroundStyle(Color.coveInkMuted)
                }
                Button("Resume", action: onRestart)
                    .buttonStyle(.link)
                    .foregroundStyle(Color.coveHarbor)
            }
            .font(.system(size: 13, weight: .medium))
        } else {
            let phase = session.tracker.phase
            HStack(spacing: 8) {
                Text(headline(phase))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.coveInk)
                if case let .running(tool, _) = phase, !tool.detail.isEmpty {
                    Text(tool.detail)
                        .font(CoveFont.mono(12))
                        .foregroundStyle(Color.coveInkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let since = phase.since, isActive(phase) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: since, to: context.date))
                            .font(CoveFont.mono(11))
                            .foregroundStyle(Color.coveInkMuted.opacity(0.8))
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var tasks: some View {
        let board = session.tracker.board
        if !board.tasks.isEmpty {
            HStack(spacing: 8) {
                if let current = board.current {
                    Text(current.subject)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coveInkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                PixelProgress(tasks: board.tasks)
                Text("\(board.completedCount)/\(board.tasks.count)")
                    .font(CoveFont.mono(11))
                    .foregroundStyle(Color.coveInkMuted)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder private var lines: some View {
        let tracker = session.tracker
        if tracker.linesAdded + tracker.linesRemoved > 0 {
            HStack(spacing: 6) {
                Text("+\(tracker.linesAdded)").foregroundStyle(Color.coveAdded)
                Text("−\(tracker.linesRemoved)").foregroundStyle(Color.coveRemoved)
            }
            .font(CoveFont.mono(11))
            .monospacedDigit()
            .padding(.leading, 6)
        }
    }

    private func headline(_ phase: AgentPhase) -> String {
        switch phase {
        case .idle: "Ready"
        case .thinking: "Thinking"
        case let .running(tool, _): tool.verb
        case .awaitingUser: "Waiting for you"
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
