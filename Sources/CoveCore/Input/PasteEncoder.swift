/// 把输入框里的文本变成写进 PTY 的字节。
///
/// 用 bracketed paste（`ESC[200~ … ESC[201~`）包裹，claude 会把里面的换行当作文本的
/// 一部分，而不是一次次回车提交。提交用的回车单独发送，并且要和粘贴分开写、中间留一点
/// 间隔——同一次 write 里紧跟的 `\r` 有时会被 TUI 当成粘贴内容的一部分吞掉。
public enum PasteEncoder {
    static let start = "\u{1B}[200~"
    static let end = "\u{1B}[201~"

    public static let submit: [UInt8] = [0x0D]

    public static func paste(_ text: String) -> [UInt8] {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        // 文本里夹带的结束标记会让终端提前退出粘贴模式，后面的内容就变成了逐键输入。
        body = body.replacingOccurrences(of: start, with: "").replacingOccurrences(of: end, with: "")
        while body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
        return Array((start + body + end).utf8)
    }
}
