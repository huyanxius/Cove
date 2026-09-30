import CoveCore
import SwiftUI

/// 一个文件相对 HEAD 的差异。`revision` 是 Agent 对这个文件的编辑次数，
/// 它一变就重新取 diff，所以 Agent 边改这里边跟着刷新。
struct DiffView: View {
    let path: String
    let cwd: String
    let revision: Int
    let delta: LineDelta?
    /// 把打包好的行内评论交给会话；为 nil（会话已结束）时不显示评论入口。
    var sendReview: ((String) -> Void)?

    @State private var result: Git.DiffResult?
    /// 行内评论：键是 diff 里的行序号。写了字才算，空的在发送时丢掉。
    @State private var comments: [Int: String] = [:]
    @State private var editing: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.coveLine).frame(height: 1)
            content
            if !filledComments.isEmpty, sendReview != nil { reviewBar }
        }
        .background(Color.coveBg)
        .task(id: "\(path)#\(revision)") { result = await Git.diff(path: path) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(CoveFont.ui(14, weight: .semibold))
                .foregroundStyle(Color.coveT1)
            Text(displayDirectory)
                .font(CoveFont.mono(11))
                .foregroundStyle(Color.coveT3)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if let delta {
                Text("+\(delta.added)").foregroundStyle(Color.coveAdd).font(CoveFont.mono(11))
                Text("−\(delta.removed)").foregroundStyle(Color.coveDel).font(CoveFont.mono(11))
            }
            Button {
                Task { result = await Git.diff(path: path) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新读取")
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("用默认编辑器打开")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        switch result {
        case nil:
            CoffeeLoader(size: 56, caption: "正在读取改动…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unchanged:
            message("与 HEAD 无差异", detail: "改动可能已提交，或已被还原。")
        case .notRepository:
            message("文件不存在", detail: "它可能已被移动或删除。")
        case let .failed(reason):
            message("无法读取差异", detail: reason)
        case let .outsideRepository(lines):
            VStack(spacing: 0) {
                Text("未纳入版本控制 · 显示文件当前内容")
                    .font(CoveFont.ui(11.5))
                    .foregroundStyle(Color.coveT3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.coveAccentDim.opacity(0.5))
                lineList(lines)
            }
        case let .diff(lines):
            lineList(lines)
        }
    }

    /// 从左上角开始排；内容比视口窄时每行仍铺满整宽，长行横向滚动。
    private func lineList(_ lines: [DiffLine]) -> some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if line.kind != .meta || line.text.hasPrefix("\\") {
                            DiffRow(line: line, commentable: sendReview != nil && [.added, .removed, .context].contains(line.kind),
                                    hasComment: comments[index] != nil) {
                                if comments[index] == nil { comments[index] = "" }
                                editing = index
                            }
                            if editing == index || !(comments[index] ?? "").isEmpty {
                                CommentEditor(text: Binding(get: { comments[index] ?? "" }, set: { comments[index] = $0 }),
                                              focused: editing == index,
                                              done: { editing = nil },
                                              remove: { comments[index] = nil; editing = nil })
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private var filledComments: [(Int, String)] {
        comments.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.key < $1.key }
    }

    private var reviewBar: some View {
        HStack(spacing: 10) {
            Text("\(filledComments.count) 条评论")
                .font(CoveFont.ui(12))
                .foregroundStyle(Color.coveT2)
            Spacer()
            Button("清空") { comments = [:]; editing = nil }
                .buttonStyle(.borderless)
            Button("发送给 Agent") { sendComments() }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.coveRaised)
        .overlay(alignment: .top) { Rectangle().fill(Color.coveLine).frame(height: 1) }
    }

    private func sendComments() {
        guard case let .diff(lines) = result, let sendReview else { return }
        let items = filledComments.compactMap { index, note -> ReviewComment? in
            guard lines.indices.contains(index) else { return nil }
            let line = lines[index]
            return ReviewComment(line: line.newLine, code: line.text, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !items.isEmpty else { return }
        let relative = path.hasPrefix(cwd + "/") ? String(path.dropFirst(cwd.count + 1)) : path
        sendReview(AgentPrompts.review(file: relative, comments: items))
        comments = [:]
        editing = nil
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(CoveFont.ui(14, weight: .medium)).foregroundStyle(Color.coveT1)
            Text(detail).font(CoveFont.ui(12)).foregroundStyle(Color.coveT3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayDirectory: String {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if directory.hasPrefix(cwd) {
            let relative = String(directory.dropFirst(cwd.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? "./" : relative + "/"
        }
        return (directory as NSString).abbreviatingWithTildeInPath + "/"
    }
}

private struct DiffRow: View {
    let line: DiffLine
    let commentable: Bool
    let hasComment: Bool
    let comment: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            // 行号左侧的评论入口：悬停才出现，和 GitHub / VS Code 的位置一致。
            ZStack {
                if commentable && (hovering || hasComment) {
                    Button(action: comment) {
                        Image(systemName: hasComment ? "text.bubble.fill" : "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Color.coveAccentFill, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("在这一行写评论")
                }
            }
            .frame(width: 22)
            number(line.oldLine)
            number(line.newLine)
            Text(marker)
                .frame(width: 18)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .hunk || line.kind == .meta ? Color.coveT3 : Color.coveT1)
                .fixedSize()
                .padding(.trailing, 24)
        }
        .font(CoveFont.mono(12))
        .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
        .background(background)
        .textSelection(.enabled)
        .onHover { hovering = $0 }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(Color.coveT3.opacity(0.6))
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        default: ""
        }
    }

    private var markerColor: Color {
        line.kind == .added ? .coveAdd : .coveDel
    }

    private var background: Color {
        switch line.kind {
        case .added: .coveAdd.opacity(0.11)
        case .removed: .coveDel.opacity(0.11)
        case .hunk: .coveAccentDim
        default: .clear
        }
    }
}

/// 一行下面展开的评论框。回车收起（评论保留），清空并收起即删除。
private struct CommentEditor: View {
    @Binding var text: String
    let focused: Bool
    let done: () -> Void
    let remove: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("写给 Agent 的意见…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CoveFont.ui(12.5))
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit(done)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.coveT3)
            }
            .buttonStyle(.plain)
            .help("删除这条评论")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.coveRaised, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.coveAccent.opacity(0.5)))
        .padding(.leading, 22 + 100)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: 720 + 122, alignment: .leading)
        .onAppear { isFocused = focused }
        .onChange(of: focused) { _, value in isFocused = value }
    }
}
