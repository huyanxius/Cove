import CoveCore
import SwiftUI

/// 右栏：任务清单、本会话改过的文件、会话信息。点文件在中栏打开 diff。
struct InspectorView: View {
    let session: LiveSession?

    var body: some View {
        ScrollView {
            if let session {
                VStack(alignment: .leading, spacing: 24) {
                    TasksSection(board: session.tracker.board)
                    ChangesSection(session: session)
                    InfoSection(session: session)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Select a session to see its tasks and changes.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coveInkMuted)
                    .padding(16)
            }
        }
        .background(Color.coveCanvas)
    }
}

private struct TasksSection: View {
    let board: TaskBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Tasks")
                Spacer()
                if !board.tasks.isEmpty {
                    Text("\(board.completedCount)/\(board.tasks.count)")
                        .font(CoveFont.mono(10)).foregroundStyle(Color.coveInkMuted)
                }
            }
            if board.tasks.isEmpty {
                Text("Claude lists tasks here when it plans multi-step work.")
                    .font(.system(size: 12)).foregroundStyle(Color.coveInkMuted)
            } else {
                ForEach(board.tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PixelProgress(tasks: [task]).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(task.subject)
                            .font(.system(size: 12.5, weight: task.status == .inProgress ? .medium : .regular))
                            .foregroundStyle(task.status == .completed ? Color.coveInkMuted : Color.coveInk)
                            .strikethrough(task.status == .completed, color: .coveInkMuted.opacity(0.5))
                            .lineLimit(3)
                    }
                }
            }
        }
    }
}

private struct ChangesSection: View {
    let session: LiveSession

    var body: some View {
        let files = session.tracker.changes.files
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Changes")
                Spacer()
                if !files.isEmpty {
                    Text("\(files.count) files").font(CoveFont.mono(10)).foregroundStyle(Color.coveInkMuted)
                }
            }
            .padding(.bottom, 4)
            if files.isEmpty {
                Text("Files Claude edits in this session appear here.")
                    .font(.system(size: 12)).foregroundStyle(Color.coveInkMuted)
            } else {
                ForEach(files) { file in
                    FileRow(file: file, cwd: session.cwd, selected: session.activeTab == .diff(file.path)) {
                        session.openDiff(file.path)
                    }
                }
            }
        }
    }
}

private struct FileRow: View {
    let file: FileChange
    let cwd: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.coveInk)
                        .lineLimit(1)
                    Text(directory)
                        .font(CoveFont.mono(10))
                        .foregroundStyle(Color.coveInkMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                if file.created {
                    tag("NEW")
                } else if file.editCount > 1 {
                    Text("×\(file.editCount)").font(CoveFont.mono(10)).foregroundStyle(Color.coveInkMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.coveHarborWash : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .help(file.path)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(CoveFont.mono(9, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Color.coveHarbor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(Rectangle().strokeBorder(Color.coveHarbor.opacity(0.5), lineWidth: 1))
    }

    private var directory: String {
        let dir = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
        if dir == cwd { return "./" }
        if dir.hasPrefix(cwd + "/") { return String(dir.dropFirst(cwd.count + 1)) + "/" }
        return (dir as NSString).abbreviatingWithTildeInPath + "/"
    }
}

private struct InfoSection: View {
    let session: LiveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Session")
            row("Folder", (session.cwd as NSString).abbreviatingWithTildeInPath)
            row("ID", session.id)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.coveInkMuted)
            Text(value).font(CoveFont.mono(11)).foregroundStyle(Color.coveInk).textSelection(.enabled)
        }
    }
}
