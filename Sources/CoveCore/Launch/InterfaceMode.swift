/// 会话中栏用哪种界面，设置里四选一。
///
/// 前三档底下都是终端里的原版 TUI，只差在 Cove 的输入框放不放、CLI 自带的输入区遮不遮，
/// 随时切、就地生效。第四档换成 stream-json 进程（见 `StreamEvent`），切进切出要按同一个
/// 会话 ID 重开。三个 CLI 各用自己的结构化协议（见 `ChatProtocol`）。
public enum InterfaceMode: String, CaseIterable, Identifiable, Sendable {
    /// 完全原生：只有终端，键盘直接进 CLI。
    case native
    /// 原生 CLI + Cove 输入框：CLI 自带的输入区照常可见。
    case nativeWithComposer
    /// Cove 输入框替代 CLI 自带的输入区（遮住它）。
    case composer
    /// Cove 的对话界面。
    case cove

    public var id: String { rawValue }

    /// 这一档下某个 CLI 的会话该用哪种进程。
    public func surface(for cli: CLIKind) -> Surface {
        self == .cove ? .chat : .terminal
    }

    /// 终端界面下要不要把 CLI 自带的输入区遮住。第四档回落到终端的 CLI 按第三档处理。
    public var hidesCLIPrompt: Bool { self == .composer || self == .cove }

    public var showsComposer: Bool { self != .native }

    /// 旧版只有一个「隐藏 CLI 自带的输入框」开关（默认开）。
    public static func migrated(hideCLIPrompt: Bool?) -> InterfaceMode {
        hideCLIPrompt == false ? .nativeWithComposer : .composer
    }
}

public enum Surface: Equatable, Sendable {
    /// 伪终端里跑 TUI。
    case terminal
    /// 管道里跑 stream-json，Cove 自己画对话。
    case chat
}
