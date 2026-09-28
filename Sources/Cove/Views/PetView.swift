import CoveCore
import SwiftUI

/// 右下角的 Claude 小螃蟹：一个跟着 Agent 状态变表情的像素宠物，外加这次会话的工作量。
///
/// 做法借鉴 Clawd on Desk（每个状态一组动画，由 Agent 事件驱动切换），但画面是 Cove 自己的
/// 像素画——Clawd 的素材是 AGPL，不能搬进 MIT 仓库。帧用字符网格描述，Canvas 逐格绘制。
struct PetPanel: View {
    let session: LiveSession?
    let usage: UsageSnapshot?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelCrab(mood: mood)
                .frame(width: 88, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(CoveFont.ui(12, weight: .medium))
                    .foregroundStyle(SwiftUI.Color.coveT1)
                stat("工作", workTime)
                stat("Token", tokens)
                stat("估算", cost)
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(CoveFont.ui(11)).foregroundStyle(SwiftUI.Color.coveT3).frame(width: 34, alignment: .leading)
            Text(value).font(CoveFont.mono(11)).foregroundStyle(SwiftUI.Color.coveT2).monospacedDigit()
        }
    }

    private var mood: PixelCrab.Mood {
        guard let session else { return .sleeping }
        switch SessionState(phase: session.tracker.phase, isRunning: session.isRunning) {
        case .working:
            if case .thinking = session.tracker.phase { return .thinking }
            return .working
        case .waiting: return .waving
        case .idle: return .idle
        case .ended: return .sleeping
        }
    }

    private var caption: String {
        switch mood {
        case .working: "干活中"
        case .thinking: "想一想……"
        case .waving: "等你回复"
        case .idle: "待命"
        case .sleeping: "打盹"
        }
    }

    private var workTime: String {
        guard let seconds = usage?.apiDuration else { return "—" }
        return ActivityPill.elapsed(from: Date(timeIntervalSinceNow: -seconds), to: .now)
    }

    private var tokens: String {
        guard let usage, let input = usage.inputTokens else { return "—" }
        return "\(Self.compact(input)) ↓  \(Self.compact(usage.outputTokens ?? 0)) ↑"
    }

    /// 按 API key 单价估算；CLI 自己报了累计花费就用它，否则按模型单价算。
    private var cost: String {
        guard let usage else { return "—" }
        if let reported = usage.reportedCostUSD { return String(format: "$%.2f", reported) }
        guard let model = usage.modelID,
              let estimate = PriceTable.estimate(model: model, input: usage.inputTokens ?? 0, output: usage.outputTokens ?? 0,
                                                 cacheRead: usage.cacheReadTokens ?? 0, cacheWrite: usage.cacheWriteTokens ?? 0)
        else { return "—" }
        return String(format: "$%.2f", estimate)
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

/// Claude 小螃蟹 Clawd：形状逐格取自 Claude Code 启动画面里那只用半格块字符拼成的吉祥物
/// （ ▐▛███▜▌ / ▝▜█████▛▘ /  ▘▘ ▝▝ ），每个字符拆成 2×2 像素，得到 18×5 的网格；终端字符
/// 竖长，所以像素格也画成竖长（高 ≈ 宽 × 1.7）。
///
/// 动作是连续的：按显示刷新率拿到时间 t，身体的起伏、压扁拉长、倾斜、眼珠朝向、腿和手的
/// 摆动都是 t 的函数，而不是几张图轮播——像素是方的，运动是顺的，灵动感来自这里。
struct PixelCrab: View {
    enum Mood: Equatable { case working, thinking, waving, idle, sleeping }
    let mood: Mood

    private static let shell = SwiftUI.Color(nsColor: NSColor(hex: 0xD97757))
    private static let eye = SwiftUI.Color(nsColor: NSColor(hex: 0x2A2925))
    private static let aspect: CGFloat = 1.7

    /// 身体（不含眼睛、手、腿，它们单独画才能各自动）。
    private static let torso = [
        "...OOOOOOOOOOOO...",
        "...OOOOOOOOOOOO...",
        "...OOOOOOOOOOOO...",
        "...OOOOOOOOOOOO...",
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(&ctx, size: size, t: t) }
        }
        .accessibilityLabel("Claude 小螃蟹")
    }

    // MARK: - 动作参数

    private struct Pose {
        var lift: CGFloat = 0          // 离地高度（像素格）
        var squash: CGFloat = 0        // >0 压扁，<0 拉长
        var tilt: Double = 0           // 倾斜角（度）
        var shiftX: CGFloat = 0        // 侧行位移（像素格）
        var look = CGPoint.zero        // 眼珠偏移（像素格）
        var eyesShut = false
        var legPhase = 0               // 0/1 两组腿交替
        var leftArmUp: CGFloat = 0     // 手抬起的格数
        var rightArmUp: CGFloat = 0
    }

    /// 由时间算出的伪随机数，同一个时间段内稳定，用来决定何时眨眼、往哪看。
    private static func noise(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    private func pose(at t: Double) -> Pose {
        var p = Pose()
        let blinkSlot = Int(t / 3.2)
        let blinking = t - Double(blinkSlot) * 3.2 < 0.13 && Self.noise(blinkSlot) > 0.25
        switch mood {
        case .idle:
            p.squash = 0.04 * sin(t * 2.6)
            let lookSlot = Int(t / 2.2)
            p.look = CGPoint(x: [-1, 0, 1, 0][Int(Self.noise(lookSlot) * 4) % 4], y: 0)
            p.eyesShut = blinking
            // 每 8 秒侧行一小段：先挪过去，停一下再挪回来。
            let walk = t.truncatingRemainder(dividingBy: 8)
            if walk < 1.6 {
                p.shiftX = CGFloat(sin(walk / 1.6 * .pi)) * 3
                p.legPhase = Int(t * 10) % 2
                p.lift = abs(CGFloat(sin(t * 20))) * 0.25
            }
        case .working:
            let hop = abs(sin(t * 6.5))
            p.lift = CGFloat(hop) * 1.4
            p.squash = hop < 0.25 ? 0.12 * (1 - hop / 0.25) : -0.06 * hop
            p.legPhase = Int(t * 12) % 2
            p.leftArmUp = CGFloat(max(0, sin(t * 13)))
            p.rightArmUp = CGFloat(max(0, -sin(t * 13)))
            p.look = CGPoint(x: 1, y: 0)
            p.eyesShut = blinking
        case .thinking:
            p.tilt = sin(t * 1.8) * 5
            p.squash = 0.03 * sin(t * 1.8)
            p.look = CGPoint(x: sin(t * 0.9) > 0 ? 1 : -1, y: -1)
            p.eyesShut = blinking
        case .waving:
            let hop = max(0, sin(t * 5))
            p.lift = CGFloat(hop) * 1.2
            p.squash = hop < 0.1 ? 0.1 : -0.04
            p.leftArmUp = 2 + CGFloat(sin(t * 14)) * 0.8
            p.look = CGPoint(x: 0, y: 0)
            p.eyesShut = blinking
        case .sleeping:
            p.squash = 0.07 + 0.05 * sin(t * 1.4)
            p.eyesShut = true
        }
        return p
    }

    // MARK: - 绘制

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let p = pose(at: t)
        // 24 列 × 9 行的舞台：身体居中，上方留给效果，下方留给腿和影子。
        let w = min(size.width / 24, size.height / (9 * Self.aspect))
        let h = w * Self.aspect
        let groundY = size.height - h * 0.6
        let centerX = size.width / 2 + p.shiftX * w

        // 影子：离地越高越小越淡。
        let shadowWidth = w * (13 - p.lift * 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: centerX - shadowWidth / 2, y: groundY - h * 0.15,
                                         width: shadowWidth, height: h * 0.35)),
                 with: .color(.black.opacity(0.10 - Double(p.lift) * 0.02)))

        var body = ctx
        body.translateBy(x: centerX, y: groundY - h - p.lift * h)
        body.rotate(by: .degrees(p.tilt))
        body.scaleBy(x: 1 + p.squash * 0.6, y: 1 - p.squash)

        func cell(_ col: CGFloat, _ row: CGFloat, _ color: SwiftUI.Color, in context: GraphicsContext) {
            // 以身体底边中点为原点：列 0…17，行从上往下，第 4 行是腿。
            let rect = CGRect(x: (col - 9) * w, y: (row - 4) * h, width: w + 0.3, height: h + 0.3)
            context.fill(Path(rect), with: .color(color))
        }

        // 腿（在身体下面一行），两组交替抬起。
        let legs: [CGFloat] = p.legPhase == 0 ? [4, 6, 11, 13] : [5, 7, 10, 12]
        for col in legs { cell(col, 4, Self.shell, in: body) }
        // 躯干。
        for (y, row) in Self.torso.enumerated() {
            for (x, char) in row.enumerated() where char == "O" { cell(CGFloat(x), CGFloat(y), Self.shell, in: body) }
        }
        // 手：身体两侧第 2 行各两格，抬起时往上挪。
        cell(1, 2 - p.leftArmUp, Self.shell, in: body); cell(2, 2 - p.leftArmUp, Self.shell, in: body)
        cell(15, 2 - p.rightArmUp, Self.shell, in: body); cell(16, 2 - p.rightArmUp, Self.shell, in: body)
        // 眼睛：闭眼时是一道细线。
        for col: CGFloat in [5, 12] {
            if p.eyesShut {
                let rect = CGRect(x: (col - 9 + p.look.x * 0.5) * w, y: (1 - 4) * h + h * 0.55, width: w, height: h * 0.18)
                body.fill(Path(rect), with: .color(Self.eye))
            } else {
                cell(col + p.look.x * 0.5, 1 + p.look.y * 0.4, Self.eye, in: body)
            }
        }

        drawEffects(&ctx, t: t, w: w, h: h, head: CGPoint(x: centerX, y: groundY - h * 5 - p.lift * h))
    }

    /// 头顶效果：火花往上飘、思考的点依次亮、感叹号弹、z 斜着飘走。
    private func drawEffects(_ ctx: inout GraphicsContext, t: Double, w: CGFloat, h: CGFloat, head: CGPoint) {
        func dot(_ x: CGFloat, _ y: CGFloat, _ color: SwiftUI.Color, _ alpha: Double, size: CGFloat = 1) {
            ctx.fill(Path(CGRect(x: head.x + x * w, y: head.y + y * h * 0.6, width: w * size, height: w * size)),
                     with: .color(color.opacity(alpha)))
        }
        switch mood {
        case .working:
            for i in 0..<3 {
                let phase = (t * 1.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                dot(CGFloat(4 + i * 2) + CGFloat(sin(phase * 6 + Double(i))) * 0.6, CGFloat(-phase * 3), .coveAccent, 1 - phase, size: 0.8)
            }
        case .thinking:
            for i in 0..<3 {
                let lit = (Int(t * 3) % 4) > i
                dot(CGFloat(5 + i * 2), -1 - CGFloat(i) * 0.4, .coveAccent, lit ? 1 : 0.25, size: 0.9)
            }
        case .waving:
            let bounce = CGFloat(abs(sin(t * 5))) * 0.8
            ctx.fill(Path(CGRect(x: head.x + 8 * w, y: head.y - (1.4 + bounce) * h, width: w * 0.9, height: h * 1.1)),
                     with: .color(.coveAttn))
            ctx.fill(Path(CGRect(x: head.x + 8 * w, y: head.y - bounce * h, width: w * 0.9, height: w * 0.9)),
                     with: .color(.coveAttn))
        case .sleeping:
            for i in 0..<2 {
                let phase = (t * 0.35 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                let text = Text("z").font(.system(size: 7 + phase * 5, weight: .bold, design: .rounded))
                    .foregroundColor(SwiftUI.Color.coveT3.opacity(1 - phase))
                ctx.draw(text, at: CGPoint(x: head.x + (5 + phase * 4) * w, y: head.y - phase * h * 2.5))
            }
        case .idle:
            break
        }
    }
}
