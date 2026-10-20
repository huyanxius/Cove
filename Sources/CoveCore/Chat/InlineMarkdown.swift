import Foundation

/// 段落内的行内 Markdown（粗体、斜体、行内代码、链接）→ `AttributedString`。
///
/// 直接交给 `AttributedString(markdown:)` 在中文里会漏掉粗体：CommonMark 规定 `**` 前面是标点
/// 而后面紧跟文字时，它不算结束符，于是 `**若依(RuoYi)**改的` 原样露出四个星号。
/// 中文回复里「括号 / 引号后直接接汉字」太常见，所以这里先按 `**…**` 成对切开，
/// 各段分别解析，再给配对段整体加上粗体。
public enum InlineMarkdown {
    private static let bold = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)

    public static func attributed(_ text: String) -> AttributedString {
        let ns = text as NSString
        var result = AttributedString()
        var cursor = 0
        for match in bold.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += parse(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            var strong = parse(ns.substring(with: match.range(at: 1)))
            for run in strong.runs {
                let intent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                strong[run.range].inlinePresentationIntent = intent
            }
            result += strong
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { result += parse(ns.substring(from: cursor)) }
        return result
    }

    private static func parse(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
