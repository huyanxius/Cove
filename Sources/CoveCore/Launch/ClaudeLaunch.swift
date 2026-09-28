/// 拼出拉起 claude 的命令行。
///
/// 一律经用户的登录交互 shell（`-l -i -c`）执行，而不是直接 exec claude 的绝对路径：
/// 从 Finder 启动的 App 拿不到用户 shell 里的 PATH、nvm、alias 和 `CLAUDE_CONFIG_DIR`，
/// 有人的 `claude` 本身就是一个带环境变量的 alias。走 shell 才和他在终端里敲的完全一致。
import Foundation

public enum ClaudeLaunch {
    public enum Mode: Equatable, Sendable {
        /// ID 由 Cove 预先生成，这样标签页从第一秒起就知道该盯哪个 JSONL。
        case new(sessionID: String)
        /// 恢复时 CLI 沿用原 ID 继续写同一个文件（除非加 `--fork-session`）。
        case resume(sessionID: String)
    }

    /// `theme` 非空时经 `--settings` 只为这个进程覆盖 claude 的 `/theme`，让 TUI 配色和
    /// Cove 的外观一致（浅色外观配 claude 的 light 主题）；用户的 settings.json 不受影响。
    public static func claudeArguments(_ mode: Mode, theme: String? = nil) -> [String] {
        claudeArguments(mode, settingsJSON: theme.map { settingsJSON(theme: $0, statusLineCommand: nil) })
    }

    public static func claudeArguments(_ mode: Mode, settingsJSON: String?) -> [String] {
        var arguments: [String]
        switch mode {
        case let .new(id): arguments = ["--session-id", id]
        case let .resume(id): arguments = ["--resume", id]
        }
        if let settingsJSON { arguments += ["--settings", settingsJSON] }
        return arguments
    }

    /// 只作用于这个进程的额外设置：主题跟随 Cove 外观；statusLine 换成 Cove 的转发脚本，
    /// 它把用量 JSON 落盘后再交给用户原来的 statusLine 命令，终端里看到的状态栏不变。
    public static func settingsJSON(theme: String?, statusLineCommand: String?) -> String {
        var object: [String: Any] = [:]
        if let theme { object["theme"] = theme }
        if let statusLineCommand { object["statusLine"] = ["type": "command", "command": statusLineCommand, "padding": 0] }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// `claude` 本身不加引号，否则 shell 不会做 alias 展开。
    /// 启动前先清屏并清掉滚动缓冲：交互 shell 读 .zshrc 时打印的横幅和提示与这个会话无关。
    public static func shellCommand(shell: String, claudeArguments: [String]) -> (executable: String, args: [String]) {
        let claude = (["claude"] + claudeArguments.map(shellQuote)).joined(separator: " ")
        return (shell, ["-l", "-i", "-c", #"printf '\033[H\033[2J\033[3J'; "# + claude])
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
