import AppKit
import CoveCore
import SwiftUI

/// 输入框下面那排选项块（CLI、模型、权限模式）：自绘的块 + 自绘的弹出列表，不用系统下拉菜单。
///
/// 选项块平时是一个浅底圆角块，悬停时底色加深；点开是贴在块上方的一张卡片，每行可带图标、
/// 主标题和一句说明，当前选中项打勾。和对话里的卡片同一套颜色与圆角。
/// 弹出列表里的一行。
struct ChipOption: Identifiable {
    let id: String
    let title: String
    var detail: String = ""
    var icon: AnyView?
}

struct ChipMenu<Leading: View>: View {
    let title: String
    let options: [ChipOption]
    let selected: String?
    var footnote: String?
    var help: String = ""
    @ViewBuilder let leading: Leading
    let pick: (String) -> Void

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                leading
                Text(title)
                    .font(CoveFont.ui(12, weight: .medium))
                    .foregroundStyle(SwiftUI.Color.coveT1)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(hovering || open ? SwiftUI.Color.coveSelect : SwiftUI.Color.coveKey,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(SwiftUI.Color.coveRaisedLine.opacity(0.7)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .disabled(options.isEmpty)
        .popover(isPresented: $open, arrowEdge: .top) {
            ChipMenuList(options: options, selected: selected, footnote: footnote) { id in
                open = false
                pick(id)
            }
        }
        .animation(.easeOut(duration: 0.15), value: open)
    }
}

extension ChipMenu where Leading == EmptyView {
    init(title: String, options: [ChipOption], selected: String?, footnote: String? = nil, help: String = "",
         pick: @escaping (String) -> Void) {
        self.init(title: title, options: options, selected: selected, footnote: footnote, help: help,
                  leading: { EmptyView() }, pick: pick)
    }
}

private struct ChipMenuList: View {
    let options: [ChipOption]
    let selected: String?
    let footnote: String?
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options) { option in
                ChipMenuRow(option: option, selected: option.id == selected) { pick(option.id) }
            }
            if let footnote {
                Rectangle().fill(SwiftUI.Color.coveLine).frame(height: 1).padding(.vertical, 4)
                Text(footnote)
                    .font(CoveFont.ui(11))
                    .foregroundStyle(SwiftUI.Color.coveT3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }
        }
        .padding(6)
        .frame(minWidth: 220, maxWidth: 320)
        .background(SwiftUI.Color.coveRaised)
    }
}

private struct ChipMenuRow: View {
    let option: ChipOption
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: option.detail.isEmpty ? .center : .top, spacing: 10) {
                if let icon = option.icon { icon.frame(width: 18, height: 18) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(CoveFont.ui(12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(SwiftUI.Color.coveT1)
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(CoveFont.ui(11))
                            .foregroundStyle(SwiftUI.Color.coveT3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SwiftUI.Color.coveAccent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hovering ? SwiftUI.Color.coveSelect : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 每个 CLI 的标志：直接用本机对应 App 的图标（Claude、Codex、Antigravity），
/// 最准确也最好认；没装那个 App 时退回一个带首字母的色块。
struct CLILogo: View {
    let cli: CLIKind
    var size: CGFloat = 16

    var body: some View {
        if let icon = Self.icon(for: cli) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Text(String(cli.displayName.prefix(1)))
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(SwiftUI.Color.coveAccentFill, in: RoundedRectangle(cornerRadius: size * 0.25))
        }
    }

    private static let bundleIDs: [CLIKind: String] = [
        .claude: "com.anthropic.claudefordesktop",
        .codex: "com.openai.codex",
        .agy: "com.google.antigravity",
    ]

    @MainActor private static var cache: [CLIKind: NSImage?] = [:]

    @MainActor static func icon(for cli: CLIKind) -> NSImage? {
        if let hit = cache[cli] { return hit }
        let image = bundleIDs[cli]
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[cli] = image
        return image
    }
}
