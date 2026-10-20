import Foundation

/// 临时会话：不属于任何项目的随手一问。每个临时会话一个以时间命名的空目录，
/// 统一放在 Cove 自己的目录下，侧栏据此把它们归进「临时」而不是某个项目。
public enum ScratchSpace {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cove/Scratch")
    }

    public static func isScratch(cwd: String?, root: URL = defaultRoot) -> Bool {
        guard let cwd else { return false }
        return (cwd as NSString).resolvingSymlinksInPath.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    public static func folderName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// 建一个新的临时目录；同一分钟内重复创建时加序号。
    public static func makeFolder(root: URL = defaultRoot, now: Date = .now) throws -> URL {
        let base = folderName(for: now)
        var url = root.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(base)-\(n)")
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
