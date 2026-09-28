import CoveCore
import SwiftUI

/// 左栏：按项目（cwd）分组的全部会话，组按最近活动排序。点一下就在原目录里 resume。
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.sessions) { summary in
                        SessionRow(summary: summary, live: model.live[summary.id])
                            .tag(summary.id)
                            .contextMenu { menu(for: summary) }
                    }
                    if group.hiddenCount > 0 {
                        Button("\(group.hiddenCount) more") { model.expandedGroups.insert(group.key) }
                            .buttonStyle(.plain)
                            .font(CoveFont.mono(10))
                            .foregroundStyle(Color.coveInkMuted)
                            .padding(.leading, 17)
                    }
                } header: {
                    SectionLabel(text: group.name)
                        .help(group.key)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.coveSidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search sessions")
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay {
            if !model.hasLoaded { ProgressView().controlSize(.small) }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.coveHairline).frame(height: 1)
            HStack {
                Button {
                    model.chooseDirectoryForNewSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.coveHarbor)
                Spacer()
                Text("\(model.totalSessionCount)")
                    .font(CoveFont.mono(10))
                    .foregroundStyle(Color.coveInkMuted)
                    .help("Sessions on this Mac")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color.coveSidebar)
    }

    @ViewBuilder private func menu(for summary: SessionSummary) -> some View {
        if model.live[summary.id] != nil {
            Button("Close Session") { model.close(summary.id) }
        }
        if let cwd = summary.cwd {
            Button("Reveal Folder in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
            }
        }
        Button("Copy Session ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary.id, forType: .string)
        }
    }
}

private struct SessionRow: View {
    let summary: SessionSummary
    let live: LiveSession?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let live {
                    PixelDot(state: PixelDot.State(phase: live.tracker.phase, isRunning: live.isRunning))
                } else {
                    Color.clear
                }
            }
            .frame(width: 9, height: 9)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }

            VStack(alignment: .leading, spacing: 2) {
                Text(live?.title ?? summary.title)
                    .font(CoveFont.title(13))
                    .foregroundStyle(Color.coveInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(CoveFont.mono(10))
                    .foregroundStyle(Color.coveInkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let time = Self.relative.localizedString(for: min(summary.lastActivity, .now), relativeTo: .now)
        guard let branch = summary.gitBranch, !branch.isEmpty, branch != "HEAD" else { return time }
        return "\(time) · \(branch)"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
