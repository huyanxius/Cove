import CoveCore
import SwiftUI

/// 左栏：按项目（cwd）分组的全部会话，组按最近活动排序。点一下就在原目录里 resume。
///
/// 不用系统 List：它的选中态固定是系统强调色的实底，和暖港/潮汐的中性选中色冲突。
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            search
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !model.scratchSessions.isEmpty {
                        PartitionHeader(title: "临时", systemImage: "bolt")
                        ForEach(model.scratchSessions) { summary in
                            SessionRow(summary: summary, live: model.live[summary.id],
                                       selected: model.selection == summary.id)
                                .onTapGesture { model.selection = summary.id }
                                .contextMenu { menu(for: summary) }
                        }
                    }
                    PartitionHeader(title: "项目", systemImage: "folder")
                    ForEach(model.groups) { group in
                        GroupHeader(name: group.name, count: group.sessions.count + group.hiddenCount)
                            .help(group.key)
                        ForEach(group.sessions) { summary in
                            SessionRow(summary: summary, live: model.live[summary.id],
                                       selected: model.selection == summary.id)
                                .onTapGesture { model.selection = summary.id }
                                .contextMenu { menu(for: summary) }
                        }
                        if group.hiddenCount > 0 {
                            Button("\(group.hiddenCount) more") { model.expandedGroups.insert(group.key) }
                                .buttonStyle(.plain)
                                .font(CoveFont.ui(12))
                                .foregroundStyle(SwiftUI.Color.coveT3)
                                .frame(height: 28)
                                .padding(.leading, 26)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .overlay {
                if !model.hasLoaded { CoffeeLoader(size: 44, caption: "正在读取会话…") }
            }
            footer
        }
        .background(SwiftUI.Color.coveSidebar.ignoresSafeArea())
    }

    private var search: some View {
        @Bindable var model = model
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12))
            TextField("Search sessions", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(CoveFont.ui(12.5))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .focused($searchFocused)
            if model.searchText.isEmpty {
                Text("⌘K").font(CoveFont.mono(10.5))
            } else {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(SwiftUI.Color.coveT3)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SwiftUI.Color.coveRaisedLine))
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SwiftUI.Color.coveLine.frame(height: 1)
            HStack(spacing: 8) {
                footerButton("项目会话", systemImage: "plus", shortcut: "⌘N") { model.chooseDirectoryForNewSession() }
                footerButton("临时", systemImage: "bolt", shortcut: "⌥⌘N") { model.newScratchSession() }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(SwiftUI.Color.coveT2)
                        .frame(width: 30, height: 30)
                        .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SwiftUI.Color.coveRaisedLine))
                }
                .buttonStyle(.plain)
                .help("设置（⌘,）")
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
        }
    }

    private func footerButton(_ title: String, systemImage: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SwiftUI.Color.coveAccent)
                Text(title).font(CoveFont.ui(12, weight: .medium)).foregroundStyle(SwiftUI.Color.coveT1)
                Spacer(minLength: 2)
                Text(shortcut).font(CoveFont.mono(10)).foregroundStyle(SwiftUI.Color.coveT3)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SwiftUI.Color.coveRaisedLine))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// 「临时」「项目」两个大分区的标题，比项目分组标题高一级。
private struct PartitionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(title).font(CoveFont.ui(11.5, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(SwiftUI.Color.coveT2)
        .padding(.leading, 10)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

private struct GroupHeader: View {
    let name: String
    let count: Int

    var body: some View {
        HStack {
            SectionLabel(text: name)
            Spacer()
            Text("\(count)").font(CoveFont.mono(10.5)).foregroundStyle(SwiftUI.Color.coveT3)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 28)
        .padding(.top, 8)
    }
}

private struct SessionRow: View {
    let summary: SessionSummary
    let live: LiveSession?
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Group {
                if let live { PixelDot(state: state(live)) }
            }
            .frame(width: 14, height: 17)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(live?.title ?? summary.title)
                        .font(CoveFont.ui(13))
                        .foregroundStyle(SwiftUI.Color.coveT1)
                        .lineLimit(1)
                    if let live, live.cli != .claude {
                        Text(live.cli.displayName)
                            .font(CoveFont.mono(9))
                            .foregroundStyle(SwiftUI.Color.coveAccent)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SwiftUI.Color.coveAccentDim))
                    }
                }
                meta
                    .font(CoveFont.ui(11))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(background, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: SwiftUI.Color {
        if selected { return .coveSelect }
        return hovering ? SwiftUI.Color.coveSelect.opacity(0.5) : .clear
    }

    private func state(_ live: LiveSession) -> SessionState {
        SessionState(phase: live.tracker.phase, isRunning: live.isRunning)
    }

    /// 打开着的会话说它在干什么；其余的说多久以前、在哪个分支。
    @ViewBuilder private var meta: some View {
        if let live, live.isRunning, state(live) == .waiting {
            Text("等你回复").foregroundStyle(SwiftUI.Color.coveAttn)
        } else if let live, live.isRunning, case let .running(tool, _) = live.tracker.phase {
            detail(tool.verb, branch: live.tracker.gitBranch ?? summary.gitBranch)
        } else if let live, live.isRunning, case .thinking = live.tracker.phase {
            detail("Thinking", branch: live.tracker.gitBranch ?? summary.gitBranch)
        } else {
            detail(Self.relativeTime(summary.lastActivity), branch: summary.gitBranch)
        }
    }

    private func detail(_ lead: String, branch: String?) -> some View {
        HStack(spacing: 0) {
            Text(lead)
            if let branch, !branch.isEmpty, branch != "HEAD" {
                Text(" · ")
                Text(branch).font(CoveFont.mono(10.5))
            }
        }
        .foregroundStyle(selected ? SwiftUI.Color.coveT2 : SwiftUI.Color.coveT3)
    }

    /// 一分钟以内说「刚刚」：格式化器对 0 秒会给出「0 秒后」这种怪话。
    static func relativeTime(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 60 { return "刚刚" }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
