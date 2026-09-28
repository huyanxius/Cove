import CoveCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 360)
        } detail: {
            Group {
                if let session = model.selectedLive {
                    SessionPane(session: session)
                        .id(session.id)
                } else {
                    WelcomeView()
                }
            }
            .inspector(isPresented: $model.showInspector) {
                InspectorView(session: model.selectedLive, usage: model.latestUsage)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
        }
        .navigationTitle(model.selectedLive?.title ?? "Cove")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let session = model.selectedLive {
                    ActivityPill(session: session)
                        .onTapGesture(count: 2) {
                            if !session.isRunning { model.restart(session.id) }
                        }
                        .help(session.isRunning ? "" : "双击恢复会话")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("设置（⌘,）")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("显示/隐藏检查器（⌥⌘I）")
            }
        }
        .toolbarBackground(SwiftUI.Color.coveBg, for: .windowToolbar)
        .tint(.coveAccent)
    }

    private var subtitle: String {
        guard let session = model.selectedLive else { return "" }
        let folder = (session.cwd as NSString).abbreviatingWithTildeInPath
        guard let branch = session.tracker.gitBranch else { return folder }
        return "\(folder) · \(branch)"
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.hasLoaded, let cup = Brand.cupMark {
                    Image(nsImage: cup).resizable().interpolation(.high).scaledToFit()
                } else {
                    CoffeeLoader(size: 110)
                }
            }
            .frame(width: 110, height: 114)
            .accessibilityHidden(true)
            Text("Cove")
                .font(CoveFont.display(30, weight: .medium))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .padding(.top, 20)
            Text("A harbor for your Claude Code sessions.")
                .font(CoveFont.display(15))
                .foregroundStyle(SwiftUI.Color.coveT2)
                .padding(.top, 6)
            HStack(spacing: 10) {
                Button {
                    model.chooseDirectoryForNewSession()
                } label: {
                    Text("New Session…")
                        .font(CoveFont.ui(13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(SwiftUI.Color.coveAccentFill, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n")
                if let latest = model.sessions.first {
                    Button {
                        model.selection = latest.id
                    } label: {
                        Text("继续「\(String(latest.title.prefix(24)))」")
                            .font(CoveFont.ui(13))
                            .foregroundStyle(SwiftUI.Color.coveT1)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SwiftUI.Color.coveRaisedLine))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 28)
            if model.hasLoaded {
                Text("\(model.totalSessionCount) sessions · \(model.projectCount) projects")
                    .font(CoveFont.mono(10.5))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color.coveBg)
    }
}
