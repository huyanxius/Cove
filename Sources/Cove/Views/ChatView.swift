import AppKit
import CoveCore
import SwiftUI

/// Cove 界面的中栏：一列对话。只画 `ChatLog` 里有的东西，不自己推断状态。
///
/// 版式跟 docs/DESIGN.md：正文用系统字体，路径、命令、代码用等宽；一个强调色；
/// 只有「等你批准」用暖色 `attn`，因为那是唯一需要把人拉回来的时刻。
struct ChatView: View {
    let session: LiveSession
    let chat: ChatBridge

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chat.log.items) { item in
                        ChatRow(item: item, session: session, chat: chat)
                            .padding(.top, spacing(before: item))
                            .id(item.id)
                    }
                    if let draft = chat.log.draft, !draft.isEmpty {
                        StreamingReply(draft: draft, chunks: chat.draftChunks).padding(.top, 18)
                    } else if chat.log.isWorking && chat.log.pendingPermission == nil {
                        WorkingLine(phase: session.tracker.phase).padding(.top, 18)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.log.items.count) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: chat.log.draft) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
        .overlay {
            if chat.log.items.isEmpty && !chat.log.isWorking {
                EmptyChat(cwd: session.cwd, running: session.isRunning)
            }
        }
        .background(SwiftUI.Color.coveBg)
    }

    private static let bottom = "bottom"

    /// 条目之间的间距决定层次：连续的工具调用挤成一组，组和正文之间、换人说话时留大空。
    private func spacing(before item: ChatItem) -> CGFloat {
        guard item.id > 0 else { return 0 }
        let previous = chat.log.items[item.id - 1].kind
        switch (previous, item.kind) {
        case (.tool, .tool): return 3
        case (_, .prompt), (.prompt, _): return 28
        default: return 18
        }
    }
}

private struct ChatRow: View {
    let item: ChatItem
    let session: LiveSession
    let chat: ChatBridge

    var body: some View {
        switch item.kind {
        case let .prompt(text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .font(CoveFont.ui(14))
                    .lineSpacing(5)
                    .foregroundStyle(SwiftUI.Color.coveT1)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(SwiftUI.Color.coveSelect, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case let .reply(text):
            ReplyBlock(text: text)
        case let .tool(call):
            ToolLine(call: call) { path in session.openDiff(path) }
        case let .permission(request, answer):
            PermissionCard(request: request, answer: answer) { allow in chat.answer(request, allow: allow) }
        case let .notice(text):
            Text(text)
                .font(CoveFont.ui(12))
                .foregroundStyle(SwiftUI.Color.coveT3)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 一条回复，悬停时右上角出现「复制」：复制的是原始 Markdown，不是排版后的文字。
private struct ReplyBlock: View {
    let text: String
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        MarkdownText(text: text)
            .overlay(alignment: .topTrailing) {
                if hovering || copied {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(SwiftUI.Color.coveT2)
                            .frame(width: 24, height: 22)
                            .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(SwiftUI.Color.coveRaisedLine))
                    }
                    .buttonStyle(.plain)
                    .help("复制原文（Markdown）")
                    .offset(x: 8, y: -6)
                }
            }
            .onHover { hovering = $0 }
    }
}

/// 一次工具调用：状态方块 + 动词 + 对象。文件类工具做完后可以点开 diff。
struct ToolLine: View {
    let call: ToolCall
    let openDiff: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(Self.verb(call.activity))
                .font(CoveFont.ui(12))
                .foregroundStyle(SwiftUI.Color.coveT3)
            Text(call.activity.detail)
                .font(CoveFont.mono(11.5))
                .foregroundStyle(SwiftUI.Color.coveT2)
                .lineLimit(1)
                .truncationMode(.middle)
            if call.state == .failed {
                Text("失败").font(CoveFont.ui(11.5)).foregroundStyle(SwiftUI.Color.coveDel)
            }
            if let path = call.filePath, call.state == .done, ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(call.activity.toolName) {
                Button("查看改动") { openDiff(path) }
                    .buttonStyle(.link)
                    .font(CoveFont.ui(11.5))
            }
        }
        .padding(.leading, 2)
    }

