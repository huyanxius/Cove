import CoveCore
import SwiftUI

/// 右下角的用量：5 小时额度、7 天额度、上下文占用三只圆环，下面一行当前模型。
/// Claude 用 statusLine，Codex 用 app-server；数据未到时圆环显示空值。
struct UsagePanel: View {
    let usage: UsageSnapshot?
    /// 当前会话的 CLI；Antigravity 暂无用量来源。
    var cli: CLIKind? = .claude
    var surface: Surface? = .chat

    var body: some View {
        if cli == .agy || (cli == .codex && surface != .chat) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.0percent").font(.system(size: 11))
                Text(cli == .codex ? "Codex 终端模式暂未接入用量" : "Antigravity 暂不提供用量数据")
                    .font(CoveFont.ui(11.5))
            }
            .foregroundStyle(SwiftUI.Color.coveT3)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            rings
        }
    }

    private var rings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ring("5h", usage?.fiveHourPercent, resets: usage?.fiveHourResetsAt)
                Spacer(minLength: 4)
                ring("7d", usage?.sevenDayPercent, resets: usage?.sevenDayResetsAt)
                Spacer(minLength: 4)
                ring("上下文", usage?.contextPercent, resets: nil)
            }
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.system(size: 10))
                Text(usage?.modelName ?? "等待 \(cli?.displayName ?? "CLI") 报告用量")
                    .font(CoveFont.mono(11))
                    .lineLimit(1)
            }
            .foregroundStyle(SwiftUI.Color.coveT2)
        }
    }

    private func ring(_ label: String, _ percent: Double?, resets: Date?) -> some View {
        VStack(spacing: 4) {
            UsageRing(percent: percent)
                .frame(width: 46, height: 46)
            Text(label).font(CoveFont.ui(10.5, weight: .medium)).foregroundStyle(SwiftUI.Color.coveT3)
        }
        .help(resets.map { "重置于 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? label)
    }
}

struct UsageRing: View {
    let percent: Double?

    var body: some View {
        let value = min(max((percent ?? 0) / 100, 0), 1)
        ZStack {
            Circle().stroke(SwiftUI.Color.coveLine, lineWidth: 5)
            Circle()
                .trim(from: 0, to: value)
                .stroke(color(value), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(CoveFont.mono(10.5, weight: .medium))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .monospacedDigit()
        }
        .animation(.easeOut(duration: 0.4), value: value)
    }

    /// 过了八成换成提醒色，其余一律强调蓝。
    private func color(_ value: Double) -> SwiftUI.Color {
        value >= 0.8 ? .coveAttn : .coveAccent
    }
}
