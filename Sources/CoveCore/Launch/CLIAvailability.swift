/// 只确认命令在登录 shell 中可见；检测到安装不代表账号已登录。
public enum CLIAvailability {
    public static var detectionScript: String {
        CLIKind.allCases.map { cli in
            "if command -v \(cli.executable) >/dev/null 2>&1 && \(cli.executable) --version >/dev/null 2>&1; then printf '\\nCOVE_CLI_FOUND:\(cli.rawValue)\\n'; fi"
        }.joined(separator: "\n")
    }

    public static func installed(in output: String) -> Set<CLIKind> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            let prefix = "COVE_CLI_FOUND:"
            guard line.hasPrefix(prefix) else { return nil }
            return CLIKind(rawValue: String(line.dropFirst(prefix.count)))
        })
    }

    public static func preferred(_ current: CLIKind, installed: Set<CLIKind>) -> CLIKind {
        if installed.contains(current) { return current }
        return CLIKind.allCases.first(where: installed.contains) ?? current
    }
}
