// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v10_13)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.3"),
        .package(url: "https://github.com/SwiftGen/SwiftGenPlugin", from: "6.5.1")
    ],
    targets: [.target(name: "BuildTools", path: "")]
)
