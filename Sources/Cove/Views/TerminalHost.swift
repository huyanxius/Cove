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
    private var bottomConstraint: NSLayoutConstraint?
    /// 终端往容器下方延伸的行数：被隐藏的输入区落到可见区域外，正文一直铺到输入框上沿。
    private var extendedRows = 0
    private var pendingRows = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
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
        // 外观切换时 codex / agy 的终端会就地换色，内边距跟着刷。
        syncAppearance()
        // 用户正在 CLI 自己的输入框里打斜杠命令时，输入区和它下面的补全菜单都得露出来。
        guard let terminal = mounted, session?.directInput == nil,
              InterfaceMode.current.hidesCLIPrompt else {
            cover.isHidden = true
            setExtension(0)
            return
        }
        let engine = terminal.getTerminal()
        let screen = (0..<engine.rows).map { engine.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
        guard let row = PromptRegion.hiddenFrom(screen) else {
            cover.isHidden = true
            setExtension(0)
            return
        }
        // 与 SwiftTerm 的行高算法一致：ceil(ascent + descent + leading)。
        let font = terminal.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        // 输入区真正占的行数（到最后一行非空内容为止）。只在它贴着屏幕底部时才延伸——
        // 输入区在屏幕中间时下面本来就是空的，延伸只会让它一路往下追。
        let lastUsed = screen.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? row
        let regionRows = lastUsed - row + 1
        let atBottom = lastUsed >= engine.rows - 2
        setExtension(atBottom ? regionRows + extendedRows : extendedRows, lineHeight: lineHeight)
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
        let bottom = terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            bottom,
        ])
        bottomConstraint = bottom
        extendedRows = 0
        mounted = terminal
        syncAppearance()
    }

    /// 连续两次测到同一个值才改，避免终端改尺寸、CLI 重排时来回抖。
    private func setExtension(_ rows: Int, lineHeight: CGFloat = 0) {
        let target = max(0, min(rows, 12))
        guard target != extendedRows else { pendingRows = target; return }
        guard target == pendingRows else { pendingRows = target; return }
        extendedRows = target
        bottomConstraint?.constant = -10 + CGFloat(target) * lineHeight + (target > 0 ? 10 : 0)
    }

    /// 内边距与终端同色（终端配色见 `LiveSession.tone`）。
    private func syncAppearance() {
        layer?.backgroundColor = mounted?.nativeBackgroundColor.cgColor
    }
}
