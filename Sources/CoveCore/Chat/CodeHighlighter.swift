/// 代码块的轻量高亮：只分关键字、字符串、注释、数字四类，diff 按行分增删。
///
/// 不是语法分析器：一个字符扫描器加一张多语言通用的关键字表，够让代码块不再是一片同色的字。
/// 没标语言的代码块不高亮——没法知道 `#` 是注释还是别的东西，宁可不上色也别上错。
public enum CodeHighlighter {
    public enum Kind: Equatable, Sendable {
        case keyword, string, comment, number
        case added, removed, hunk
    }

    public struct Span: Equatable, Sendable {
        /// 字符下标范围（`Array(code)` 的下标）。
        public let range: Range<Int>
        public let kind: Kind
    }

    public static func spans(_ code: String, language: String) -> [Span] {
        let language = language.lowercased()
        if ["diff", "patch"].contains(language) { return diff(code) }
        guard !language.isEmpty, !["text", "txt", "plain", "plaintext", "markdown", "md"].contains(language) else { return [] }
        return scan(Array(code), hashComments: hashLanguages.contains(language), dashComments: dashLanguages.contains(language))
    }

    private static let hashLanguages: Set<String> = [
        "python", "py", "sh", "bash", "zsh", "shell", "console", "ruby", "rb", "yaml", "yml", "toml", "r", "perl", "make", "makefile", "dockerfile", "ini", "conf",
    ]
    private static let dashLanguages: Set<String> = ["sql", "lua", "haskell", "hs"]

    private static let keywords: Set<String> = [
        // 各语言里最常见的那批，不求全。
        "func", "function", "fn", "def", "class", "struct", "enum", "protocol", "interface", "impl", "trait", "extension",
        "let", "var", "const", "val", "mut", "static", "final", "public", "private", "internal", "fileprivate", "protected", "export", "import", "from", "package", "use", "mod",
        "if", "else", "elif", "switch", "case", "default", "match", "for", "while", "do", "loop", "in", "of", "break", "continue", "return", "yield",
        "try", "catch", "throw", "throws", "finally", "guard", "defer", "await", "async", "where", "is", "as", "new", "delete", "typeof", "instanceof",
        "true", "false", "nil", "null", "none", "None", "True", "False", "undefined", "self", "Self", "this", "super",
        "type", "typealias", "some", "any", "void", "int", "string", "bool", "and", "or", "not", "with", "lambda", "pass", "raise", "except",
        "select", "insert", "update", "from", "where", "join", "order", "by", "group", "create", "table", "echo", "then", "fi", "done", "esac",
    ]

    private static func scan(_ chars: [Character], hashComments: Bool, dashComments: Bool) -> [Span] {
        var spans: [Span] = []
        var i = 0
        func lineEnd(from start: Int) -> Int {
            var j = start
            while j < chars.count, chars[j] != "\n" { j += 1 }
            return j
        }
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if (c == "/" && next == "/") || (hashComments && c == "#") || (dashComments && c == "-" && next == "-") {
                let end = lineEnd(from: i)
                spans.append(Span(range: i..<end, kind: .comment))
                i = end
            } else if c == "/" && next == "*" {
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                let end = min(j + 2, chars.count)
                spans.append(Span(range: i..<end, kind: .comment))
                i = end
            } else if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                while j < chars.count, chars[j] != c, c == "`" || chars[j] != "\n" {
                    j += chars[j] == "\\" ? 2 : 1
                }
                let end = min(j + 1, chars.count)
                spans.append(Span(range: i..<end, kind: .string))
                i = end
            } else if c.isNumber, i == 0 || !isWord(chars[i - 1]) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_" { j += 1 }
                spans.append(Span(range: i..<j, kind: .number))
                i = j
            } else if isWord(c) {
                var j = i
                while j < chars.count, isWord(chars[j]) { j += 1 }
                if keywords.contains(String(chars[i..<j])) { spans.append(Span(range: i..<j, kind: .keyword)) }
                i = j
            } else {
                i += 1
            }
        }
        return spans
    }

    private static func isWord(_ c: Character) -> Bool {
        c == "_" || (c.isASCII && (c.isLetter || c.isNumber))
    }

    private static func diff(_ code: String) -> [Span] {
        var spans: [Span] = []
        var start = 0
        for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
            let kind: Kind? = line.hasPrefix("@@") ? .hunk : line.hasPrefix("+") ? .added : line.hasPrefix("-") ? .removed : nil
            if let kind, !line.isEmpty { spans.append(Span(range: start..<start + line.count, kind: kind)) }
            start += line.count + 1
        }
        return spans
    }
}
