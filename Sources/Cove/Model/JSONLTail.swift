import CoveCore
import Foundation

/// 跟着一个会话的 JSONL 往下读，把新增的行喂给 `ActivityTracker`。
///
/// 用 0.5s 轮询而不是 FSEvents：CLI 每次追加都是整行写入，轮询读增量字节足够及时，
/// 也不怕文件在会话开始时还不存在（新会话要等第一条消息才落盘）。首次打开一个几十 MB
/// 的旧会话时，完整回放在后台队列里做，界面只收到折叠后的结果。
final class JSONLTail: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cove.jsonl-tail", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var url: URL?
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var tracker = ActivityTracker()
    private let locate: @Sendable () -> URL?
    private let onUpdate: @Sendable (ActivityTracker) -> Void

    init(locate: @escaping @Sendable () -> URL?, onUpdate: @escaping @Sendable (ActivityTracker) -> Void) {
        self.locate = locate
        self.onUpdate = onUpdate
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        if url == nil { url = locate() }
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // 文件被截断或替换（极少见），从头再来。
            offset = 0
            remainder = Data()
            tracker = ActivityTracker()
        }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return }
        offset += UInt64(chunk.count)

        var buffer = remainder + chunk
        var consumed = 0
        buffer.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var start = 0
            for index in 0..<bytes.count where bytes[index] == 0x0A {
                if index > start, let line = String(bytes: bytes[start..<index], encoding: .utf8) {
                    for event in TranscriptEvent.parse(line) { tracker.apply(event) }
                }
                start = index + 1
            }
            consumed = start
        }
        // 最后一行可能还没写完，留到下一轮。
        remainder = buffer.subdata(in: consumed..<buffer.count)
        buffer = Data()
        onUpdate(tracker)
    }
}
