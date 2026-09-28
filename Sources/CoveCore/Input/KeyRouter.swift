/// 与 AppKit 无关的按键描述，App 层把 NSEvent 翻译成它再交给 `KeyRouter`。
public struct KeyStroke: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case up, down, left, right, escape, enter, tab
        /// 按下的字符（忽略修饰键后的原始字符，Ctrl+C 这里是 "c"）。
        case character(String)
        case other
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum KeyRoute: Equatable, Sendable {
    case composer
    /// 原样写进 PTY 的字节。
    case terminal([UInt8])
}

/// 决定一次按键归输入框还是归终端里的 claude。
///
/// 规则只看「输入框是不是空的」：空的时候用户多半在操作 claude 的菜单（权限确认、
/// `/resume` 列表、补全），方向键、Esc、Enter、Tab、⇧Tab（切权限模式）、Ctrl+字母
/// 都交给终端；一旦输入框里有字，所有键都归输入框，保证编辑手感和普通文本框一致。
/// 数字和字母永远不透传——否则在空输入框里打字的第一个字母会被 claude 吃掉。
public enum KeyRouter {
    /// `applicationCursor` 是终端当前的 DECCKM 状态：程序打开它之后，方向键要发
    /// `ESC O A` 而不是 `ESC [ A`，发错了在某些 TUI 里就是一串乱码。
    public static func route(_ stroke: KeyStroke, composerIsEmpty: Bool, applicationCursor: Bool = false) -> KeyRoute {
        if stroke.modifiers.contains(.command) || !composerIsEmpty { return .composer }

        let escape: UInt8 = 0x1B
        let csi: [UInt8] = [escape, 0x5B]
        let arrow: [UInt8] = applicationCursor ? [escape, 0x4F] : csi
        switch stroke.key {
        case .up: return .terminal(arrow + [0x41])
        case .down: return .terminal(arrow + [0x42])
        case .right: return .terminal(arrow + [0x43])
        case .left: return .terminal(arrow + [0x44])
        case .escape: return .terminal([escape])
        case .tab: return .terminal(stroke.modifiers.contains(.shift) ? csi + [0x5A] : [0x09])
        case .enter:
            // ⇧↩ / ⌥↩ 是「换行」，哪怕输入框是空的也不该变成提交。
            if stroke.modifiers.contains(.shift) || stroke.modifiers.contains(.option) { return .composer }
            return .terminal([0x0D])
        case let .character(char) where stroke.modifiers.contains(.control):
            guard let ascii = char.lowercased().unicodeScalars.first?.value, (0x61...0x7A).contains(ascii) else {
                return .composer
            }
            return .terminal([UInt8(ascii) & 0x1F])
        case .character, .other:
            return .composer
        }
    }
}
