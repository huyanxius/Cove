import CoveCore
import SwiftUI

/// 中栏：标签条（终端 + 打开的 diff）、终端或 diff、输入框。
///
/// 看 diff 时终端并不卸载，只是被盖住；输入框始终在，边看改动边写反馈。
/// 终端在两种外观下都铺满中栏，和外壳连成一片，不加描边。
struct SessionPane: View {
    let session: LiveSession
    @AppStorage("interfaceMode") private var interfaceMode = InterfaceMode.composer

    var body: some View {
        VStack(spacing: 0) {
            TabBar(session: session)
            content
            // 「原生 CLI」档只有终端；Cove 界面没有终端，输入框必须在。
            if interfaceMode.showsComposer || session.chat != nil {
                Composer(session: session)
            }
        }
        .background(SwiftUI.Color.coveBg)
        .onChange(of: session.focusRequest, initial: true) { _, _ in focusTerminalIfNative() }
        .onChange(of: interfaceMode) { _, _ in focusTerminalIfNative() }
    }

    /// 没有 Cove 输入框时，「聚焦输入框」就是聚焦终端本身。
    private func focusTerminalIfNative() {
        guard !interfaceMode.showsComposer, session.chat == nil else { return }
        DispatchQueue.main.async { session.terminal.window?.makeFirstResponder(session.terminal) }
    }


    private var content: some View {
        ZStack {
            if let chat = session.chat {
                ChatView(session: session, chat: chat)
                    .opacity(session.activeTab == .terminal ? 1 : 0)
                    .allowsHitTesting(session.activeTab == .terminal)
            } else {
                TerminalHost(session: session)
                    .opacity(session.activeTab == .terminal ? 1 : 0)
                    .allowsHitTesting(session.activeTab == .terminal)
            }
            if session.isRunning && !session.hasOutput && session.activeTab == .terminal {
                ZStack {
                    session.chat != nil ? SwiftUI.Color.coveBg : SwiftUI.Color(nsColor: session.terminal.nativeBackgroundColor)
                    CoffeeLoader(size: 76, caption: "正在启动 \(session.cli.displayName)…")
                }
                .transition(.opacity)
            }
            if case let .diff(path) = session.activeTab {
                DiffView(path: path, cwd: session.cwd,
                         revision: session.tracker.changes.files.first { $0.path == path }?.editCount ?? 0,
                         delta: session.fileDeltas[path],
                         sendReview: session.isRunning ? { text in
                             session.send(text)
                             session.activeTab = .terminal
                         } : nil)
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
                    Image(systemName: session.chat != nil ? "bubble.left" : "terminal").font(.system(size: 11))
                    Text(session.chat != nil ? "对话" : "Terminal")
                        .font(CoveFont.ui(12, weight: isActive(.terminal) ? .medium : .regular))
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
