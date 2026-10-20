import Foundation

/// 把一段回复切成块，对话视图逐块排版。
///
/// 行内语法（粗体、行内代码、链接）交给 `InlineMarkdown`；块级结构在这里切：标题、段落、
/// 列表（圆点 / 编号 / 任务）、引用、表格、分隔线、代码围栏。覆盖 claude 回复里实际会出现的
/// 那些，不追求完整 CommonMark——列表的多段续行、嵌套引用这类少见写法按段落显示。
///
/// 每段可显示的文字都带着它在原文里的起始位置（`Segment.start`，按字符计）。流式渐显靠它
/// 把屏幕上的每个字对回到达时间，所以无论新字落在哪种块里都能渐显。
public enum MarkdownBlocks {
    /// 原文里连续的一段文字。
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let start: Int

        public init(_ text: String, start: Int) {
            self.text = text
            self.start = start
        }
    }

    public enum ListMarker: Equatable, Sendable {
        case bullet
        case number(Int)
        case task(done: Bool)
    }

    public struct ListItem: Equatable, Sendable {
        public let marker: ListMarker
        /// 缩进层级：每两个空格（或一个制表符）算一级。
        public let level: Int
        public let text: Segment
    }

    public enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }

    public enum Block: Equatable, Sendable {
        case paragraph(Segment)
        case heading(level: Int, Segment)
        case code(language: String, Segment)
        case list([ListItem])
        /// 引用的每一行；显示时去掉了 `>`。
        case quote([Segment])
        case table(header: [String], alignments: [Alignment], rows: [[String]])
        case rule
    }

    public static func split(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Substring] = []
        var paragraphStart = 0
        var items: [ListItem] = []
        var quote: [Segment] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(Segment(paragraph.joined(separator: "\n"), start: paragraphStart))) }
            if !items.isEmpty { blocks.append(.list(items)) }
            if !quote.isEmpty { blocks.append(.quote(quote)) }
            paragraph = []
            items = []
            quote = []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.count + 1
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lineStart = starts[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flush()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [Substring] = []
                var end = index + 1
                while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[end])
                    end += 1
                }
                // 流式输出到一半时围栏还没闭合，照样按代码显示。
                let bodyStart = index + 1 < lines.count ? starts[index + 1] : lineStart + line.count + 1
                blocks.append(.code(language: language, Segment(body.joined(separator: "\n"), start: bodyStart)))
                index = end + 1
                continue
            }
            if let heading = heading(line, start: lineStart) {
                flush()
                blocks.append(heading)
            } else if isRule(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let table = table(lines, at: index) {
                flush()
                blocks.append(table.block)
                index = table.next
                continue
            } else if let item = listItem(line, start: lineStart) {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                items.append(item)
            } else if let segment = quoteLine(line, start: lineStart) {
                if !paragraph.isEmpty || !items.isEmpty { flush() }
                quote.append(segment)
            } else if trimmed.isEmpty {
                flush()
            } else {
                if !items.isEmpty || !quote.isEmpty { flush() }
                if paragraph.isEmpty { paragraphStart = lineStart }
                paragraph.append(line)
            }
            index += 1
        }
        flush()
        return blocks
    }

    // MARK: 各种行

    private static func leadingSpaces(_ line: Substring) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func heading(_ line: Substring, start: Int) -> Block? {
        let lead = leadingSpaces(line)
        let rest = line.dropFirst(lead)
        let hashes = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let afterHashes = rest.dropFirst(hashes)
        guard afterHashes.isEmpty || afterHashes.first == " " || afterHashes.first == "\t" else { return nil }
        let gap = leadingSpaces(afterHashes)
        let body = String(afterHashes.dropFirst(gap)).trimmingCharacters(in: .whitespaces)
        return .heading(level: hashes, Segment(body, start: start + lead + hashes + gap))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: Substring, start: Int) -> ListItem? {
        let lead = leadingSpaces(line)
        var rest = line.dropFirst(lead)
        var marker: ListMarker
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            marker = .bullet
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " else { return nil }
            marker = .number(number)
            rest = after.dropFirst(2)
        }
        rest = rest.drop { $0 == " " }
        if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
            marker = .task(done: rest.dropFirst().first != " ")
            rest = rest.dropFirst(4)
        }
        let level = line.prefix(lead).reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        return ListItem(marker: marker, level: level, text: Segment(String(rest), start: start + (line.count - rest.count)))
    }

    private static func quoteLine(_ line: Substring, start: Int) -> Segment? {
        let rest = line.dropFirst(leadingSpaces(line))
        guard rest.first == ">" else { return nil }
        var body = rest.dropFirst()
        if body.first == " " { body = body.dropFirst() }
        return Segment(String(body), start: start + (line.count - body.count))
    }

    /// 表头行 + 分隔行（`|---|:--:|`）才算表格；之后含 `|` 的非空行都是数据行。
    private static func table(_ lines: [Substring], at index: Int) -> (block: Block, next: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), let alignments = alignments(separator) else { return nil }
        let columns = cells(header)
        guard columns.count == alignments.count else { return nil }
        var rows: [[String]] = []
        var next = index + 2
        while next < lines.count {
            let row = lines[next].trimmingCharacters(in: .whitespaces)
            guard !row.isEmpty, row.contains("|") else { break }
            var values = cells(row)
            // 行里的格子数和表头对不上时补齐或截断，不让一行拖垮整张表。
            if values.count < columns.count { values += Array(repeating: "", count: columns.count - values.count) }
            rows.append(Array(values.prefix(columns.count)))
            next += 1
        }
        return (.table(header: columns, alignments: alignments, rows: rows), next)
    }

    private static func alignments(_ separator: String) -> [Alignment]? {
        let parts = cells(separator)
        guard !parts.isEmpty else { return nil }
        var result: [Alignment] = []
        for part in parts {
            let compact = part.replacingOccurrences(of: " ", with: "")
            let dashes = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (compact.hasPrefix(":"), compact.hasSuffix(":")) {
            case (true, true): result.append(.center)
            case (false, true): result.append(.trailing)
            default: result.append(.leading)
            }
        }
        return result
    }

    private static func cells(_ row: String) -> [String] {
        var body = Substring(row)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
