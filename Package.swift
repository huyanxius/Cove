// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cove",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cove", targets: ["Cove"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0"),
    ],
    targets: [
        // 纯逻辑层：JSONL 解析、状态推断、输入路由。不依赖 AppKit，全部可测。
        .target(name: "CoveCore"),
        .executableTarget(
            name: "Cove",
            dependencies: ["CoveCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            // SwiftTerm 的 delegate 协议没有 actor 标注，在 Swift 6 严格并发下每个回调都要
            // 手工桥接；App 层先用 Swift 5 语言模式，CoveCore 仍是 Swift 6。
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CoveCoreTests", dependencies: ["CoveCore"]),
    ]
)
