import CoveCore
import SwiftUI

/// 左栏：搜索、按 CLI 筛选、置顶 / 临时 / 项目三个区。整理规则在 `SessionOrganizer`，这里只画。
///
/// 不用系统 List：它的选中态固定是系统强调色的实底，和暖港的中性选中色冲突。
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var renaming: SessionSummary?
    @State private var renameText = ""
    @State private var deleting: SessionSummary?

    var body: some View {
        let sections = model.sections
        VStack(spacing: 0) {
            search
            filterBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.showingArchive {
                        PartitionHeader(title: "已归档", systemImage: "archivebox")
                        if sections.others.isEmpty {
                            emptyNote("没有归档的会话。右键会话选「归档」，它就会收到这里。")
                        }
                        rows(sections.others)
                    } else {
                        if !sections.pinned.isEmpty {
                            PartitionHeader(title: "已置顶", systemImage: "pin")
                            rows(sections.pinned)
                        }
                        if !sections.scratch.isEmpty {
                            PartitionHeader(title: "临时", systemImage: "bolt")
                            rows(sections.scratch)
                        }
                        if model.groupByProject {
                            PartitionHeader(title: "项目", systemImage: "folder")
                            ForEach(model.groups(sections.others)) { group in
                                GroupHeader(name: group.name, count: group.sessions.count + group.hiddenCount)
                                    .help(group.key)
                                rows(group.sessions)
                                if group.hiddenCount > 0 {
                                    Button("还有 \(group.hiddenCount) 个") { model.expandedGroups.insert(group.key) }
                                        .buttonStyle(.plain)
                                        .font(CoveFont.ui(12))
                                        .foregroundStyle(SwiftUI.Color.coveT3)
                                        .frame(height: 28)
                                        .padding(.leading, 26)
                                }
                            }
                        } else {
                            PartitionHeader(title: "全部会话", systemImage: "clock")
                            rows(sections.others)
                        }
                        if sections.pinned.isEmpty && sections.scratch.isEmpty && sections.others.isEmpty && model.hasLoaded {
                            emptyNote(model.searchText.isEmpty ? "这个筛选下还没有会话。" : "没有找到「\(model.searchText)」。")
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
        .alert("重命名会话", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名字", text: $renameText)
            Button("保存") {
                if let renaming { model.rename(renaming.id, to: renameText) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        } message: {
            Text("名字只保存在 Cove 里，不会改动 CLI 的记录。留空恢复原标题。")
        }
        .confirmationDialog("删除这个会话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { summary in
            Button("移到废纸篓", role: .destructive) { model.delete(summary) }
            Button("取消", role: .cancel) {}
        } message: { summary in
            Text("「\(summary.title)」的记录文件会移到废纸篓，可以从废纸篓找回；Cove 的备份也会一起移走。")
        }
    }

    // MARK: 顶部

    private var search: some View {
        @Bindable var model = model
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12))
            TextField("搜索会话", text: $model.searchText)
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
        .padding(.bottom, 8)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
    }

    /// 全部 / Claude / Codex / Agy，右边是归档开关和视图菜单。
    private var filterBar: some View {
        HStack(spacing: 4) {
            FilterPill(title: "全部", selected: model.cliFilter == nil && !model.showingArchive) {
                model.cliFilter = nil
                model.showingArchive = false
            }
            ForEach(CLIKind.allCases) { cli in
                FilterPill(title: cli == .agy ? "Agy" : cli == .claude ? "Claude" : cli.displayName,
                           selected: model.cliFilter == cli && !model.showingArchive, cli: cli) {
                    model.cliFilter = model.cliFilter == cli ? nil : cli
                    model.showingArchive = false
                }
            }
            Spacer(minLength: 2)
            Button {
                model.showingArchive.toggle()
            } label: {
                Image(systemName: model.showingArchive ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 11))
                    .foregroundStyle(model.showingArchive ? SwiftUI.Color.coveAccent : SwiftUI.Color.coveT3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.showingArchive ? "回到会话列表" : "查看已归档的会话")
            Menu {
                Toggle("按项目分组", isOn: Binding(get: { model.groupByProject }, set: { model.groupByProject = $0 }))
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(SwiftUI.Color.coveT3)
            .help("视图")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: 列表

    private func rows(_ summaries: [SessionSummary]) -> some View {
        ForEach(summaries) { summary in
            SessionRow(summary: summary, live: model.live[summary.id],
                       selected: model.selection == summary.id,
                       pinned: model.isPinned(summary.id), unread: model.isUnread(summary.id),
                       archived: model.showingArchive,
                       togglePin: { model.togglePin(summary.id) },
                       toggleArchive: { model.toggleArchive(summary.id) })
                .onTapGesture { model.selection = summary.id }
                .contextMenu { menu(for: summary) }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(CoveFont.ui(12))
            .foregroundStyle(SwiftUI.Color.coveT3)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    // MARK: 底部

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

    // MARK: 右键菜单

    @ViewBuilder private func menu(for summary: SessionSummary) -> some View {
        let id = summary.id
        Button(model.isPinned(id) ? "取消置顶" : "置顶") { model.togglePin(id) }
        Button("重命名…") {
            renameText = summary.title
            renaming = summary
        }
        Button(model.isUnread(id) ? "标为已读" : "标为未读") { model.toggleUnread(id) }
        Button(model.isArchived(id) ? "取消归档" : "归档") { model.toggleArchive(id) }
        Divider()
        if let cwd = summary.cwd, summary.cli == .claude {
            Button("在新工作树中开新会话") { model.newSession(in: URL(fileURLWithPath: cwd), cli: .claude, inWorktree: true) }
        }
        Button("复制恢复命令") { copy(SessionOrganizer.resumeCommand(for: summary)) }
        Button("复制会话 ID") { copy(id) }
        if summary.fileURL.path != "/dev/null", FileManager.default.fileExists(atPath: summary.fileURL.path) {
            Button("在 Finder 中显示记录文件") { NSWorkspace.shared.activateFileViewerSelecting([summary.fileURL]) }
        }
        if let cwd = summary.cwd {
            Button("在 Finder 中显示文件夹") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd) }
        }
        Divider()
        if model.live[id] != nil {
            Button("关闭会话") { model.close(id) }
        }
        Button("删除…", role: .destructive) { deleting = summary }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 筛选条上的一枚：选中时浅底加深，CLI 的带自己的标志。
private struct FilterPill: View {
    let title: String
    let selected: Bool
    var cli: CLIKind?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let cli { CLILogo(cli: cli, size: 12) }
                Text(title).font(CoveFont.ui(11.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? SwiftUI.Color.coveT1 : SwiftUI.Color.coveT2)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(selected ? SwiftUI.Color.coveSelect : hovering ? SwiftUI.Color.coveSelect.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 「置顶」「临时」「项目」这些大分区的标题，比项目分组标题高一级。
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

/// 侧栏一行。行首是状态：干活时小螃蟹在敲键盘，等批准时招手，跑完没看过是一个蓝点。
private struct SessionRow: View {
    let summary: SessionSummary
    let live: LiveSession?
    let selected: Bool
    let pinned: Bool
    let unread: Bool
    let archived: Bool
    let togglePin: () -> Void
    let toggleArchive: () -> Void
    @State private var hovering = false

    /// 这一行现在的状态。Cove 界面的会话看对话进程，终端的看 JSONL 推断的阶段。
    enum Activity: Equatable { case working, approval, waiting, idle, ended, closed }

    private var activity: Activity {
        guard let live else { return .closed }
        guard live.isRunning else { return .ended }
        if let chat = live.chat {
            if chat.log.pendingPermission != nil { return .approval }
            return chat.log.isWorking ? .working : .idle
        }
        switch live.tracker.phase {
        case .thinking, .running: return .working
        case .awaitingUser: return .waiting
        case .idle: return .idle
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            indicator
                .frame(width: 20, height: 17)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(summary.title)
                        .font(CoveFont.ui(13, weight: unread ? .semibold : .regular))
                        .foregroundStyle(SwiftUI.Color.coveT1)
                        .lineLimit(1)
                    if summary.isArchivedOnly {
                        Text("已备份")
                            .font(CoveFont.ui(9.5))
                            .foregroundStyle(SwiftUI.Color.coveT3)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SwiftUI.Color.coveLine))
                            .help("原记录已被 claude 清理，这是 Cove 的备份；点开会先复原")
                    }
                    if summary.cli != .claude {
                        CLILogo(cli: summary.cli, size: 14).help(summary.cli.displayName)
                    }
                }
                meta
                    .font(CoveFont.ui(11))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering {
                HStack(spacing: 2) {
                    if !archived {
                        rowButton(pinned ? "pin.slash" : "pin", help: pinned ? "取消置顶" : "置顶", action: togglePin)
                    }
                    rowButton(archived ? "tray.and.arrow.up" : "archivebox", help: archived ? "取消归档" : "归档", action: toggleArchive)
                }
                .padding(.top, 5)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(background, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var indicator: some View {
        switch activity {
        case .working:
            PixelCrab(mood: .typing).help("正在干活")
        case .approval:
            PixelCrab(mood: .waving).help("在等你批准")
        default:
            if unread {
                Circle().fill(SwiftUI.Color.coveAccent).frame(width: 7, height: 7).padding(.top, 5).help("有新进展")
            } else if activity == .waiting {
                PixelDot(state: .waiting).padding(.top, 6)
            } else if activity == .idle {
                PixelDot(state: .idle).padding(.top, 6)
            } else if pinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(SwiftUI.Color.coveT3).padding(.top, 4)
            }
        }
    }

    private func rowButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5))
                .foregroundStyle(SwiftUI.Color.coveT2)
                .frame(width: 20, height: 20)
                .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var background: SwiftUI.Color {
        if selected { return .coveSelect }
        return hovering ? SwiftUI.Color.coveSelect.opacity(0.5) : .clear
    }

    /// 打开着的会话说它在干什么；其余的说多久以前、在哪个分支。
    @ViewBuilder private var meta: some View {
        switch activity {
        case .approval:
            Text("等你批准").foregroundStyle(SwiftUI.Color.coveAttn)
        case .waiting:
            Text("等你回复").foregroundStyle(SwiftUI.Color.coveAttn)
        case .working:
            if let live, case let .running(tool, _) = live.tracker.phase {
                detail(ToolLine.verb(tool) + " " + tool.detail, branch: nil)
            } else {
                detail("正在干活", branch: live?.tracker.gitBranch ?? summary.gitBranch)
            }
        default:
            detail(Self.relativeTime(summary.lastActivity), branch: live?.tracker.gitBranch ?? summary.gitBranch)
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
