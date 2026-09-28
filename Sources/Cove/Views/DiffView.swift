import CoveCore
import SwiftUI

/// 一个文件相对 HEAD 的差异。`revision` 是 Agent 对这个文件的编辑次数，
/// 它一变就重新取 diff，所以 Agent 边改这里边跟着刷新。
struct DiffView: View {
    let path: String
    let cwd: String
    let revision: Int
    let delta: LineDelta?

    @State private var result: Git.DiffResult?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.coveLine).frame(height: 1)
            content
        }
        .background(Color.coveBg)
        .task(id: "\(path)#\(revision)") { result = await Git.diff(path: path) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(CoveFont.ui(14, weight: .semibold))
                .foregroundStyle(Color.coveT1)
            Text(displayDirectory)
                .font(CoveFont.mono(11))
                .foregroundStyle(Color.coveT3)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if let delta {
                Text("+\(delta.added)").foregroundStyle(Color.coveAdd).font(CoveFont.mono(11))
                Text("−\(delta.removed)").foregroundStyle(Color.coveDel).font(CoveFont.mono(11))
            }
            Button {
                Task { result = await Git.diff(path: path) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload diff")
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Open in default editor")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        switch result {
        case nil:
            CoffeeLoader(size: 56, caption: "正在读取改动…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unchanged:
            message("No changes against HEAD.", detail: "The edits may already be committed, or were reverted.")
        case .notRepository:
            message("Not a git repository.", detail: "Cove reads diffs from git. Open the file to review it directly.")
        case let .failed(reason):
            message("Couldn't load the diff.", detail: reason)
        case let .outsideRepository(lines):
            VStack(spacing: 0) {
                Text("这个文件不在 git 仓库里，没有旧版本可比，下面是它现在的全文。")
                    .font(CoveFont.ui(11.5))
                    .foregroundStyle(Color.coveT3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.coveAccentDim.opacity(0.5))
                lineList(lines)
            }
        case let .diff(lines):
            lineList(lines)
        }
    }

    private func lineList(_ lines: [DiffLine]) -> some View {
        Group {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.kind != .meta || line.text.hasPrefix("\\") {
                            DiffRow(line: line)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(CoveFont.ui(14, weight: .medium)).foregroundStyle(Color.coveT1)
            Text(detail).font(CoveFont.ui(12)).foregroundStyle(Color.coveT3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayDirectory: String {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if directory.hasPrefix(cwd) {
            let relative = String(directory.dropFirst(cwd.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? "./" : relative + "/"
        }
        return (directory as NSString).abbreviatingWithTildeInPath + "/"
    }
}

private struct DiffRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldLine)
            number(line.newLine)
            Text(marker)
                .frame(width: 18)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .hunk || line.kind == .meta ? Color.coveT3 : Color.coveT1)
                .fixedSize()
                .padding(.trailing, 24)
        }
        .font(CoveFont.mono(12))
        .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
        .background(background)
        .textSelection(.enabled)
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(Color.coveT3.opacity(0.6))
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        default: ""
        }
    }

    private var markerColor: Color {
        line.kind == .added ? .coveAdd : .coveDel
    }

    private var background: Color {
        switch line.kind {
        case .added: .coveAdd.opacity(0.11)
        case .removed: .coveDel.opacity(0.11)
        case .hunk: .coveAccentDim
        default: .clear
        }
    }
}
