import CoveCore
import Foundation

/// Cove 界面每个会话和 CLI 之间的原始往来，一行一条、标明方向，排查协议问题用
/// （比如权限卡片没出来：看 claude 到底发没发 `can_use_tool`）。
///
/// 位置：`~/Library/Application Support/Cove/logs/<cli>-<会话ID>.log`。单行截到 4000 字符
/// （工具输出可能很长），单个文件到 5 MB 就不再写，避免在磁盘紧张的机器上越攒越大。
final class ProtocolLog: @unchecked Sendable {
    static let directory = UsageRelay.supportDirectory.appendingPathComponent("logs")
    private static let lineLimit = 4000
    private static let fileLimit: UInt64 = 5 * 1024 * 1024

    let url: URL
    private let queue = DispatchQueue(label: "cove.protocol-log", qos: .utility)
    private var handle: FileHandle?
    private var written: UInt64 = 0

    init(cli: CLIKind, sessionID: String) {
        url = Self.directory.appendingPathComponent("\(cli.rawValue)-\(sessionID).log")
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            written = (try? handle?.seekToEnd()) ?? 0
        }
    }

    enum Direction: String {
        case received = "<-"
        case sent = "->"
        case stderr = "!!"
        case note = "##"
    }

    func record(_ direction: Direction, _ text: String) {
        let stamp = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withTime, .withFractionalSeconds])
        var body = text.trimmingCharacters(in: .newlines)
        if body.count > Self.lineLimit { body = String(body.prefix(Self.lineLimit)) + "…[截断]" }
        let line = "\(stamp) \(direction.rawValue) \(body)\n"
        queue.async { [self] in
            guard let handle, written < Self.fileLimit else { return }
            let data = Data(line.utf8)
            try? handle.write(contentsOf: data)
            written += UInt64(data.count)
        }
    }

    deinit {
        let handle = handle
        queue.async { try? handle?.close() }
    }
}
