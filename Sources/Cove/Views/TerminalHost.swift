import AppKit
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
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
