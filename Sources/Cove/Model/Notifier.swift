import AppKit
import CoveCore
import UserNotifications

/// 会话做完或卡在权限确认上、而你没在看它时，发一条系统通知；点通知回到那个会话。
///
/// 只在 `.app` 里工作：`swift run` 直接跑的可执行文件没有 bundle，通知中心不认。
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// 点了通知之后要选中的会话。
    var onOpen: ((String) -> Void)?
    private var attention: [String: Attention] = [:]
    private var authorized = false

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func install() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// 每次轮询把每个打开着的会话的状态喂进来；返回这一轮发生的变化（给侧栏的未读点用）。
    @discardableResult
    func observe(_ sessions: [LiveSession], selected: String?) -> [(String, Attention.Event)] {
        var events: [(String, Attention.Event)] = []
        let alive = Set(sessions.map(\.id))
        attention = attention.filter { alive.contains($0.key) }
        for session in sessions where session.isRunning {
            var tracker = attention[session.id] ?? Attention()
            let event = tracker.observe(state(of: session))
            attention[session.id] = tracker
            guard let event else { continue }
            events.append((session.id, event))
            // 正看着它就不打扰。
            if NSApp.isActive && selected == session.id { continue }
            post(event, for: session)
        }
        return events
    }

    private func state(of session: LiveSession) -> Attention.State {
        if let chat = session.chat {
            if chat.log.pendingPermission != nil { return .needsApproval }
            return chat.log.isWorking ? .working : .idle
        }
        switch session.tracker.phase {
        case .thinking, .running: return .working
        case .idle, .awaitingUser: return .idle
        }
    }

    private func post(_ event: Attention.Event, for session: LiveSession) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = session.title
        switch event {
        case .finished: content.body = "做完了，轮到你。"
        case .needsApproval:
            content.body = session.chat?.log.pendingPermission.map { "等你批准：\($0.toolName) \($0.summary)" } ?? "等你批准。"
        }
        content.userInfo = ["session": session.id]
        let request = UNNotificationRequest(identifier: "\(session.id)-\(Date.now.timeIntervalSince1970)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        if authorized {
            center.add(request)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self.authorized = true }
            center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let id { self.onOpen?(id) }
        }
        completionHandler()
    }
}
