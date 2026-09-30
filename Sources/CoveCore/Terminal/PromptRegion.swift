/// 在终端屏幕文字里找出 CLI 自带输入区的起始行，Cove 用自己的输入框时把这一行往下盖住。
///
/// 只认输入区「平时的样子」：claude 是两道横线夹着 `❯` 行，codex 是 `›` 开头的一行，
/// agy（Gemini 系）是 `╭──╮` 框里一行 `>`。权限确认、选择菜单出现时这些特征会消失或变成
/// `❯ 1. Yes` 这样的编号选项——这时返回 nil，不遮挡，菜单照常可见可操作。
/// 只在屏幕底部 `window` 行内找，避免把正文里画出来的同形文字当成输入区。
public enum PromptRegion {
    public static func hiddenFrom(_ screen: [String], window: Int = 14) -> Int? {
        let lines = screen.map { $0.trimmingCharacters(in: .whitespaces) }
        // 屏幕底部常有空行，底部窗口从最后一行非空内容往上算。
        guard let last = lines.lastIndex(where: { !$0.isEmpty }) else { return nil }
        let lowest = max(0, last - window + 1)

        for i in stride(from: last, through: lowest, by: -1) {
            let line = lines[i]
            // claude：上横线 + ❯ 行 + 若干续行 + 下横线。
            if line.hasPrefix("❯"), !isNumberedOption(line, marker: "❯"),
               i > 0, isRule(lines[i - 1]),
               lines[(i + 1)...].prefix(8).contains(where: isRule) {
                return i - 1
            }
            // agy / Gemini 系：╭ 顶框 + │ > 行。
            if line.hasPrefix("│"), i > 0, lines[i - 1].hasPrefix("╭") {
                let inner = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if inner.hasPrefix(">") || inner.hasPrefix("*") { return i - 1 }
            }
            // codex：› 开头的输入行（编号选项除外）。
            if line.hasPrefix("›"), !isNumberedOption(line, marker: "›") {
                return i
            }
        }
        return nil
    }

    static func isRule(_ line: String) -> Bool {
        line.count >= 10 && line.allSatisfy { "─━═".contains($0) }
    }

    /// `❯ 1. Yes` / `› 2. No`：菜单里的编号选项。
    static func isNumberedOption(_ line: String, marker: Character) -> Bool {
        let rest = line.drop { $0 == marker || $0 == " " }
        guard let first = rest.first, first.isNumber else { return false }
        return rest.dropFirst().drop { $0.isNumber }.first == "."
    }
}
