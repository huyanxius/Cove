import SwiftUI

/// 中栏：标签条（终端 + 打开的 diff）、终端或 diff、输入框。
///
/// 看 diff 时终端并不卸载，只是被盖住；输入框始终在，边看改动边写反馈。
/// 终端在两种外观下都铺满中栏，和外壳连成一片，不加描边。
struct SessionPane: View {
    let session: LiveSession

    var body: some View {
        VStack(spacing: 0) {
            TabBar(session: session)
            content
            Composer(session: session)
        }
        .background(SwiftUI.Color.coveBg)
    }


    private var content: some View {
        ZStack {
            TerminalHost(session: session)
                .opacity(session.activeTab == .terminal ? 1 : 0)
                .allowsHitTesting(session.activeTab == .terminal)
            if session.isRunning && !session.hasOutput && session.activeTab == .terminal {
                ZStack {
                    SwiftUI.Color(nsColor: session.terminal.nativeBackgroundColor)
                    CoffeeLoader(size: 76, caption: "正在启动 \(session.cli.displayName)…")
                }
                .transition(.opacity)
            }
            if case let .diff(path) = session.activeTab {
                DiffView(path: path, cwd: session.cwd,
                         revision: session.tracker.changes.files.first { $0.path == path }?.editCount ?? 0,
                         delta: session.fileDeltas[path])
            }
        }
    }
}

private struct TabBar: View {
    let session: LiveSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tab(.terminal) {
                    Image(systemName: "terminal").font(.system(size: 11))
                    Text("Terminal").font(CoveFont.ui(12, weight: isActive(.terminal) ? .medium : .regular))
                }
                ForEach(session.openDiffs, id: \.self) { path in
                    tab(.diff(path)) {
                        Image(systemName: "plusminus").font(.system(size: 10, weight: .medium))
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(CoveFont.mono(11.5))
                        Button {
                            session.closeDiff(path)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(SwiftUI.Color.coveT3)
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close \(URL(fileURLWithPath: path).lastPathComponent)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            if colorScheme == .dark { SwiftUI.Color.coveLine.frame(height: 1) }
        }
    }

    private func isActive(_ tab: LiveSession.Tab) -> Bool { session.activeTab == tab }

    private func tab(_ tab: LiveSession.Tab, @ViewBuilder label: () -> some View) -> some View {
        let active = isActive(tab)
        return HStack(spacing: 7) { label() }
            .foregroundStyle(active ? SwiftUI.Color.coveT1 : SwiftUI.Color.coveT2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SwiftUI.Color.coveRaised)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SwiftUI.Color.coveRaisedLine))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { session.activeTab = tab }
            .accessibilityAddTraits(.isButton)
    }
}
