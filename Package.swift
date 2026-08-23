// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TokenGauge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TokenGauge", targets: ["TokenGauge"]),
        .library(name: "TokenGaugeCore", targets: ["TokenGaugeCore"]),
    ],
    targets: [
        .target(name: "TokenGaugeCore"),
        .executableTarget(name: "TokenGauge", dependencies: ["TokenGaugeCore"]),
        .testTarget(name: "TokenGaugeCoreTests", dependencies: ["TokenGaugeCore"]),
    ]
)
