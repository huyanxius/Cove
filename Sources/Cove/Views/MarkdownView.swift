import AppKit
import CoveCore
import SwiftUI

// MARK: 阅读样式

/// 对话正文的字体、字号、行距，设置里改。只作用于回复和你的消息，界面文字不跟着变。
struct ReadingStyle: Equatable {
    /// `system` / `serif` / `rounded`，或者一个字体家族名（霞鹜文楷、思源宋体……）。
    var family: String
    var size: Double
    var lineSpacing: Double

    static let `default` = ReadingStyle(family: "system", size: 14.5, lineSpacing: 7)

    func font(scale: Double = 1, weight: Font.Weight = .regular) -> Font {
        let points = size * scale
        switch family {
        case "system": return .system(size: points, weight: weight)
        case "serif": return .system(size: points, weight: weight, design: .serif)
        case "rounded": return .system(size: points, weight: weight, design: .rounded)
        default: return .custom(family, size: points).weight(weight)
        }
    }

    var code: Font { .system(size: size - 1.5, design: .monospaced) }

    /// 设置里可选的字体：三种系统设计 + 本机装了的常用中文字体。
    static var families: [(id: String, title: String)] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let extras: [(String, String)] = [
            ("LXGW WenKai", "霞鹜文楷"), ("LXGW WenKai Screen", "霞鹜文楷 屏幕版"), ("Source Han Serif SC", "思源宋体"),
            ("Noto Serif CJK SC", "Noto 宋体"), ("Songti SC", "宋体"), ("Kaiti SC", "楷体"), ("Source Han Sans SC", "思源黑体"),
        ]
        return [("system", "系统（苹方）"), ("serif", "衬线（New York / 宋体）"), ("rounded", "圆体")]
            + extras.filter { installed.contains($0.0) }
    }
}

private struct ReadingStyleKey: EnvironmentKey {
    static let defaultValue = ReadingStyle.default
}

extension EnvironmentValues {
    var readingStyle: ReadingStyle {
        get { self[ReadingStyleKey.self] }
        set { self[ReadingStyleKey.self] = newValue }
    }
}

// MARK: 流式渐显

/// 正在流式输出的正文里，还在渐显中的那些字：从原文第 `start` 个字起，每个字一个到达时间。
struct FadeMap {
    let start: Int
    let arrivals: [Date]

    func arrival(at index: Int) -> Date? {
        let i = index - start
        return arrivals.indices.contains(i) ? arrivals[i] : nil
    }
}

enum BlurIn {
    static let duration: TimeInterval = 0.6
    static let radius: CGFloat = 6
}

@available(macOS 15, *)
struct ArrivalAttribute: TextAttribute {
    let arrived: Date
}

@available(macOS 15, *)
struct BlurInRenderer: TextRenderer {
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

/// 正在流式输出的回复。每个字何时开始浮现由 `RevealTimeline` 排定（严格按顺序），
/// 交给 `MarkdownText` 按原文位置对上；`BlurInRenderer` 按时间画模糊和透明度。
///
/// 这段文字只存在到这一块输出完为止，所以不开文字选中——macOS 上可选中的文字换一套控件绘制，
/// 会绕过自定义渲染器。
struct StreamingReply: View {
    let draft: String
    let chunks: [ChatBridge.DraftChunk]

    var body: some View {
        if #available(macOS 15, *) {
            TimelineView(.animation) { context in
                MarkdownText(text: draft, fade: fade(at: context.date), selectable: false)
                    .textRenderer(BlurInRenderer(now: context.date))
            }
        } else {
            MarkdownText(text: draft, selectable: false)
        }
    }

    /// 从第一个还没完全浮现的字起，给出后面每个字的浮现时间。时间线单调不减，所以从尾部
    /// 往前找到第一个已经完全浮现的字就停。
    private func fade(at now: Date) -> FadeMap? {
        let reveal = RevealTimeline.reveal(batches: chunks.map { ($0.text.count, $0.arrived.timeIntervalSinceReferenceDate) })
        let clock = now.timeIntervalSinceReferenceDate
        var start = reveal.count
        while start > 0, clock < reveal[start - 1] + BlurIn.duration { start -= 1 }
        guard start < reveal.count else { return nil }
        // 字数以 draft 为准：分批拼接时极少数组合字符会在接缝处合并，两边差一两个字。
        let offset = draft.count - reveal.count
        return FadeMap(start: start + offset, arrivals: reveal[start...].map { Date(timeIntervalSinceReferenceDate: $0) })
    }
}

