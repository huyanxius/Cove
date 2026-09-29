import AppKit
import SwiftUI

/// 顶栏「打开于」：把会话文件夹交给编辑器、终端或 Finder。只列本机装了的。
struct OpenInMenu: View {
    let folder: String

    /// bundle id 是查安装位置用的，名字是菜单上显示的。顺序即菜单顺序：编辑器、终端、Finder。
    private static let candidates: [(id: String, name: String)] = [
        ("com.microsoft.VSCode", "VS Code"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("dev.zed.Zed", "Zed"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.apple.Terminal", "终端"),
    ]

    var body: some View {
        Menu {
            ForEach(installed, id: \.id) { app in
                Button(app.name) { open(with: app.url) }
            }
            Divider()
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
            Button("拷贝路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder, forType: .string)
            }
        } label: {
            Label("打开于", systemImage: "arrow.up.forward.app")
        }
        .help("在其他应用中打开这个文件夹")
    }

    private var installed: [(id: String, name: String, url: URL)] {
        Self.candidates.compactMap { candidate in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.id).map { (candidate.id, candidate.name, $0) }
        }
    }

    private func open(with app: URL) {
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
