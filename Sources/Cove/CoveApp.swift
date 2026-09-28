import AppKit
import SwiftUI

@main
struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = AppearanceChoice.system
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        // 单窗口：选中哪个会话是全局状态，多窗口共享同一个 model 会互相抢选择。
        Window("Cove", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onChange(of: appearance, initial: true) { _, choice in NSApp.appearance = choice.nsAppearance }
                .sheet(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
                    OnboardingView().environment(model)
                }
                .task {
                    UsageRelay.install()
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
                Button("New Temporary Session") { model.newScratchSession() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            CommandMenu("Session") {
                Button("Focus Composer") { model.selectedLive?.focusRequest += 1 }
                    .keyboardShortcut("l")
                    .disabled(model.selectedLive == nil)
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
