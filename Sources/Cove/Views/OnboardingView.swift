import CoveCore
import SwiftUI

/// 首次启动时先选已安装并登录的 CLI，再介绍输入与文件夹访问。
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("defaultCLI") private var defaultCLI = CLIKind.claude.rawValue
    @State private var page = 0
    @State private var setup = CLISetup()

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "cup.and.saucer", title: "欢迎来到 Cove",
             body: "给你的编程 Agent 一个原生 Mac 工作台：找回会话，顺手写提示词，直接审阅改动。Cove 沿用 CLI 的登录与配置。"),
        Page(symbol: "terminal", title: "先准备一个 CLI",
             body: "Cove 不包含模型或 CLI。请先在终端安装并登录 Claude Code 或 Codex，确认能正常对话，再选择新会话默认使用的工具。已有 agy 的用户也可以选择 Antigravity。"),
        Page(symbol: "text.cursor", title: "输入框就是普通输入框",
             body: "鼠标定位、选中、撤销、中文输入法都正常。回车发送，⇧回车换行。输入框为空时，↑↓、esc、tab 会交给 CLI，用来操作它的菜单。"),
        Page(symbol: "lock.open", title: "给 Cove 一次文件夹权限",
             body: "先用你允许 Cove 访问的项目文件夹。如果「桌面」「文稿」里的会话启动失败，可以在系统隐私设置中允许 Cove 访问，再重开会话。"),
        Page(symbol: "sparkles", title: "开始吧",
             body: "⌘N 在某个项目文件夹里开会话，按文件夹归类；⌥⌘N 开一个临时会话，随手问问。右下角能看到用量和小螃蟹。"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            let current = pages[page]
            VStack(spacing: 16) {
                Image(systemName: current.symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(SwiftUI.Color.coveAccent)
                    .frame(height: 44)
                Text(current.title).font(CoveFont.ui(20, weight: .semibold)).foregroundStyle(SwiftUI.Color.coveT1)
                Text(current.body)
                    .font(CoveFont.ui(13.5))
                    .foregroundStyle(SwiftUI.Color.coveT2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 380)
                if page == 1 {
                    Picker("默认 CLI", selection: $defaultCLI) {
                        ForEach(CLIKind.allCases) { cli in
                            Text(cli.displayName).tag(cli.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                    HStack(spacing: 8) {
                        if setup.isChecking {
                            ProgressView().controlSize(.small)
                            Text("正在检查已安装的 CLI…")
                        } else {
                            Image(systemName: selectedCLIIsInstalled ? "checkmark.circle" : "exclamationmark.circle")
                            Text(selectedCLIIsInstalled ? "已检测到安装；请确认已在终端登录" : "未检测到所选 CLI；安装后重新检测")
                            Button("重新检测") { Task { await checkInstallation() } }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(SwiftUI.Color.coveT2)
                    HStack(spacing: 20) {
                        Link("安装 Claude Code", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                        Link("安装 Codex", destination: URL(string: "https://developers.openai.com/codex/cli/")!)
                    }
                    .font(.caption)
                }
                if page == 3 {
                    Button("打开「完整磁盘取用」") { Onboarding.openFullDiskAccess() }
                        .controlSize(.large)
                }
            }
            .padding(.top, 36)
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Rectangle()
                            .fill(index == page ? SwiftUI.Color.coveAccent : SwiftUI.Color.coveLine)
                            .frame(width: index == page ? 14 : 6, height: 6)
                    }
                }
                Spacer()
                if page > 0 { Button("上一步") { page -= 1 } }
                if page < pages.count - 1 {
                    Button("继续") { page += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(page == 1 && (setup.isChecking || !selectedCLIIsInstalled))
                } else {
                    Button("临时会话") { onboarded = true; model.newScratchSession() }
                    Button("选择项目文件夹…") { onboarded = true; model.chooseDirectoryForNewSession() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 480)
        .background(SwiftUI.Color.coveBg)
        .animation(.easeInOut(duration: 0.2), value: page)
        .task { await checkInstallation() }
    }
    private var selectedCLIIsInstalled: Bool {
        CLIKind(rawValue: defaultCLI).map { setup.installed.contains($0) } ?? false
    }

    private func checkInstallation() async {
        await setup.refresh()
        let current = CLIKind(rawValue: defaultCLI) ?? .claude
        defaultCLI = CLIAvailability.preferred(current, installed: setup.installed).rawValue
    }
}

enum Onboarding {
    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
