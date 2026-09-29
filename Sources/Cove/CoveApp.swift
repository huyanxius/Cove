import AppKit
import CoveCore
import SwiftUI

@main
struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = AppearanceChoice.system
    @AppStorage("interfaceMode") private var interfaceMode = InterfaceMode.composer
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        // 单窗口：选中哪个会话是全局状态，多窗口共享同一个 model 会互相抢选择。
        Window("Cove", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onChange(of: appearance, initial: true) { _, choice in
                    NSApp.appearance = choice.nsAppearance
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.reconcileTones() }
                }
                .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
                    // 跟随系统时，系统切深浅色也要让会话跟上。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.reconcileTones() }
                }
                .onChange(of: interfaceMode) { _, _ in model.reconcileSurfaces() }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                    model.checkAttention()
                }
                .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                    // 正在干活而被跳过的会话，等它空下来再补上。
                    model.reconcileTones()
                    model.reconcileSurfaces()
                }
                .sheet(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
                    OnboardingView().environment(model)
                }
                .task {
                    UsageRelay.install()
                    Notifier.shared.install()
                    Notifier.shared.onOpen = { id in model.selection = id }
                    delegate.model = model
                    model.startRefreshing()
                    model.handleLaunchArguments()
                }
        }
        .defaultSize(width: 1380, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.chooseDirectoryForNewSession() }
                    .keyboardShortcut("n")
                Button("New Session in Worktree…") { model.chooseDirectoryForNewSession(inWorktree: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Temporary Session") { model.newScratchSession() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .sidebar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Interface", selection: $interfaceMode) {
                    ForEach(InterfaceMode.allCases) { Text($0.title).tag($0) }
                }
            }
            CommandMenu("Session") {
                Button("Focus Composer") { model.selectedLive?.focusRequest += 1 }
                    .keyboardShortcut("l")
                    .disabled(model.selectedLive == nil)
                Button(model.selectedLive?.directInput == nil ? "Use CLI Input" : "Use Cove Input") {
                    model.selectedLive?.toggleNativeInput()
                }
                .keyboardShortcut("/")
                .disabled(model.selectedLive?.isRunning != true)
                Button("Cycle Permission Mode") {
                    guard let chat = model.selectedLive?.chat else { return }
                    chat.setPermissionMode((chat.permissionMode ?? .default).next)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.selectedLive?.chat == nil)
                Button("Raise Effort") {
                    guard let chat = model.selectedLive?.chat, !chat.effortLevels.isEmpty else { return }
                    let levels = chat.effortLevels
                    let index = chat.effortLevel.flatMap { levels.firstIndex(of: $0) } ?? levels.count / 2 - 1
                    chat.setEffort(levels[(index + 1) % levels.count])
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedLive?.chat == nil)
                Button("Copy Last Reply") { model.copyLastReply() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.selectedLive?.cli != .claude)
                Button("Show Terminal") { model.selectedLive?.activeTab = .terminal }
                    .keyboardShortcut("1")
                    .disabled(model.selectedLive == nil)
                Divider()
                Button("Toggle Inspector") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Close Session") {
                    if let id = model.selection { model.close(id) }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.selectedLive == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { LoaderRenderer.renderIfRequested() }
        // Cove 界面的 claude 进程退出后，再往它的 stdin 写会收到 SIGPIPE，默认处理是杀掉整个 App。
        signal(SIGPIPE, SIG_IGN)
        InterfaceMode.migrateStoredPreference()
        // `swift run` 直接跑可执行文件时没有 bundle，得手动变成前台 App。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.applicationIconImage == nil || Bundle.main.bundleIdentifier == nil,
           let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.terminateAll() }
    }
}

extension InterfaceMode {
    static var current: InterfaceMode {
        UserDefaults.standard.string(forKey: "interfaceMode").flatMap(InterfaceMode.init) ?? .composer
    }

    /// 旧版的「隐藏 CLI 自带的输入框」开关换算成界面档位，只做一次。
    static func migrateStoredPreference(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: "interfaceMode") == nil else { return }
        let legacy = defaults.object(forKey: "hideCLIPrompt") as? Bool
        defaults.set(migrated(hideCLIPrompt: legacy).rawValue, forKey: "interfaceMode")
        defaults.removeObject(forKey: "hideCLIPrompt")
    }

    var title: String {
        switch self {
        case .native: "原生 CLI"
        case .nativeWithComposer: "原生 CLI + Cove 输入框"
        case .composer: "Cove 输入框替代 CLI 输入框"
        case .cove: "Cove 界面"
        }
    }

    var detail: String {
        switch self {
        case .native: "只有终端，键盘直接进 CLI，和在终端 App 里用完全一样。"
        case .nativeWithComposer: "终端照原样显示，下面多一个 Cove 输入框：中文输入、多行编辑、拖文件更顺手。"
        case .composer: "遮住 CLI 自带的输入区和状态栏，只用 Cove 的输入框；弹出选择菜单时会自动露出来。"
        case .cove: "类似 Claude 桌面版的对话界面：逐字输出、原生权限确认。只对 Claude 会话生效，codex / agy 按上一档显示；TUI 专属的面板（/model 选择器等）在这一档里用不了。"
        }
    }
}

/// 外观：跟随系统，或固定浅色 / 深色。只影响新开或恢复的会话里 claude 的主题。
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
