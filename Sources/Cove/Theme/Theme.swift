import AppKit
import CoveCore
import SwiftTerm
import SwiftUI

/// 色板「暖港」：中性色取 Claude 原生的暖灰（浅色是象牙纸色，深色是暖炭灰 #262624），
/// 蓝只做强调，取自图标纸杯的蓝（#4E74A6）。只有一个强调色（`accent`），`attn` 只给「等你回复」。
/// 深色曾试过整面石板蓝（潮汐），实机看发闷，已弃用。
/// token 名与 docs/DESIGN.md、设计稿 CSS 变量一一对应，改色先改稿子再抄过来。
enum Palette {
    static let bg = dynamic(0xF5F4EF, 0x262624)
    static let bgSidebar = dynamic(0xEDEBE3, 0x1F1E1C)
    static let line = dynamic(0xE1DED4, 0x353430)
    static let raised = dynamic(0xFDFCF9, 0x30302D)
    static let raisedLine = dynamic(0xDCD8CD, 0x3F3E3A)
    static let select = dynamic(0xE4E1D7, 0x393834)
    static let t1 = dynamic(0x2A2925, 0xECEAE3)
    /// 长段正文专用：比 t1 退半步。深色底上接近纯白的中文会显得发粗发亮，读长文累。
    static let body = dynamic(0x33322D, 0xD6D3CA)
    static let t2 = dynamic(0x6A675F, 0xB3B0A7)
    static let t3 = dynamic(0x9A968C, 0x7F7C74)
    static let accent = dynamic(0x43699B, 0x93B4D8)
    static let accentFill = dynamic(0x4E74A6, 0x4E74A6)
    static let accentDim = dynamic(0x43699B, 0x93B4D8, lightAlpha: 0.18, darkAlpha: 0.22)
    static let attn = dynamic(0xC15F3C, 0xD97757)
    static let add = dynamic(0x4E7D4F, 0x93BC8F)
    static let del = dynamic(0xB4533B, 0xE3907A)
    static let key = dynamic(0xECE9E0, 0x3A3935)

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance) ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension SwiftUI.Color {
    static let coveBg = SwiftUI.Color(nsColor: Palette.bg)
    static let coveSidebar = SwiftUI.Color(nsColor: Palette.bgSidebar)
    static let coveLine = SwiftUI.Color(nsColor: Palette.line)
    static let coveRaised = SwiftUI.Color(nsColor: Palette.raised)
    static let coveRaisedLine = SwiftUI.Color(nsColor: Palette.raisedLine)
    static let coveSelect = SwiftUI.Color(nsColor: Palette.select)
    static let coveT1 = SwiftUI.Color(nsColor: Palette.t1)
    static let coveBody = SwiftUI.Color(nsColor: Palette.body)
    static let coveT2 = SwiftUI.Color(nsColor: Palette.t2)
    static let coveT3 = SwiftUI.Color(nsColor: Palette.t3)
    static let coveAccent = SwiftUI.Color(nsColor: Palette.accent)
    static let coveAccentFill = SwiftUI.Color(nsColor: Palette.accentFill)
    static let coveAccentDim = SwiftUI.Color(nsColor: Palette.accentDim)
    static let coveAttn = SwiftUI.Color(nsColor: Palette.attn)
    static let coveAdd = SwiftUI.Color(nsColor: Palette.add)
    static let coveDel = SwiftUI.Color(nsColor: Palette.del)
    static let coveKey = SwiftUI.Color(nsColor: Palette.key)
}

/// 界面文字一律用系统字体：中文自动落到苹方。衬线只给拉丁展示文字（App 名、欢迎语），
/// 千万别给会话标题——中文会回退成宋体，这是上一版丑的主因之一。
enum CoveFont {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// 分组标题：10.5pt 半粗、字距 0.07em、大写。
    static let label = Font.system(size: 10.5, weight: .semibold)
}

/// 终端面板配色，跟随会话启动时交给 claude 的主题：深色主题是 claude 原生的暖炭底，
/// 与深色外壳同色连成一片；浅色主题是白底，作为一张卡片嵌在象牙纸色里。
enum TerminalPalette {
    struct Scheme {
        let background: UInt32
        let foreground: UInt32
        let caret: UInt32
        let ansi: [UInt32]
    }

    private static let darkANSI: [UInt32] = [
        0x2E2E2B, 0xE3907A, 0x93BC8F, 0xD9B06C, 0x8CB6DE, 0xC3A6D6, 0x86C2C0, 0xD6D3CB,
        0x6F6C66, 0xEFA893, 0xAAD1A6, 0xE8C688, 0xA9C9E8, 0xD4BCE2, 0xA2D4D2, 0xF3F1EC,
    ]

    static func scheme(tone: TerminalTone) -> Scheme {
        switch tone {
        case .dark:
            Scheme(background: 0x262624, foreground: 0xE8E6DF, caret: 0x8FB2D4, ansi: darkANSI)
        case .light:
            Scheme(background: 0xFFFFFF, foreground: 0x2A2925, caret: 0x3D6890, ansi: [
                0x2A2925, 0xB4533B, 0x4E7D4F, 0x9A6A1F, 0x3D6890, 0x7A5A92, 0x2F7373, 0x8A877F,
                0x6A675F, 0xC45F45, 0x5E925F, 0xB07A2A, 0x4E7BA6, 0x9171AA, 0x3D8C8C, 0xB9B6AE,
            ])
        }
    }

    static func apply(_ tone: TerminalTone, to view: TerminalView) {
        let scheme = scheme(tone: tone)
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
