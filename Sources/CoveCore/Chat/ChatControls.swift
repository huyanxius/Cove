import Foundation

/// 输入框下面那排控制（模型、思考强度、权限档位）的可选项和当前值。由各 CLI 的
/// `ChatProtocol` 维护，界面只负责展示。三家的权限档位不是一回事，所以 `modes` 只存 id，
/// 叫法和说明在界面层按 CLI 查。
public struct ChatControls: Equatable, Sendable {
    public var models: [ModelOption] = []
    /// 当前模型（`ModelOption.value`）。nil = 还不知道，显示「模型」。
    public var model: String?
    /// 当前模型支持的强度档位，从低到高；空 = 不支持调强度。
    public var effortLevels: [String] = []
    public var effort: String?
    public var modes: [String] = []
    public var mode: String?

    public init() {}
}

/// 改一项控制之后要做什么。
public enum ControlChange: Equatable, Sendable {
    /// 往 stdin 写这些行（claude 的控制请求）；空数组表示记下了、下一轮生效（codex）。
    case send([String])
    /// 这个 CLI 只能在启动时设这一项：等这一轮结束，按同一会话 ID 带新参数重开（agy）。
    case relaunch
}

/// 从一行 stdout 里取出 JSON。
///
/// CLI 经登录交互 shell 拉起，.zshrc 里打印横幅的颜色码有时不带换行，于是第一行 JSON
/// 前面粘着 `ESC[0m` 这样的转义序列——只认 `{` 开头会把它当噪音丢掉（agy 的 init 行
/// 就这样丢过，Cove 一直等不到「连上」）。这里先剥掉终端转义序列，剩下的前缀只要是空白
/// 就从第一个 `{` 取起。
public enum JSONLine {
    private static let escape = try! NSRegularExpression(pattern: "\u{1B}(\\[[0-9;?]*[ -/]*[@-~]|\\][^\u{07}]*\u{07}|[@-Z\\\\-_])")

    public static func payload(_ line: String) -> String? {
        let ns = line as NSString
        let clean = escape.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        guard let brace = clean.firstIndex(of: "{"),
              clean[..<brace].allSatisfy({ $0.isWhitespace }) else { return nil }
        return String(clean[brace...])
    }
}
