import CoveCore
import SwiftUI

/// 设置窗口（⌘,）：通用、快捷键、关于三页。
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
            PetSettings().tabItem { Label("小螃蟹", systemImage: "pawprint") }
            ShortcutSettings().tabItem { Label("快捷键", systemImage: "keyboard") }
            AboutSettings().tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage("appearance") private var appearance = AppearanceChoice.system
    @AppStorage("defaultCLI") private var defaultCLI = CLIKind.claude.rawValue
    @AppStorage("showUsage") private var showUsage = true
    @AppStorage("backupTranscripts") private var backupTranscripts = true
    @AppStorage("showPet") private var showPet = true
    @AppStorage("interfaceMode") private var interfaceMode = InterfaceMode.composer
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        Form {
            Picker("外观", selection: $appearance) {
                ForEach(AppearanceChoice.allCases) { Text($0.localizedTitle).tag($0) }
            }
            Text("外观只影响之后新开或恢复的会话里 claude 的主题。")
                .font(.caption).foregroundStyle(.secondary)

            Picker("新会话默认使用", selection: $defaultCLI) {
                ForEach(CLIKind.allCases) { Text($0.displayName).tag($0.rawValue) }
            }

            Picker("界面", selection: $interfaceMode) {
                ForEach(InterfaceMode.allCases) { Text($0.title).tag($0) }
            }
            Text(interfaceMode.detail + (interfaceMode == .cove ? "切换会让空闲的 Claude 会话按原 ID 重开，对话不会丢。" : ""))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("备份会话记录", isOn: $backupTranscripts)
            Text("claude 默认会删掉 30 天前的会话记录。开着时 Cove 每 5 分钟镜像一份，被删的会话仍列在侧栏、点开即恢复。APFS 上是文件克隆，原件还在时几乎不占空间。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("右下角显示用量圆环", isOn: $showUsage)
            Toggle("右下角显示 Claude 小螃蟹", isOn: $showPet)

            LabeledContent("临时会话目录") {
                Button("在 Finder 中显示") {
                    try? FileManager.default.createDirectory(at: ScratchSpace.defaultRoot, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(ScratchSpace.defaultRoot)
                }
            }
            LabeledContent("完整磁盘取用") {
                Button("打开隐私设置") { Onboarding.openFullDiskAccess() }
            }
            LabeledContent("新手引导") {
                Button("重新显示") { onboarded = false }
            }
        }
        .formStyle(.grouped)
    }
}

/// 五种状态并排演示，也是调动画时的预览台。
private struct PetSettings: View {
    @AppStorage("showPet") private var showPet = true
    private let moods: [(PixelCrab.Mood, String)] = [
        (.idle, "待命"), (.working, "干活"), (.thinking, "思考"), (.waving, "等你"), (.sleeping, "打盹"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.1) { mood, label in
                    VStack(spacing: 6) {
                        PixelCrab(mood: mood).frame(width: 84, height: 64)
                        Text(label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 20)
            Toggle("在右下角显示小螃蟹", isOn: $showPet)
            Text("小螃蟹跟着当前会话的状态变动作；旁边是这次会话的工作时长、token 和按 API 价格估算的花费。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShortcutSettings: View {
    private let rows: [(String, String)] = [
        ("⌘N", "新建项目会话（选择文件夹）"),
        ("⌥⌘N", "新建临时会话"),
        ("⇧⌘N", "在新工作树里新建会话（并行、互不踩文件）"),
        ("⌘K", "搜索会话"),
        ("⌘L", "聚焦输入框"),
        ("⌘1", "回到终端标签"),
        ("⌘/", "切到 CLI 自己的输入框 / 切回来"),
        ("⇧⌘C", "复制上一条回复的原文"),
        ("⇧⌘M", "Cove 界面：切换权限模式"),
        ("esc", "Cove 界面：停止当前这一轮"),
        ("⌥⌘I", "显示/隐藏检查器"),
        ("⇧⌘W", "关闭当前会话"),
        ("↩ / ⇧↩", "发送 / 换行"),
        ("输入框为空时 ↑↓ esc tab", "交给 CLI 的菜单"),
        ("输入框为空时 / 或 !", "交给 CLI 的输入框，执行后回来"),
    ]

    var body: some View {
        Form {
            ForEach(rows, id: \.0) { key, action in
                LabeledContent(action) { Text(key).font(.system(.body, design: .monospaced)) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Cove").font(CoveFont.display(22, weight: .medium))
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption).foregroundStyle(.secondary)
            Text("原版 CLI 外面的一层原生外壳：会话、输入、状态与改动。")
                .font(.callout).foregroundStyle(.secondary)
            Link("github.com/huyanxius/Cove", destination: URL(string: "https://github.com/huyanxius/Cove")!)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AppearanceChoice {
    var localizedTitle: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}