// MARK: 正文

/// 回复正文：块级结构由 `MarkdownBlocks` 切，行内语法由 `InlineMarkdown` 处理。
struct MarkdownText: View {
    let text: String
    var fade: FadeMap?
    var selectable = true
    @Environment(\.readingStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: style.size * 0.95) {
            ForEach(Array(MarkdownBlocks.split(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .modifier(SelectableIf(selectable))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlocks.Block) -> some View {
        switch block {
        case let .paragraph(segment):
            styled(segment)
                .font(style.font())
                .lineSpacing(style.lineSpacing)
                .foregroundStyle(SwiftUI.Color.coveBody)
                .fixedSize(horizontal: false, vertical: true)
        case let .heading(level, segment):
            styled(segment)
                .font(style.font(scale: level == 1 ? 1.32 : level == 2 ? 1.18 : 1.06, weight: level <= 2 ? .semibold : .medium))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .padding(.top, level <= 2 ? 8 : 4)
        case let .list(items):
            VStack(alignment: .leading, spacing: style.lineSpacing * 0.8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        marker(item.marker)
                        styled(item.text)
                            .font(style.font())
                            .lineSpacing(style.lineSpacing)
                            .foregroundStyle(isDone(item) ? SwiftUI.Color.coveT3 : SwiftUI.Color.coveBody)
                            .strikethrough(isDone(item), color: SwiftUI.Color.coveT3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 20)
                }
            }
        case let .quote(lines):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(SwiftUI.Color.coveAccent.opacity(0.45)).frame(width: 3)
                VStack(alignment: .leading, spacing: style.lineSpacing * 0.6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        styled(line)
                            .font(style.font())
                            .lineSpacing(style.lineSpacing)
                            .foregroundStyle(SwiftUI.Color.coveT2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .table(header, alignments, rows):
            MarkdownTable(header: header, alignments: alignments, rows: rows)
        case .rule:
            Rectangle().fill(SwiftUI.Color.coveLine).frame(height: 1).padding(.vertical, 4)
        case let .code(language, segment):
            CodeBlock(language: language, segment: segment, fade: fade)
        }
    }

    private func isDone(_ item: MarkdownBlocks.ListItem) -> Bool { item.marker == .task(done: true) }

    @ViewBuilder
    private func marker(_ marker: MarkdownBlocks.ListMarker) -> some View {
        switch marker {
        case .bullet:
            Circle().fill(SwiftUI.Color.coveT3).frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0.height / 2 - style.size * 0.35 }
                .frame(width: 12)
        case let .number(n):
            Text("\(n).").font(style.font()).monospacedDigit().foregroundStyle(SwiftUI.Color.coveT3).frame(minWidth: 18, alignment: .trailing)
        case let .task(done):
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(done ? SwiftUI.Color.coveAccentFill : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(done ? .clear : SwiftUI.Color.coveT3, lineWidth: 1.2))
                if done { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) }
            }
            .frame(width: 14, height: 14)
            .alignmentGuide(.firstTextBaseline) { $0.height / 2 + style.size * 0.35 }
        }
    }

    /// 一段文字 → Text。已落定的部分按行内 Markdown 排版；还在渐显的字逐个挂上到达时间
    /// （按纯文本显示零点几秒，落定后并回 Markdown）。
    private func styled(_ segment: MarkdownBlocks.Segment) -> Text {
        let plain = Text(InlineMarkdown.attributed(segment.text))
        guard #available(macOS 15, *), let fade, segment.start + segment.text.count > fade.start else { return plain }
        let characters = Array(segment.text)
        let split = max(0, fade.start - segment.start)
        var result = Text(InlineMarkdown.attributed(String(characters[..<split])))
        for index in split..<characters.count {
            let piece = Text(String(characters[index]))
            if let arrived = fade.arrival(at: segment.start + index) {
                result = result + piece.customAttribute(ArrivalAttribute(arrived: arrived))
            } else {
                result = result + piece
            }
        }
        return result
    }
}

private struct SelectableIf: ViewModifier {
    let enabled: Bool
    init(_ enabled: Bool) { self.enabled = enabled }

    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}

// MARK: 表格

private struct MarkdownTable: View {
    let header: [String]
    let alignments: [MarkdownBlocks.Alignment]
    let rows: [[String]]
    @Environment(\.readingStyle) private var style

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column: column, bold: true)
                    }
                }
                .background(SwiftUI.Color.coveKey)
                ForEach(rows.indices, id: \.self) { row in
                    Rectangle().fill(SwiftUI.Color.coveLine).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(rows[row][column], column: column, bold: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SwiftUI.Color.coveRaisedLine))
            .padding(1)
        }
    }

    private func cell(_ text: String, column: Int, bold: Bool) -> some View {
        Text(InlineMarkdown.attributed(text))
            .font(style.font(scale: 0.93, weight: bold ? .semibold : .regular))
            .foregroundStyle(bold ? SwiftUI.Color.coveT1 : SwiftUI.Color.coveBody)
            .lineSpacing(3)
            .frame(maxWidth: 320, alignment: frameAlignment(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .gridColumnAlignment(horizontalAlignment(column))
    }

    private func horizontalAlignment(_ column: Int) -> HorizontalAlignment {
        switch alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ column: Int) -> SwiftUI.Alignment {
        switch alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

// MARK: 代码块

/// 代码块：顶上一条语言标签和复制按钮，正文等宽、横向滚动、轻量高亮。
private struct CodeBlock: View {
    let language: String
    let segment: MarkdownBlocks.Segment
    let fade: FadeMap?
    @Environment(\.readingStyle) private var style
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language.lowercased())
                    .font(CoveFont.mono(10.5))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(segment.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9.5))
                        Text(copied ? "已复制" : "复制").font(CoveFont.ui(11))
                    }
                    .foregroundStyle(SwiftUI.Color.coveT3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(SwiftUI.Color.coveLine).frame(height: 1) }
            ScrollView(.horizontal, showsIndicators: false) {
                highlighted
                    .font(style.code)
                    .lineSpacing(3)
                    .foregroundStyle(SwiftUI.Color.coveT1)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(SwiftUI.Color.coveKey.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwiftUI.Color.coveRaisedLine))
    }

    /// 按高亮区间逐字上色；还在渐显的字各自挂上到达时间。
    private var highlighted: Text {
        let characters = Array(segment.text)
        var kinds = [CodeHighlighter.Kind?](repeating: nil, count: characters.count)
        for span in CodeHighlighter.spans(segment.text, language: language) {
            for index in span.range where index < kinds.count { kinds[index] = span.kind }
        }
        var result = Text("")
        var index = 0
        while index < characters.count {
            let arrival = fadeArrival(index)
            var end = index + 1
            if arrival == nil {
                while end < characters.count, kinds[end] == kinds[index], fadeArrival(end) == nil { end += 1 }
            }
            var piece = Text(String(characters[index..<end]))
            if let color = color(kinds[index]) { piece = piece.foregroundColor(color) }
            if kinds[index] == .comment { piece = piece.italic() }
            if #available(macOS 15, *), let arrival {
                piece = piece.customAttribute(ArrivalAttribute(arrived: arrival))
            }
            result = result + piece
            index = end
        }
        return result
    }

    private func fadeArrival(_ index: Int) -> Date? {
        fade?.arrival(at: segment.start + index)
    }

    private func color(_ kind: CodeHighlighter.Kind?) -> SwiftUI.Color? {
        switch kind {
        case .keyword: .coveAccent
        case .string: .coveAdd
        case .comment: .coveT3
        case .number: .coveAttn
        case .added: .coveAdd
        case .removed: .coveDel
        case .hunk: .coveAccent
        case nil: nil
        }
    }
}
