// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatteryForgeCore",
    platforms: [.macOS(.v14), .iOS(.v15)],
    products: [.library(name: "BatteryForgeCore", targets: ["BatteryForgeCore"])],
    targets: [
        .target(name: "BatteryForgeCore"),
        .testTarget(name: "BatteryForgeCoreTests", dependencies: ["BatteryForgeCore"])
    ]
)
