import Foundation

/// 把一段回复切成段落、标题和代码块，对话视图逐块排版。
///
/// 段落内部的行内语法（粗体、行内代码、链接）交给系统的 `AttributedString(markdown:)`，
/// 它不处理块级结构，所以块级这一层在这里切。只认最常见的三种块：代码围栏、`#` 标题、
/// 空行分隔的段落；列表和引用留在段落里原样显示——对 claude 的回复已经够用。
public enum MarkdownBlocks {
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case heading(String)
        case code(language: String, String)
    }

    public static func split(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Substring] = []
        var code: (language: String, lines: [Substring])?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.language, open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(line)
                    code = open
                }
            } else if trimmed.hasPrefix("```") {
                flushParagraph()
                code = (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        // 流式输出到一半时围栏还没闭合，照样按代码显示。
        if let open = code { blocks.append(.code(language: open.language, open.lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
