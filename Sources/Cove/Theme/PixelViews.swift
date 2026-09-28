import CoveCore
import SwiftUI

/// 会话状态点：4×4pt 方块，不用圆点。运行中在两个相邻格之间步进，
/// 帧率刻意压到 4fps——步进的「一格一格」本身就是像素感，平滑动画反而像装饰。
struct PixelDot: View {
    enum State: Equatable { case idle, working, waiting, ended }
    let state: State

    var body: some View {
        switch state {
        case .working:
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate * 4) % 4
                Canvas { ctx, _ in
                    // 两格一组，亮格绕 2×2 的四个位置走一圈：▖▘▝▗。
                    let spots = [CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 5)]
                    for (index, spot) in spots.enumerated() {
                        let rect = CGRect(origin: spot, size: CGSize(width: 4, height: 4))
                        ctx.fill(Path(rect), with: .color(index == frame ? .coveHarbor : .coveHarbor.opacity(0.22)))
                    }
                }
                .frame(width: 9, height: 9)
            }
        default:
            Rectangle()
                .fill(color)
                .frame(width: 5, height: 5)
                .frame(width: 9, height: 9)
        }
    }

    private var color: Color {
        switch state {
        case .waiting: .coveLantern
        case .ended: .coveInkMuted.opacity(0.35)
        case .idle, .working: .coveInkMuted.opacity(0.6)
        }
    }
}

extension PixelDot.State {
    init(phase: AgentPhase, isRunning: Bool) {
        guard isRunning else { self = .ended; return }
        switch phase {
        case .idle: self = .idle
        case .thinking, .running: self = .working
        case .awaitingUser: self = .waiting
        }
    }
}

/// 任务进度格：完成填实，进行中描边加内点，待办只描一道淡边。
struct PixelProgress: View {
    let tasks: [AgentTask]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tasks) { task in
                cell(task.status)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(tasks.filter { $0.status == .completed }.count) of \(tasks.count) tasks done")
    }

    @ViewBuilder private func cell(_ status: AgentTask.Status) -> some View {
        switch status {
        case .completed:
            Rectangle().fill(Color.coveHarbor).frame(width: 6, height: 6)
        case .inProgress:
            Rectangle().strokeBorder(Color.coveHarbor, lineWidth: 1)
                .overlay(Rectangle().fill(Color.coveHarbor).frame(width: 2, height: 2))
                .frame(width: 6, height: 6)
        case .pending:
            Rectangle().strokeBorder(Color.coveInkMuted.opacity(0.4), lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}

/// 分组标签：SF Mono 10pt 大写、加字距。
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(CoveFont.label)
            .tracking(0.8)
            .foregroundStyle(Color.coveInkMuted)
    }
}

/// App 内的图标，和 scripts/make_icon.py 里的 ART 是同一张网格（改一处要同步另一处）。
struct PixelLogo: View {
    static let art = [
        "................",
        "................",
        ".....oooooo.....",
        "....oooooooo....",
        "...ooo....ooo...",
        "..ooo...........",
        "..oo........##..",
        "..oo.~~.....##..",
        "..oo...~~...##..",
        "..oo........##..",
        "..ooo...........",
        "...ooo....ooo...",
        "....oooooooo....",
        ".....oooooo.....",
        "................",
        "................",
    ]

    var cell: CGFloat = 4

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in Self.art.enumerated() {
                for (x, char) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(color(char)))
                }
            }
        }
        .frame(width: cell * 16, height: cell * 16)
        .clipShape(RoundedRectangle(cornerRadius: cell * 16 * 0.225, style: .continuous))
        .accessibilityHidden(true)
    }

    private func color(_ char: Character) -> Color {
        switch char {
        case "o": Color(nsColor: NSColor(hex: 0xF3EEE3))
        case "~": Color(nsColor: NSColor(hex: 0x4E79A6))
        case "#": Color(nsColor: NSColor(hex: 0x9FC3E6))
        default: Color(nsColor: NSColor(hex: 0x1C334D))
        }
    }
}