    /// 对话里用中文动词；`ToolActivity` 的英文动词留给状态条。
    static func verb(_ activity: ToolActivity) -> String {
        switch activity.verb {
        case "Running": "运行"
        case "Editing": "编辑"
        case "Writing": "写入"
        case "Reading": "读取"
        case "Searching": "搜索"
        case "Searching the web": "搜索网页"
        case "Fetching": "抓取"
        case "Delegating": "委派"
        case "Planning": "规划"
        case "Using skill": "技能"
        default: "调用"
        }
    }

    private var color: SwiftUI.Color {
        switch call.state {
        case .running: .coveAccent
        case .done: .coveT3
        case .failed: .coveDel
        }
    }
}

private struct PermissionCard: View {
    let request: PermissionRequest
    let answer: PermissionAnswer?
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Rectangle().fill(answer == nil ? SwiftUI.Color.coveAttn : SwiftUI.Color.coveT3).frame(width: 6, height: 6)
                Text(answer == nil ? "Claude 想要使用 \(request.toolName)" : "\(request.toolName)")
                    .font(CoveFont.ui(13, weight: .medium))
                    .foregroundStyle(SwiftUI.Color.coveT1)
                Spacer()
                if let answer {
                    Text(answer == .allowed ? "已允许" : "已拒绝")
                        .font(CoveFont.ui(11.5))
                        .foregroundStyle(SwiftUI.Color.coveT3)
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(CoveFont.mono(12))
                    .foregroundStyle(SwiftUI.Color.coveT2)
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(SwiftUI.Color.coveKey, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if answer == nil {
                HStack(spacing: 8) {
                    Spacer()
                    Button("拒绝") { decide(false) }
                    Button("允许") { decide(true) }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(answer == nil ? SwiftUI.Color.coveAttn.opacity(0.55) : SwiftUI.Color.coveRaisedLine))
    }

    /// 让人判断「批不批」最需要看的那一项：命令、路径或网址；都没有就用 CLI 的一句话说明。
    private var detail: String {
        let input = request.input
        return input["command"] ?? input["file_path"] ?? input["notebook_path"] ?? input["url"]
            ?? input["pattern"] ?? request.summary
    }
}

private struct WorkingLine: View {
    let phase: AgentPhase

    var body: some View {
        HStack(spacing: 8) {
            CoffeeLoader(size: 18)
            Text(label)
                .font(CoveFont.ui(12.5))
                .foregroundStyle(SwiftUI.Color.coveT3)
        }
    }

    private var label: String {
        if case let .running(activity, _) = phase { return "\(ToolLine.verb(activity)) \(activity.detail)" }
        return "思考中…"
    }
}

private struct EmptyChat: View {
    let cwd: String
    let running: Bool

    var body: some View {
        VStack(spacing: 10) {
            if running, let cup = Brand.cupMark {
                Image(nsImage: cup).resizable().interpolation(.high).scaledToFit().frame(width: 64, height: 66)
            }
            Text(running ? "在 \((cwd as NSString).lastPathComponent) 里开始" : "会话已结束")
                .font(CoveFont.display(20))
                .foregroundStyle(SwiftUI.Color.coveT1)
            Text(running ? "输入 / 查看可用的命令和技能" : "双击顶部状态可以恢复")
                .font(CoveFont.ui(12.5))
                .foregroundStyle(SwiftUI.Color.coveT3)
        }
        .allowsHitTesting(false)
    }
}

/// 正在流式输出的回复：新到的字从模糊渐变到清晰（`BlurInRenderer`），已落定的照常排版。
///
/// 做法：最后 `BlurIn.duration` 秒内到达的那几批字是「新字」，只要它们都落在最后一个块的
/// 末尾，这个块就拆成「旧字 + 新字」两段 Text 拼接，新字挂上到达时间，由渲染器按时间
/// 画出模糊和透明度。新字跨了块边界（比如刚好到了空行）就这一帧不做效果，不影响排版。
private struct StreamingReply: View {
    let draft: String
    let chunks: [ChatBridge.DraftChunk]

    var body: some View {
        if #available(macOS 15, *) {
            TimelineView(.animation) { context in
                MarkdownText(text: draft, fresh: fresh(at: context.date))
                    .textRenderer(BlurInRenderer(now: context.date))
            }
        } else {
            MarkdownText(text: draft)
        }
    }

    /// 还在渐显中的那几批字，拆成单个字、到达时间逐字错开，一批字从左到右依次浮现，
    /// 而不是整块同时出现。错开的总时长有上限，大段文字一次到达时也不会拖太久。
    private func fresh(at now: Date) -> [ChatBridge.DraftChunk] {
        let window = BlurIn.duration + BlurIn.maxStagger
        let recent = chunks.reversed().prefix { now.timeIntervalSince($0.arrived) < window }.reversed()
        return recent.flatMap { chunk -> [ChatBridge.DraftChunk] in
            let characters = Array(chunk.text)
            let step = min(BlurIn.perCharacter, BlurIn.maxStagger / Double(max(characters.count, 1)))
            return characters.enumerated().map { index, character in
                ChatBridge.DraftChunk(text: String(character), arrived: chunk.arrived.addingTimeInterval(Double(index) * step))
            }
        }
    }
}

enum BlurIn {
    static let duration: TimeInterval = 0.6
    static let radius: CGFloat = 6
    /// 同一批字之间逐字错开的间隔，以及一批字错开的总上限。
    static let perCharacter: TimeInterval = 0.025
    static let maxStagger: TimeInterval = 0.35
}

@available(macOS 15, *)
private struct ArrivalAttribute: TextAttribute {
    let arrived: Date
}

@available(macOS 15, *)
private struct BlurInRenderer: TextRenderer {
    let now: Date

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let arrival = run[ArrivalAttribute.self] else {
                    context.draw(run)
                    continue
                }
                let progress = min(max(now.timeIntervalSince(arrival.arrived) / BlurIn.duration, 0), 1)
                let eased = 1 - pow(1 - progress, 3)
                var copy = context
                copy.opacity = eased
                if eased < 1 { copy.addFilter(.blur(radius: (1 - eased) * BlurIn.radius)) }
                copy.draw(run)
            }
        }
    }
}

