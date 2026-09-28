import Foundation

/// 终端区域用深底还是浅底。
///
/// 跟的是 claude 自己的 `/theme`，不是 macOS 外观：TUI 的配色是按它的主题为某种底色
/// 设计的，深色主题的浅灰字放在浅底上几乎看不见。所以浅色 App 里出现一块深色终端是
/// 正常的——这和 IDE 里的终端面板一个道理。
public enum TerminalTone: Equatable, Sendable {
    case light, dark

    /// `claudeTheme` 是 settings.json 里 `theme` 的原值：dark / light / dark-daltonized /
    /// light-ansi / auto…… 未设置时 CLI 默认 dark。
    public static func resolve(claudeTheme: String?, systemIsDark: Bool) -> TerminalTone {
        guard let theme = claudeTheme?.lowercased() else { return .dark }
        if theme == "auto" { return systemIsDark ? .dark : .light }
        return theme.hasPrefix("light") ? .light : .dark
    }

    public static func claudeTheme(fromSettings json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["theme"] as? String
    }
}
