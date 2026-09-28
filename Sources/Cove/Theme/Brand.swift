import AppKit

enum Brand {
    /// 不带方块底的杯子本体（由 scripts/make_icon.sh 从 Resources/CupMark.svg 生成）。
    static let cupMark: NSImage? = Bundle.main.url(forResource: "CupMark", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
}