/// 回复正文：块级结构由 `MarkdownBlocks` 切，行内语法交给系统 Markdown。
struct MarkdownText: View {
    let text: String
    /// 流式输出时刚到的几批字，按顺序排在 `text` 末尾；为空就是普通的静态正文。
    var fresh: [ChatBridge.DraftChunk] = []

    var body: some View {
        let blocks = MarkdownBlocks.split(text)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case let .paragraph(body) where index == blocks.count - 1 && !fresh.isEmpty:
                    fading(body, inline: true)
                        .font(CoveFont.ui(14.5))
                        .lineSpacing(7)
                        .foregroundStyle(SwiftUI.Color.coveBody)
                case let .paragraph(body):
                    Text(Self.inline(body))
                        .font(CoveFont.ui(14.5))
                        .lineSpacing(7)
                        .foregroundStyle(SwiftUI.Color.coveBody)
                case let .heading(body):
                    Text(Self.inline(body))
                        .font(CoveFont.ui(15.5, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color.coveT1)
                        .padding(.top, 6)
                case let .code(_, body):
                    ScrollView(.horizontal, showsIndicators: false) {
                        (index == blocks.count - 1 && !fresh.isEmpty ? fading(body, inline: false) : Text(body))
                            .font(CoveFont.mono(12.5))
                            .foregroundStyle(SwiftUI.Color.coveT1)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SwiftUI.Color.coveKey, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        // 可选中的文字在 macOS 上换成另一套控件绘制，会绕过 `BlurInRenderer`，渐显就没了。
        // 流式中的那段本来只存在一瞬间，先不让选；落定成正式回复后照常可选。
        .modifier(SelectableIf(fresh.isEmpty))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 把块拆成「旧字 + 各批新字」拼接的 Text。新字不在块尾时整块按旧字处理。
    private func fading(_ body: String, inline: Bool) -> Text {
        let tail = fresh.map(\.text).joined()
        guard #available(macOS 15, *), !tail.isEmpty, body.hasSuffix(tail) else {
            return inline ? Text(Self.inline(body)) : Text(body)
        }
        let settled = String(body.dropLast(tail.count))
        // 新字只存在零点几秒，按纯文本显示；落定后并进旧字，行内 Markdown 才生效。
        var result = inline ? Text(Self.inline(settled)) : Text(settled)
        for chunk in fresh {
            result = result + Text(chunk.text).customAttribute(ArrivalAttribute(arrived: chunk.arrived))
        }
        return result
    }

    static func inline(_ text: String) -> AttributedString {
        InlineMarkdown.attributed(text)
    }
}

private struct SelectableIf: ViewModifier {
    let enabled: Bool
    init(_ enabled: Bool) { self.enabled = enabled }

    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}
