import SwiftUI

/// 中栏：状态条、标签（终端 + 打开的 diff）、终端或 diff、输入框。
///
/// 看 diff 时终端并不卸载，只是被盖住；输入框始终在，边看改动边写反馈。
struct SessionPane: View {
    let session: LiveSession
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip(session: session, onRestart: onRestart)
            Rectangle().fill(Color.coveHairline).frame(height: 1)
            if !session.openDiffs.isEmpty {
                TabStrip(session: session)
                Rectangle().fill(Color.coveHairline).frame(height: 1)
            }
            ZStack {
                TerminalHost(session: session)
                    .opacity(session.activeTab == .terminal ? 1 : 0)
                    .allowsHitTesting(session.activeTab == .terminal)
                if case let .diff(path) = session.activeTab {
                    DiffView(path: path, cwd: session.cwd,
                             revision: session.tracker.changes.files.first { $0.path == path }?.editCount ?? 0,
                             onClose: { session.closeDiff(path) })
                }
            }
            Rectangle().fill(Color.coveHairline).frame(height: 1)
            Composer(session: session)
        }
        .background(Color.coveCanvas)
    }
}

private struct TabStrip: View {
    let session: LiveSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tab(.terminal, title: "Terminal", closable: false)
                ForEach(session.openDiffs, id: \.self) { path in
                    tab(.diff(path), title: URL(fileURLWithPath: path).lastPathComponent, closable: true)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(Color.coveCanvas)
    }

    private func tab(_ tab: LiveSession.Tab, title: String, closable: Bool) -> some View {
        let active = session.activeTab == tab
        return HStack(spacing: 6) {
            Button(title) { session.activeTab = tab }
                .buttonStyle(.plain)
                .font(CoveFont.mono(11, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Color.coveInk : Color.coveInkMuted)
            if closable, case let .diff(path) = tab {
                Button {
                    session.closeDiff(path)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.coveInkMuted)
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // 选中标签的底边是一条 2pt 的实线，和状态点、进度格同一套像素语汇。
            Rectangle().fill(active ? Color.coveHarbor : .clear).frame(height: 2)
        }
    }
}
