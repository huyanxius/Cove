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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 10) {
            ComposerField(text: $session.draft, height: $height, focusRequest: session.focusRequest,
                          placeholder: session.isRunning ? "Message Claude…" : "会话已结束",
                          applicationCursor: { session.applicationCursor },
                          onSubmit: submit,
                          onPassthrough: { session.sendRaw($0) })
                .frame(height: height)

            HStack(spacing: 6) {
                // 只有输入框为空时按键才会交给 Claude，所以提示也只在那时出现。
                if session.draft.isEmpty && session.isRunning {
                    Text("输入框为空时，")
                    KeyCap(text: "↑↓")
                    KeyCap(text: "esc")
                    KeyCap(text: "tab")
                    Text("交给 Claude 的菜单")
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

    private var sendButton: some View {
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
    let applicationCursor: () -> Bool
    let onSubmit: (String) -> Void
    let onPassthrough: ([UInt8]) -> Void

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
        let route = KeyRouter.route(stroke, composerIsEmpty: string.isEmpty,
                                    applicationCursor: coordinator.parent.applicationCursor())
        switch route {
        case let .terminal(bytes):
            coordinator.parent.onPassthrough(bytes)
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
