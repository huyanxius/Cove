/// 键盘交给了 CLI 自己的输入框之后（见 `KeyRoute.handoff`），根据用户在终端里的按键判断
/// 什么时候把键盘还给 Cove 的输入框。
///
/// 看的是按键而不是屏幕：CLI 输入框空着的时候会画灰色占位文字（codex 的「Ask Codex to do
/// anything」），从屏幕文字上分不出「空」和「有字」。按键足够：回车 = 命令已经执行，
/// Ctrl+C = CLI 清空了输入，删到比开头那个 `/` 还少 = 输入框又空了。
/// Tab 补全会一次塞进不知道多少字，之后只认回车和 Ctrl+C，不再数退格。
///
/// 用 ⌘/ 主动切过去的是 `sticky`：用户明说了要用 CLI 的输入框，按什么都不自动切回，
/// 只有再按一次 ⌘/ 才回来。
public struct DirectInput: Equatable, Sendable {
    public let sticky: Bool
    /// 交接时已经写进去的那个字符算一个。
    private var typed = 1
    private var countable = true

    public init(sticky: Bool = false) {
        self.sticky = sticky
    }

    /// 返回 true 表示该把键盘还给 Cove 的输入框了。这个键本身仍然照常交给终端。
    public mutating func record(_ stroke: KeyStroke) -> Bool {
        guard !sticky else { return false }
        let mods = stroke.modifiers
        switch stroke.key {
        case .enter:
            return !mods.contains(.shift) && !mods.contains(.option)
        case .character("c") where mods.contains(.control):
            return true
        case .tab:
            countable = false
            return false
        case .backspace:
            guard countable else { return false }
            typed -= 1
            return typed <= 0
        case let .character(text) where mods.isDisjoint(with: [.control, .command]):
            typed += text.count
            return false
        default:
            return false
        }
    }
}
