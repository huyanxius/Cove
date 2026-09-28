import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            Group {
                if let session = model.selectedLive {
                    SessionPane(session: session, onRestart: { model.restart(session.id) })
                        .id(session.id)
                } else {
                    WelcomeView()
                }
            }
            .inspector(isPresented: $model.showInspector) {
                InspectorView(session: model.selectedLive)
                    .inspectorColumnWidth(min: 240, ideal: 290, max: 420)
            }
        }
        .navigationTitle(model.selectedLive?.title ?? "Cove")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.chooseDirectoryForNewSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New Session (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (⌥⌘I)")
            }
        }
        .tint(.coveHarbor)
    }

    private var subtitle: String {
        guard let session = model.selectedLive else { return "" }
        return (session.cwd as NSString).abbreviatingWithTildeInPath
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            PixelLogo(cell: 5)
            VStack(spacing: 6) {
                Text("Cove")
                    .font(CoveFont.title(30, weight: .medium))
                    .foregroundStyle(Color.coveInk)
                Text("A harbor for your Claude Code sessions.")
                    .font(CoveFont.title(15))
                    .foregroundStyle(Color.coveInkMuted)
            }
            HStack(spacing: 10) {
                Button("New Session…") { model.chooseDirectoryForNewSession() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n")
                if let latest = model.sessions.first {
                    Button("Resume “\(latest.title.prefix(28))”") { model.selection = latest.id }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .padding(.top, 6)
            if model.hasLoaded {
                Text("\(model.totalSessionCount) sessions · \(model.projectCount) projects on this Mac")
                    .font(CoveFont.mono(10))
                    .foregroundStyle(Color.coveInkMuted)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.coveCanvas)
    }
}
