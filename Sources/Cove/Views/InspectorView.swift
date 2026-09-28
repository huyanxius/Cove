import CoveCore
import SwiftUI

/// 右栏：任务、本会话改过的文件（点开看 diff）、会话信息。会话信息钉在底部。
struct InspectorView: View {
    let session: LiveSession?

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                ScrollView {
                    VStack(spacing: 0) {
                        TasksSection(board: session.tracker.board)
                        SwiftUI.Color.coveLine.frame(height: 1)
                        ChangesSection(session: session)
                    }
                }
                SwiftUI.Color.coveLine.frame(height: 1)
                InfoSection(session: session)
            } else {
                Text("选中一个会话，这里会显示它的任务和改动。")
                    .font(CoveFont.ui(12))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .padding(16)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SwiftUI.Color.coveBg)
    }
}

private struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            SectionLabel(text: title)
            Spacer()
            trailing.font(CoveFont.mono(11))
        }
        .frame(height: 20)
        .padding(.bottom, 8)
    }
}

private struct TasksSection: View {
    let board: TaskBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Tasks") {
                if !board.tasks.isEmpty {
                    Text("\(board.completedCount)/\(board.tasks.count)").foregroundStyle(SwiftUI.Color.coveT2)
                }
            }
            if board.tasks.isEmpty {
                Text("Claude 规划多步工作时，任务会列在这里。")
                    .font(CoveFont.ui(12))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .padding(.bottom, 4)
            } else {
                SegmentedProgress(tasks: board.tasks)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                ForEach(board.tasks) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

private struct TaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack(spacing: 10) {
            glyph.frame(width: 12)
            Text(task.subject)
                .font(CoveFont.ui(12.5, weight: task.status == .inProgress ? .medium : .regular))
                .foregroundStyle(task.status == .inProgress ? SwiftUI.Color.coveT1 : SwiftUI.Color.coveT2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if task.status == .inProgress {
                Text("进行中").font(CoveFont.ui(10.5, weight: .medium)).foregroundStyle(SwiftUI.Color.coveAccent)
            }
        }
        .frame(height: 28)
        .help(task.subject)
    }

    @ViewBuilder private var glyph: some View {
        switch task.status {
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(SwiftUI.Color.coveAccent)
        case .inProgress:
            Rectangle().fill(SwiftUI.Color.coveAccent).frame(width: 6, height: 6)
        case .pending:
            Rectangle().strokeBorder(SwiftUI.Color.coveT3, lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}

private struct ChangesSection: View {
    let session: LiveSession

    var body: some View {
        let files = session.tracker.changes.files
        let total = session.totalDelta
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Changes") {
                if !files.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(files.count) files").foregroundStyle(SwiftUI.Color.coveT2)
                        if total.added + total.removed > 0 {
                            Text("+\(total.added)").foregroundStyle(SwiftUI.Color.coveAdd)
                            Text("−\(total.removed)").foregroundStyle(SwiftUI.Color.coveDel)
                        }
                    }
                }
            }
            if files.isEmpty {
                Text("Claude 在这个会话里改过的文件会出现在这里。")
                    .font(CoveFont.ui(12))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .padding(.bottom, 4)
            } else {
                ForEach(files) { file in
                    FileRow(file: file, delta: session.fileDeltas[file.path], cwd: session.cwd,
                            selected: session.activeTab == .diff(file.path)) {
                        session.openDiff(file.path)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

private struct FileRow: View {
    let file: FileChange
    let delta: LineDelta?
    let cwd: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(CoveFont.ui(12.5, weight: .medium))
                        .foregroundStyle(SwiftUI.Color.coveT1)
                        .lineLimit(1)
                    Text(directory)
                        .font(CoveFont.mono(10.5))
                        .foregroundStyle(SwiftUI.Color.coveT3)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    if let delta {
                        HStack(spacing: 6) {
                            if delta.added > 0 { Text("+\(delta.added)").foregroundStyle(SwiftUI.Color.coveAdd) }
                            if delta.removed > 0 { Text("−\(delta.removed)").foregroundStyle(SwiftUI.Color.coveDel) }
                        }
                        .font(CoveFont.mono(11))
                    }
                    if file.created {
                        Text("NEW")
                            .font(CoveFont.mono(9.5))
                            .tracking(0.4)
                            .foregroundStyle(SwiftUI.Color.coveAccent)
                            .padding(.horizontal, 3)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SwiftUI.Color.coveAccentDim))
                    } else if file.editCount > 1 {
                        Text("×\(file.editCount)").font(CoveFont.mono(10)).foregroundStyle(SwiftUI.Color.coveT3)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .help(file.path)
    }

    private var background: SwiftUI.Color {
        if selected { return .coveSelect }
        return hovering ? SwiftUI.Color.coveSelect.opacity(0.5) : .clear
    }

    private var directory: String {
        let dir = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
        if dir == cwd { return "./" }
        if dir.hasPrefix(cwd + "/") { return String(dir.dropFirst(cwd.count + 1)) }
        return (dir as NSString).abbreviatingWithTildeInPath
    }
}

private struct InfoSection: View {
    let session: LiveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Session") { EmptyView() }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                row("Folder", (session.cwd as NSString).abbreviatingWithTildeInPath)
                if let branch = session.tracker.gitBranch { row("Branch", branch) }
                if let model = session.tracker.model { row("Model", ActivityTracker.displayName(forModel: model)) }
                row("ID", session.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(CoveFont.ui(12)).foregroundStyle(SwiftUI.Color.coveT3)
            Text(value)
                .font(CoveFont.mono(11.5))
                .foregroundStyle(SwiftUI.Color.coveT1)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
