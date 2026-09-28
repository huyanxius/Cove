import AppKit
import SwiftTerm
import SwiftUI

/// 把 `LiveSession` 持有的终端视图挂进 SwiftUI。
///
/// 容器本身常驻，换会话时只把子视图摘下换上，终端和进程都不重建。容器四周留一圈
/// 与终端同色的内边距，TUI 的文字就不会贴着分隔线。
struct TerminalHost: NSViewRepresentable {
    let session: LiveSession

    func makeNSView(context: Context) -> TerminalContainer {
        let container = TerminalContainer()
        container.mount(session.terminal)
        return container
    }

    func updateNSView(_ container: TerminalContainer, context: Context) {
        container.mount(session.terminal)
    }
}

final class TerminalContainer: NSView {
    private weak var mounted: TerminalView?
    private let inset: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func mount(_ terminal: TerminalView) {
        guard mounted !== terminal else { return }
        mounted?.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset / 2),
        ])
        mounted = terminal
        syncBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncBackground()
    }

    private func syncBackground() {
        layer?.backgroundColor = mounted?.nativeBackgroundColor.cgColor
    }
}
