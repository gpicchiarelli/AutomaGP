// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutomaGPWorkbench",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AutomaGPWorkbench")
    ]
)
