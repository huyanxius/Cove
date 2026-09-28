import CoveCore
import Foundation

/// 把 claude 的 statusLine 输入转交给 Cove。
///
/// Cove 经 `--settings` 把 statusLine 换成下面这段转发脚本：它把收到的 JSON 写进
/// `usage/<会话ID>.json`，再原样交给用户自己配的 statusLine 命令，所以终端里的状态栏不变。
/// 会话 ID 和用户原命令通过环境变量传给脚本，不用在命令行里拼接转义。
enum UsageRelay {
    static let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cove")
    static let usageDirectory = supportDirectory.appendingPathComponent("usage")
    static let scriptURL = supportDirectory.appendingPathComponent("statusline-relay.sh")

    private static let script = """
    #!/bin/sh
    # Cove statusLine relay：先把用量 JSON 存给 Cove，再交给用户原来的 statusLine。
    input=$(cat)
    dir="$HOME/Library/Application Support/Cove/usage"
    mkdir -p "$dir"
    [ -n "$COVE_SESSION_ID" ] && printf '%s' "$input" > "$dir/$COVE_SESSION_ID.json"
    [ -n "$COVE_USER_STATUSLINE" ] && printf '%s' "$input" | sh -c "$COVE_USER_STATUSLINE"
    exit 0
    """

    /// 每次启动都覆盖写一遍，脚本内容随版本更新。
    static func install() {
        try? FileManager.default.createDirectory(at: usageDirectory, withIntermediateDirectories: true)
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
    }

    static var command: String { "sh " + ClaudeLaunch.shellQuote(scriptURL.path) }

    /// 用户在 ~/.claude/settings.json 里配的 statusLine 命令；没配就不转发。
    static func userStatusLineCommand() -> String? {
        let settings = SessionIndexer.defaultRoot.deletingLastPathComponent().appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["statusLine"] as? [String: Any] else { return nil }
        return status["command"] as? String
    }

    static func snapshot(for sessionID: String) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: usageDirectory.appendingPathComponent("\(sessionID).json")) else { return nil }
        return UsageSnapshot.parse(data)
    }
}
