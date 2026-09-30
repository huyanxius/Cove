/// Cove 能承载的命令行 Agent。终端里跑的都是它们各自的原版程序。
///
/// 只有 claude 有完整的状态推断（JSONL、--session-id、statusLine 用量）；codex 和 agy
/// 接入到「侧栏列出历史会话、点开即恢复」为止，会话列表读它们自己的索引库（见 `CodexSessions`
/// / `AgySessions`），不解析对话内容。
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

    /// 恢复某个会话的参数；`resume` 为 nil 即新开。codex 的恢复是子命令，agy 是选项。
    /// claude 新会话还要带 `--session-id`，那部分在 `ClaudeLaunch`。
    public func arguments(resume: String?) -> [String] {
        guard let resume else { return [] }
        switch self {
        case .claude: return ["--resume", resume]
        case .codex: return ["resume", resume]
        case .agy: return ["--conversation", resume]
        }
    }
}
