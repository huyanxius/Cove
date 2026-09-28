import AppKit
import SwiftUI

@main
struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        // 单窗口：选中哪个会话是全局状态，多窗口共享同一个 model 会互相抢选择。
        Window("Cove", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .task {
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
