/// Cove 能承载的命令行 Agent。终端里跑的都是它们各自的原版程序。
///
/// 只有 claude 有完整的会话记录与状态推断（JSONL、--session-id、statusLine 用量）；
/// codex 和 agy 目前只作为「在这个文件夹里开一个终端会话」接入，不解析它们的内部记录。
public enum CLIKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case claude, codex, agy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .agy: "Antigravity"
        }
    }

    /// 在用户登录 shell 里调用的命令名；不写绝对路径，让用户自己的 PATH / alias 生效。
    public var executable: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .agy: "agy"
        }
    }

    /// 非 claude 的 CLI：新会话不带参数；`resume` 预留给以后接入各自的恢复命令。
    public func arguments(resume: String?) -> [String] {
        switch self {
        case .claude: resume.map { ["--resume", $0] } ?? []
        case .codex, .agy: []
        }
    }
}
