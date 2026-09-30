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
    @AppStorage("readingFont") private var readingFont = ReadingStyle.default.family
    @AppStorage("readingSize") private var readingSize = ReadingStyle.default.size
    @AppStorage("readingSpacing") private var readingSpacing = ReadingStyle.default.lineSpacing

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
                EmptyChat(cwd: session.cwd, running: session.isRunning,
                          connecting: session.isRunning && !chat.connected ? session.cli.displayName : nil)
            }
        }
        .background(SwiftUI.Color.coveBg)
        .environment(\.readingStyle, ReadingStyle(family: readingFont, size: readingSize, lineSpacing: readingSpacing))
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
    @Environment(\.readingStyle) private var style

    var body: some View {
        switch item.kind {
        case let .prompt(text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .font(style.font(scale: 0.97))
                    .lineSpacing(style.lineSpacing * 0.7)
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
            PermissionCard(request: request, answer: answer, agent: session.cli == .claude ? "Claude" : session.cli.displayName) { allow in
                chat.answer(request, allow: allow)
            }
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
    let agent: String
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Rectangle().fill(answer == nil ? SwiftUI.Color.coveAttn : SwiftUI.Color.coveT3).frame(width: 6, height: 6)
                Text(answer == nil ? "\(agent) 想要\(Self.action(request))" : Self.action(request))
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

    /// 卡片标题里的动作：命令就是「运行命令」，改文件就是「修改文件」，其余写工具名。
    static func action(_ request: PermissionRequest) -> String {
        switch request.toolName {
        case "Bash": "运行命令"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "修改文件"
        case "WebFetch": "访问网页"
        default: "使用 \(request.toolName)"
        }
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
    /// 非 nil 时进程还没吐出第一行：显示「正在连接 xx」。
    let connecting: String?

    var body: some View {
        VStack(spacing: 10) {
            if running, let cup = Brand.cupMark {
                Image(nsImage: cup).resizable().interpolation(.high).scaledToFit().frame(width: 64, height: 66)
            }
            Text(running ? "在 \((cwd as NSString).lastPathComponent) 里开始" : "会话已结束")
                .font(CoveFont.display(20))
                .foregroundStyle(SwiftUI.Color.coveT1)
            Text(connecting.map { "正在连接 \($0)…可以先输入，连上后自动发出" }
                 ?? (running ? "输入 / 查看可用的命令和技能" : "双击顶部状态可以恢复"))
                .font(CoveFont.ui(12.5))
                .foregroundStyle(SwiftUI.Color.coveT3)
        }
        .allowsHitTesting(false)
    }
}
