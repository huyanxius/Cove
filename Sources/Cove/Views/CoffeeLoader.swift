import SwiftUI

/// Cove 的加载动画：品牌那只手绘纸杯被「倒满」。
///
/// 底下是一层很淡的杯子虚影；实色的杯子从杯底往上显现，显现的边缘是一道柔和的液面波纹；
/// 满杯后停一拍再淡出、重新开始。杯口两缕模糊的细蒸汽错开相位往上飘。画面全部来自
/// 品牌杯子本身（Brand.cupMark），动画只做遮罩和透明度，不另画几何图形。
struct CoffeeLoader: View {
    var size: CGFloat = 64
    var caption: String?

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation) { context in
                CoffeeLoaderFrame(t: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: size, height: size * 1.25)
            if let caption {
                Text(caption)
                    .font(CoveFont.ui(12))
                    .tracking(0.3)
                    .foregroundStyle(SwiftUI.Color.coveT3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(caption ?? "正在加载")
    }
}

/// 某一时刻的画面，拆出来方便导出帧检查（见 `--render-loader`）。
struct CoffeeLoaderFrame: View {
    let t: Double
    static let cycle = 2.8

    var body: some View {
        Canvas { ctx, size in
            guard let image = Brand.cupMark else { return }
            let resolved = ctx.resolve(Image(nsImage: image))
            // 杯子占下方 80%，上方留给蒸汽。
            let cupHeight = size.height * 0.8
            let cupWidth = cupHeight * image.size.width / image.size.height
            let cupRect = CGRect(x: (size.width - cupWidth) / 2, y: size.height - cupHeight, width: cupWidth, height: cupHeight)

            let phase = t.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
            // 0–0.62 倒满（缓入缓出），0.62–0.82 停住，0.82–1 淡出。
            let fill = phase < 0.62 ? Self.ease(phase / 0.62) : 1
            let fade = phase < 0.82 ? 1 : 1 - Self.ease((phase - 0.82) / 0.18)

            // 虚影。
            var ghost = ctx
            ghost.opacity = 0.16
            ghost.draw(resolved, in: cupRect)

            // 实色部分：用带波纹的液面裁出来。杯体在图里大约占 8%~90% 的高度。
            let bottom = cupRect.minY + cupRect.height * 0.9
            let top = cupRect.minY + cupRect.height * 0.06
            let level = bottom - (bottom - top) * fill
            var surface = Path()
            surface.move(to: CGPoint(x: cupRect.minX - 4, y: cupRect.maxY + 4))
            let steps = 24
            for i in 0...steps {
                let x = cupRect.minX - 4 + (cupRect.width + 8) * CGFloat(i) / CGFloat(steps)
                let amplitude = cupRect.height * 0.018 * (1 - fill * 0.7)
                let wave = sin(Double(i) * 0.55 + t * 3.1) + 0.5 * sin(Double(i) * 1.1 - t * 1.7)
                surface.addLine(to: CGPoint(x: x, y: level + amplitude * CGFloat(wave)))
            }
            surface.addLine(to: CGPoint(x: cupRect.maxX + 4, y: cupRect.maxY + 4))
            surface.closeSubpath()
            var full = ctx
            full.opacity = fade
            full.clip(to: surface)
            full.draw(resolved, in: cupRect)

            // 蒸汽：满杯之后才冒，两缕，模糊的细线。
            let steam = max(0, min(1, (phase - 0.45) / 0.2)) * fade
            guard steam > 0 else { return }
            var wisps = ctx
            wisps.addFilter(.blur(radius: size.width * 0.02))
            // 两缕细长的 S 形蒸汽：越往上摆幅越大、越淡，分段画出由浓到淡的渐隐。
            for i in 0..<2 {
                let local = (t * 0.32 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let baseX = cupRect.midX + (i == 0 ? -1 : 1) * cupRect.width * 0.12
                let rimY = cupRect.minY + cupRect.height * 0.04
                let rise = CGFloat(local) * size.height * 0.06
                let length = size.height * 0.22
                var previous: CGPoint?
                for step in 0...24 {
                    let k = CGFloat(step) / 24
                    let sway = CGFloat(sin(Double(k) * .pi * 1.3 + t * 0.9 + Double(i) * 2.2)) * cupRect.width * 0.07 * (0.3 + k)
                    let point = CGPoint(x: baseX + sway, y: rimY - rise - k * length)
                    if let previous {
                        var segment = Path()
                        segment.move(to: previous)
                        segment.addLine(to: point)
                        let alpha = Double(1 - k) * sin(local * .pi) * 0.5 * steam
                        wisps.stroke(segment, with: .color(SwiftUI.Color.coveT3.opacity(alpha)),
                                     style: StrokeStyle(lineWidth: size.width * (0.02 + 0.02 * k), lineCap: .round))
                    }
                    previous = point
                }
            }
        }
    }

    static func ease(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}

/// `Cove --render-loader <目录>`：把加载动画一个周期内的 8 帧渲染成 PNG，检查画面用。
enum LoaderRenderer {
    @MainActor
    static func renderIfRequested(_ arguments: [String] = CommandLine.arguments) {
        guard let flag = arguments.firstIndex(of: "--render-loader"), arguments.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, dark) in [false, true].enumerated() {
            for frame in 0..<8 {
                let t = CoffeeLoaderFrame.cycle * Double(frame) / 8
                let view = CoffeeLoaderFrame(t: t)
                    .frame(width: 160, height: 200)
                    .padding(20)
                    .background(dark ? SwiftUI.Color(nsColor: NSColor(hex: 0x262624)) : SwiftUI.Color(nsColor: NSColor(hex: 0xF5F4EF)))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("loader-\(index)-\(frame).png"))
                }
            }
        }
        exit(0)
    }
}
