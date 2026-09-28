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
            dependencies: ["CoveCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .testTarget(name: "CoveCoreTests", dependencies: ["CoveCore"]),
    ]
)
