import Foundation

/// 字节级的 JSONL 预筛。
///
/// 会话文件里绝大部分体积是 tool_result（整份文件内容、长命令输出），而侧栏只关心
/// 标题行和人类消息行。CLI 写记录时 `type` 总在前几百字节内，所以只在每行开头的
/// `window` 字节里找标记，命中了才把这一行转成 String 交给 JSON 解码。
/// 在 820MB / 481 个会话上，这让首次扫描从 40 多秒降到 1 秒量级。
public enum JSONLScanner {
    public struct Filter: Sendable {
        let include: [[UInt8]]
        let exclude: [[UInt8]]
        let window: Int
        /// 超过这个长度的行直接跳过。人类消息行也可能极长——贴进来的截图是 base64，
        /// 一行几 MB——而侧栏只需要它的标题和 cwd，为它解码不值得。
        let maxLineLength: Int

        public init(include: [String], exclude: [String] = [], window: Int = 1024, maxLineLength: Int = 256 * 1024) {
            self.include = include.map { Array($0.utf8) }
            self.exclude = exclude.map { Array($0.utf8) }
            self.window = window
            self.maxLineLength = maxLineLength
        }
    }

    /// 侧栏用：标题记录 + 非工具结果的 user 记录。
    public static let summaryFilter = Filter(
        include: [#""type":"user""#, #""type":"ai-title""#, #""type":"custom-title""#],
        exclude: [#""tool_use_id""#]
    )

    public static func lines(in data: Data, matching filter: Filter) -> [Substring] {
        var result: [Substring] = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            var start = 0
            while start < count {
                let remaining = count - start
                let newline = memchr(base + start, 0x0A, remaining)
                let end = newline.map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                let length = end - start
                if length > 0, length <= filter.maxLineLength {
                    let head = base + start
                    let window = min(length, filter.window)
                    if contains(head, window, filter.include), !contains(head, window, filter.exclude),
                       let line = String(bytes: UnsafeRawBufferPointer(start: head, count: length), encoding: .utf8) {
                        result.append(Substring(line))
                    }
                }
                start = end + 1
            }
        }
        return result
    }

    private static func contains(_ head: UnsafeRawPointer, _ length: Int, _ needles: [[UInt8]]) -> Bool {
        needles.contains { needle in
            needle.withUnsafeBytes { memmem(head, length, $0.baseAddress, needle.count) != nil }
        }
    }
}
