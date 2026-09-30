import SwiftUI

/// 首次启动的新手引导：四页，讲清 Cove 是什么、输入框怎么用、要给什么权限，最后给出第一步。
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarded") private var onboarded = false
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "cup.and.saucer", title: "欢迎来到 Cove",
             body: "终端里跑的就是原版 claude（也可以是 codex、agy）。Cove 只在外面补上会话列表、好用的输入框、Agent 状态和改动 diff。"),
        Page(symbol: "text.cursor", title: "输入框就是普通输入框",
             body: "鼠标定位、选中、撤销、中文输入法都正常。回车发送，⇧回车换行。输入框为空时，↑↓、esc、tab 会交给 CLI，用来操作它的菜单。"),
        Page(symbol: "lock.open", title: "给 Cove 一次文件夹权限",
             body: "你的项目多在「桌面」「文稿」里。macOS 需要你在 完整磁盘取用 里允许 Cove，会话才能在这些文件夹里启动，diff 也才读得到。"),
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
                if page == 2 {
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
                    Button("继续") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("临时会话") { onboarded = true; model.newScratchSession() }
                    Button("选择项目文件夹…") { onboarded = true; model.chooseDirectoryForNewSession() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 360)
        .background(SwiftUI.Color.coveBg)
        .animation(.easeInOut(duration: 0.2), value: page)
    }
}

enum Onboarding {
    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
