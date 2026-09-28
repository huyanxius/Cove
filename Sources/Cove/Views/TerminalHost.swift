import AppKit
import CoveCore
import SwiftTerm
import SwiftUI

/// 把 `LiveSession` 持有的终端视图挂进 SwiftUI。
///
/// 容器本身常驻，换会话时只把子视图摘下换上，终端和进程都不重建。容器四周留一圈
/// 与终端同色的内边距，TUI 的文字就不会贴着边。
struct TerminalHost: NSViewRepresentable {
    let session: LiveSession

    func makeNSView(context: Context) -> TerminalContainer {
        let container = TerminalContainer()
        container.mount(session)
        return container
    }

    func updateNSView(_ container: TerminalContainer, context: Context) {
        container.mount(session)
    }
}

final class TerminalContainer: NSView {
    private weak var session: LiveSession?
    private weak var mounted: TerminalView?
    /// 盖在 CLI 自带输入区上的同色遮挡，见 `updatePromptCover()`。
    private let cover = NSView()
    private var coverTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        cover.wantsLayer = true
        cover.isHidden = true
        coverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePromptCover() }
        }
    }

    deinit { coverTimer?.invalidate() }

    /// 用 Cove 自己的输入框时，把 CLI 画在屏幕底部的输入区（以及它下面的状态栏）盖住。
    /// 每 0.2 秒读一遍可见屏幕的文字，交给 `PromptRegion` 找起始行；找不到（比如正在弹
    /// 权限菜单）就不盖。遮挡只是一层同色的 NSView，终端本身的内容与交互都不受影响。
    private func updatePromptCover() {
        guard let terminal = mounted, UserDefaults.standard.object(forKey: "hideCLIPrompt") as? Bool ?? true else {
            cover.isHidden = true
            return
        }
        let engine = terminal.getTerminal()
        let screen = (0..<engine.rows).map { engine.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
        guard let row = PromptRegion.hiddenFrom(screen) else {
            cover.isHidden = true
            return
        }
        // 与 SwiftTerm 的行高算法一致：ceil(ascent + descent + leading)。
        let font = terminal.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let top = terminal.frame.maxY - CGFloat(row) * lineHeight
        cover.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, top))
        cover.layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        if cover.superview !== self { addSubview(cover, positioned: .above, relativeTo: terminal) }
        cover.isHidden = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func mount(_ session: LiveSession) {
        self.session = session
        let terminal = session.terminal
        guard mounted !== terminal else { return }
        mounted?.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        mounted = terminal
        syncAppearance()
    }

    /// 内边距与终端同色；终端的颜色在会话启动时就定了（见 `LiveSession.tone`）。
    private func syncAppearance() {
        layer?.backgroundColor = mounted?.nativeBackgroundColor.cgColor
    }
}
