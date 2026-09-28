import AppKit
import CoveCore
import SwiftTerm
import SwiftUI

/// docs/DESIGN.md 里的色板。每个 token 同时给出浅色和深色值，随系统外观切换。
/// 只有 `harbor` 是强调色；`lantern` 只给「等你」这一个状态用，别拿去做装饰。
enum Palette {
    static let canvas = dynamic(0xF6F5F1, 0x15181C)
    static let sidebar = dynamic(0xEEEDE7, 0x1A1E23)
    static let surface = dynamic(0xFFFFFF, 0x1E2329)
    static let hairline = dynamic(0xE2DFD7, 0x2B3138)
    static let ink = dynamic(0x1D2530, 0xE6E4DE)
    static let inkMuted = dynamic(0x6D6A63, 0x9A968D)
    static let harbor = dynamic(0x2E5E8C, 0x7EA7D0)
    static let harborWash = dynamic(0xE3EBF3, 0x22303F)
    static let lantern = dynamic(0xB07A2A, 0xD3A55A)
    static let added = dynamic(0x3F7D4E, 0x7DB38A)
    static let removed = dynamic(0xA8483E, 0xD9857B)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension SwiftUI.Color {
    static let coveCanvas = SwiftUI.Color(nsColor: Palette.canvas)
    static let coveSidebar = SwiftUI.Color(nsColor: Palette.sidebar)
    static let coveSurface = SwiftUI.Color(nsColor: Palette.surface)
    static let coveHairline = SwiftUI.Color(nsColor: Palette.hairline)
    static let coveInk = SwiftUI.Color(nsColor: Palette.ink)
    static let coveInkMuted = SwiftUI.Color(nsColor: Palette.inkMuted)
    static let coveHarbor = SwiftUI.Color(nsColor: Palette.harbor)
    static let coveHarborWash = SwiftUI.Color(nsColor: Palette.harborWash)
    static let coveLantern = SwiftUI.Color(nsColor: Palette.lantern)
    static let coveAdded = SwiftUI.Color(nsColor: Palette.added)
    static let coveRemoved = SwiftUI.Color(nsColor: Palette.removed)
}

/// 三种字体各有分工：衬线给标题和会话名（人文感的来源），SF 给界面文字，
/// SF Mono 给终端、diff、路径和一切数值。`label` 是像素味的主要出口。
enum CoveFont {
    static func title(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
}

/// 终端面板的配色。底色随 claude 自己的主题（见 `TerminalTone`），ANSI 16 色压低饱和度，
/// 和外壳的港湾蓝同一个色温，免得 TUI 里的红绿在克制的外壳里显得刺眼。
enum TerminalPalette {
    struct Scheme {
        let background: UInt32
        let foreground: UInt32
        let caret: UInt32
        let ansi: [UInt32]
    }

    static let dark = Scheme(
        background: 0x171B20, foreground: 0xE6E4DE, caret: 0x7EA7D0,
        ansi: [0x1E2329, 0xD9857B, 0x7DB38A, 0xD3A55A, 0x7EA7D0, 0xB59BC9, 0x7FB5B5, 0xCFCCC4,
               0x5C636C, 0xE8A198, 0x9BCBA6, 0xE4C07F, 0xA3C2E0, 0xCBB5DB, 0x9FCFCF, 0xF3F1EC]
    )

    static let light = Scheme(
        background: 0xFFFFFF, foreground: 0x1D2530, caret: 0x2E5E8C,
        ansi: [0x1D2530, 0xA8483E, 0x3F7D4E, 0x9A6A1F, 0x2E5E8C, 0x7A5A92, 0x2F7373, 0x8A877F,
               0x5C636C, 0xC05A4F, 0x4E9460, 0xB07A2A, 0x3F74A8, 0x9171AA, 0x3D8C8C, 0xB9B6AE]
    )

    static func scheme(for tone: TerminalTone) -> Scheme { tone == .dark ? dark : light }

    static func apply(_ tone: TerminalTone, to view: TerminalView) {
        let scheme = scheme(for: tone)
        view.installColors(scheme.ansi.map(terminalColor))
        view.nativeBackgroundColor = NSColor(hex: scheme.background)
        view.nativeForegroundColor = NSColor(hex: scheme.foreground)
        view.caretColor = NSColor(hex: scheme.caret)
    }

    private static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        // SwiftTerm 的颜色分量是 16 位。
        SwiftTerm.Color(red: UInt16((hex >> 16) & 0xFF) * 257, green: UInt16((hex >> 8) & 0xFF) * 257,
                        blue: UInt16(hex & 0xFF) * 257)
    }
}
