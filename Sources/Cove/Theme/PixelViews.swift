import CoveCore
import SwiftUI

/// 会话在侧栏里的状态：只在打开着的会话上出现。
enum SessionState: Equatable {
    case working, waiting, idle, ended

    init(phase: AgentPhase, isRunning: Bool) {
        guard isRunning else { self = .ended; return }
        switch phase {
        case .thinking, .running: self = .working
        case .awaitingUser: self = .waiting
        case .idle: self = .idle
        }
    }
}

/// 侧栏状态点：5pt 实心方块。工作中是强调蓝，等你回复是唯一的暖色。
struct PixelDot: View {
    let state: SessionState

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 5, height: 5)
            .accessibilityLabel(label)
    }

    private var color: SwiftUI.Color {
        switch state {
        case .working: .coveAccent
        case .waiting: .coveAttn
        case .idle: .coveT3
        case .ended: .coveT3.opacity(0.4)
        }
    }

    private var label: String {
        switch state {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .idle: "Idle"
        case .ended: "Ended"
        }
    }
}

/// 工具栏里「正在干活」的步进指示：三格 4pt 方块，亮格逐格右移。
/// 帧率刻意压到 4fps——一格一格地跳本身就是像素感，平滑动画反而像装饰。
struct PixelStep: View {
    var active = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(active && index == lit ? SwiftUI.Color.coveAccent : SwiftUI.Color.coveAccentDim)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 任务进度小格（6pt）：完成实心，进行中淡底描边，待办只描边。
struct TaskCells: View {
    let tasks: [AgentTask]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tasks) { task in
                TaskCell(status: task.status)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(tasks.filter { $0.status == .completed }.count) of \(tasks.count) tasks done")
    }
}

struct TaskCell: View {
    let status: AgentTask.Status

    var body: some View {
        switch status {
        case .completed:
            Rectangle().fill(SwiftUI.Color.coveAccent).frame(width: 6, height: 6)
        case .inProgress:
            Rectangle().fill(SwiftUI.Color.coveAccentDim)
                .overlay(Rectangle().strokeBorder(SwiftUI.Color.coveAccent, lineWidth: 1))
                .frame(width: 6, height: 6)
        case .pending:
            Rectangle().strokeBorder(SwiftUI.Color.coveT3.opacity(0.7), lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}

/// 检查器顶部的分段进度条：每个任务一段，进行中那段是像素虚线。
struct SegmentedProgress: View {
    let tasks: [AgentTask]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tasks) { task in
                segment(task.status)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func segment(_ status: AgentTask.Status) -> some View {
        switch status {
        case .completed:
            Rectangle().fill(SwiftUI.Color.coveAccent)
        case .inProgress:
            // 6pt 实、3pt 空的点划，和状态点、任务格是同一套方块语汇。
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(0..<max(1, Int(proxy.size.width / 9)), id: \.self) { _ in
                        Rectangle().fill(SwiftUI.Color.coveAccent.opacity(0.8)).frame(width: 6)
                    }
                }
            }
            .clipped()
        case .pending:
            Rectangle().strokeBorder(SwiftUI.Color.coveLine, lineWidth: 1)
        }
    }
}

/// 分组标题：10.5pt 半粗、大写、字距 0.07em。
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(CoveFont.label)
            .tracking(0.7)
            .foregroundStyle(SwiftUI.Color.coveT3)
    }
}

/// 键帽：提示快捷键时用，等宽 10.5pt、浅底圆角。
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CoveFont.mono(10.5))
            .foregroundStyle(SwiftUI.Color.coveT2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(SwiftUI.Color.coveKey, in: RoundedRectangle(cornerRadius: 4))
    }
}
