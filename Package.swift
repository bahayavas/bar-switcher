// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BarSwitcher", path: "Sources/BarSwitcher")
    ]
)
