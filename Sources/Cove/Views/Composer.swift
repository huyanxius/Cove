import AppKit
import CoveCore
import SwiftUI

/// 原生输入框：一个真正的 NSTextView，所以鼠标定位、选区、剪切、撤销、输入法都是系统行为。
///
/// 按键先过 `KeyRouter`：输入框为空时方向键等交给终端里的 claude（操作它的菜单），
/// 有内容时一切归输入框。Enter 提交，⇧↩ / ⌥↩ 换行。
struct Composer: View {
    let session: LiveSession
    @State private var height: CGFloat = ComposerField.minHeight
    /// 斜杠命令候选里当前选中的那一条；草稿一变就回到第一条。
    @State private var selectedSuggestion = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 10) {
            if !suggestions.isEmpty {
                SlashSuggestions(commands: suggestions, selected: selectedIndex) { pick($0) }
            }
            ComposerField(text: $session.draft, height: $height, focusRequest: session.focusRequest,
                          placeholder: session.isRunning ? "Message \(cliName)…" : "会话已结束",
                          terminalRouting: session.chat == nil,
                          applicationCursor: { session.applicationCursor },
                          onSubmit: submit,
                          onPassthrough: { session.sendRaw($0) },
                          onHandoff: { session.beginDirectInput($0) },
                          onTab: {
                              guard let command = selectedCommand else { return false }
                              complete(command)
                              return true
                          },
                          onArrow: { step in
                              guard !suggestions.isEmpty else { return false }
                              selectedSuggestion = (selectedIndex + step + suggestions.count) % suggestions.count
                              return true
                          },
                          onPickSuggestion: {
                              guard let command = selectedCommand else { return false }
                              pick(command)
                              return true
                          })
                .frame(height: height)
                .onChange(of: session.draft) { _, _ in selectedSuggestion = 0 }

            HStack(spacing: 6) {
                cliMenu.padding(.trailing, 4)
                if let chat = session.chat {
                    modelMenu(chat)
                    modeMenu(chat).padding(.trailing, 4)
                }
                // 只有输入框为空时按键才会交给 CLI，所以提示也只在那时出现。
                if let chat = session.chat {
                    if chat.log.isWorking {
                        KeyCap(text: "esc")
                        Text("打断")
                    } else if session.draft.isEmpty && session.isRunning {
                        KeyCap(text: "/")
                        Text("命令与技能")
                    }
                } else if let direct = session.directInput {
                    Text("正在用 \(cliName) 自己的输入框，")
                    if direct.sticky {
                        KeyCap(text: "⌘/")
                        Text("回到这里")
                    } else {
                        KeyCap(text: "↩")
                        Text("执行后回到这里")
                    }
                } else if session.draft.isEmpty && session.isRunning {
                    Text("输入框为空时，")
                    KeyCap(text: "/")
                    KeyCap(text: "↑↓")
                    KeyCap(text: "esc")
                    Text("交给 \(cliName)")
                }
                Spacer(minLength: 8)
                KeyCap(text: "⇧↩")
                Text("换行")
                sendButton.padding(.leading, 4)
            }
            .font(CoveFont.ui(11.5))
            .foregroundStyle(SwiftUI.Color.coveT3)
        }
        .padding(.top, 12)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.bottom, 8)
        .background(SwiftUI.Color.coveRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SwiftUI.Color.coveRaisedLine))
        .shadow(color: .black.opacity(colorScheme == .light ? 0.05 : 0), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            if colorScheme == .dark { SwiftUI.Color.coveLine.frame(height: 1) }
        }
    }

    private func modelMenu(_ chat: ChatBridge) -> some View {
        Menu {
            ForEach(chat.models) { option in
                Button {
                    chat.setModel(option)
                } label: {
                    if option.value == chat.modelValue { Label(option.displayName, systemImage: "checkmark") } else { Text(option.displayName) }
                }
            }
        } label: {
            chip(chat.models.first { $0.value == chat.modelValue }?.displayName.replacingOccurrences(of: " (recommended)", with: "") ?? "模型")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(chat.models.isEmpty)
        .help("模型")
    }

    private func modeMenu(_ chat: ChatBridge) -> some View {
        Menu {
            ForEach(PermissionMode.allCases) { mode in
                Button {
                    chat.setPermissionMode(mode)
                } label: {
                    if mode == chat.permissionMode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                }
            }
            Divider()
            Text("⇧⌘M 依次切换")
        } label: {
            chip(chat.permissionMode?.title ?? "权限")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("权限模式（⇧⌘M 切换）")
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(CoveFont.ui(11.5, weight: .medium))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(SwiftUI.Color.coveT2)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(SwiftUI.Color.coveKey, in: RoundedRectangle(cornerRadius: 5))
    }

    /// 切换 CLI：在同一文件夹里用另一个 CLI 开新会话（运行中的 CLI 换不了，上下文也带不过去）。
    private var cliMenu: some View {
        Menu {
            ForEach(CLIKind.allCases) { cli in
                Button {
                    model.switchCLI(of: session, to: cli)
                } label: {
                    if cli == session.cli { Label(cli.displayName, systemImage: "checkmark") } else { Text(cli.displayName) }
                }
            }
            Divider()
            Text("切换会在同一文件夹新开会话")
        } label: {
            HStack(spacing: 4) {
                Text(session.cli.displayName).font(CoveFont.ui(11.5, weight: .medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(SwiftUI.Color.coveT2)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(SwiftUI.Color.coveKey, in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换 CLI")
    }

    @ViewBuilder
    private var sendButton: some View {
        // Cove 界面里 Claude 在干活、输入框又是空的：按钮换成停止。有字时仍是发送——
        // stream-json 允许中途插话，claude 会在当前动作结束后读到。
        if let chat = session.chat, chat.log.isWorking, session.draft.isEmpty {
            Button(action: { chat.interrupt() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(SwiftUI.Color.coveAccentFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("停止（Esc）")
            .accessibilityLabel("Stop")
        } else {
            plainSendButton
        }
    }

    private var plainSendButton: some View {
        Button(action: { submit(session.draft) }) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(SwiftUI.Color.coveAccentFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .opacity(canSend ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help("发送（Return）")
        .accessibilityLabel("Send")
    }

    /// Cove 界面里敲 `/` 时的候选命令；终端模式下 `/` 直接交给 CLI，不在这里提示。
    private var suggestions: [SlashCommand] {
        guard let chat = session.chat else { return [] }
        return SlashCommand.matches(chat.commands, draft: session.draft)
    }

    private var selectedIndex: Int { min(selectedSuggestion, max(suggestions.count - 1, 0)) }
    private var selectedCommand: SlashCommand? { suggestions.isEmpty ? nil : suggestions[selectedIndex] }

    private func complete(_ command: SlashCommand) {
        session.draft = "/\(command.name) "
        session.focusRequest += 1
    }

    /// 回车或点击选中一条：不需要参数的直接执行，需要参数的先补全，等人把参数填完。
    private func pick(_ command: SlashCommand) {
        if command.argumentHint.isEmpty {
            submit("/" + command.name)
        } else {
            complete(command)
        }
    }

    private var cliName: String { session.cli == .claude ? "Claude" : session.cli.displayName }

    private var canSend: Bool {
        session.isRunning && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(_ text: String) {
        guard session.isRunning, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.send(text)
        session.draft = ""
    }
}

struct ComposerField: NSViewRepresentable {
    static let minHeight: CGFloat = 22
    static let maxHeight: CGFloat = 180

    @Binding var text: String
    @Binding var height: CGFloat
    let focusRequest: Int
    let placeholder: String
    /// 终端模式下空输入框的方向键、Esc 等要交给 CLI；Cove 界面没有终端，只剩 Esc 打断。
    let terminalRouting: Bool
    let applicationCursor: () -> Bool
    let onSubmit: (String) -> Void
    let onPassthrough: ([UInt8]) -> Void
    let onHandoff: ([UInt8]) -> Void
    /// 以下三个返回 true 表示按键被斜杠命令候选用掉了：Tab 补全、↑↓ 换选中、回车选定。
    let onTab: () -> Bool
    let onArrow: (Int) -> Bool
    let onPickSuggestion: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = Palette.t1
        textView.insertionPointColor = Palette.accent
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.coordinator = context.coordinator
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? ComposerTextView else { return }
        textView.placeholder = placeholder
        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight(textView)
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerField
        var lastFocusRequest = -1

        init(_ parent: ComposerField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight(textView)
        }

        func recalculateHeight(_ textView: NSTextView) {
            guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height + textView.textContainerInset.height * 2
            let clamped = min(max(used, ComposerField.minHeight), ComposerField.maxHeight)
            if abs(clamped - parent.height) > 0.5 {
                // 布局回调里改 SwiftUI 状态要推迟一拍。
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}

final class ComposerTextView: NSTextView {
    weak var coordinator: ComposerField.Coordinator?
    var placeholder = "" { didSet { needsDisplay = true } }

    override func keyDown(with event: NSEvent) {
        // 输入法组字期间（拼音还没上屏），所有键都是输入法的，一个都不能截。
        guard !hasMarkedText(), let coordinator else { return super.keyDown(with: event) }
        let stroke = KeyStroke(event)
        guard coordinator.parent.terminalRouting else { return chatKeyDown(stroke, event) }
        let route = KeyRouter.route(stroke, composerIsEmpty: string.isEmpty,
                                    applicationCursor: coordinator.parent.applicationCursor())
        switch route {
        case let .terminal(bytes):
            coordinator.parent.onPassthrough(bytes)
        case let .handoff(bytes):
            coordinator.parent.onHandoff(bytes)
        case .composer where stroke.key == .enter:
            if stroke.modifiers.contains(.shift) || stroke.modifiers.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                coordinator.parent.onSubmit(string)
            }
        case .composer:
            super.keyDown(with: event)
        }
    }

    /// 粘贴文件：插路径。粘贴纯图片（截图）：先存成 PNG 再插路径——CLI 读不到剪贴板，只认文件。
    override func paste(_ sender: Any?) {
        if insertAttachments(from: .general) { return }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if insertAttachments(from: sender.draggingPasteboard) {
            window?.makeFirstResponder(self)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func insertAttachments(from pasteboard: NSPasteboard) -> Bool {
        var paths = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .map(\.path)
        if paths.isEmpty, pasteboard.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pasteboard), let saved = Attachments.save(image) {
            paths = [saved]
        }
        guard !paths.isEmpty else { return false }
        insertText(AttachmentReference.text(for: paths), replacementRange: selectedRange())
        return true
    }

    private func chatKeyDown(_ stroke: KeyStroke, _ event: NSEvent) {
        guard let coordinator, stroke.modifiers.isDisjoint(with: [.command, .control]) else { return super.keyDown(with: event) }
        switch stroke.key {
        case .enter where stroke.modifiers.contains(.shift) || stroke.modifiers.contains(.option):
            insertNewlineIgnoringFieldEditor(nil)
        case .enter where coordinator.parent.onPickSuggestion():
            break
        case .enter:
            coordinator.parent.onSubmit(string)
        case .up where coordinator.parent.onArrow(-1), .down where coordinator.parent.onArrow(1):
            break
        case .escape:
            coordinator.parent.onPassthrough([0x1B])
        case .tab where coordinator.parent.onTab():
            break
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 14),
            .foregroundColor: Palette.t3,
        ]
        placeholder.draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y), withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

extension KeyStroke {
    init(_ event: NSEvent) {
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }

        let key: Key
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 53: key = .escape
        case 36, 76: key = .enter
        case 48: key = .tab
        case 51: key = .backspace
        default:
            if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
                key = .character(characters)
            } else {
                key = .other
            }
        }
        self.init(key: key, modifiers: modifiers)
    }
}

/// 输入框上方的斜杠命令候选。命令列表来自 claude 的初始化应答，包括用户自己的技能和插件命令。
private struct SlashSuggestions: View {
    let commands: [SlashCommand]
    let selected: Int
    let pick: (SlashCommand) -> Void

    private static let rowHeight: CGFloat = 27

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rows
            }
            .frame(height: min(CGFloat(commands.count), 7.5) * Self.rowHeight)
            .onChange(of: selected) { _, index in proxy.scrollTo(commands[index].id) }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button { pick(command) } label: {
                    HStack(spacing: 10) {
                        Text("/" + command.name)
                            .font(CoveFont.mono(12.5, weight: .medium))
                            .foregroundStyle(SwiftUI.Color.coveT1)
                        Text(command.description)
                            .font(CoveFont.ui(12))
                            .foregroundStyle(SwiftUI.Color.coveT3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if index == selected { KeyCap(text: "tab") }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowHeight)
                    .background(index == selected ? SwiftUI.Color.coveSelect : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(command.id)
            }
        }
    }
}

extension PermissionMode {
    /// 叫法跟官方桌面端的中文语境对齐。
    var title: String {
        switch self {
        case .default: "逐项批准"
        case .acceptEdits: "自动接受编辑"
        case .plan: "计划模式"
        case .auto: "自动"
        case .bypassPermissions: "跳过权限"
        }
    }

    /// ⇧⌘M 的轮换顺序；跳过权限不在轮换里，只能从菜单里显式选。
    var next: PermissionMode {
        switch self {
        case .default: .acceptEdits
        case .acceptEdits: .plan
        case .plan: .auto
        case .auto, .bypassPermissions: .default
        }
    }
}

/// 粘贴进来的图片落盘的位置。按时间命名，不自动清理——它们被会话引用着，删了回看时就断了。
enum Attachments {
    static let directory = UsageRelay.supportDirectory.appendingPathComponent("attachments")

    static func save(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = directory.appendingPathComponent("paste-\(formatter.string(from: .now)).png")
        return (try? png.write(to: url)) != nil ? url.path : nil
    }
}
