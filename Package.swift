// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PreviewX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PreviewXCore", targets: ["PreviewXCore"]),
        .library(name: "PreviewXProviders", targets: ["PreviewXProviders"]),
        .library(name: "PreviewXUI", targets: ["PreviewXUI"]),
        .library(name: "PreviewXQuickLook", targets: ["PreviewXQuickLook"]),
        .executable(name: "previewx", targets: ["PreviewXCLI"]),
        .executable(name: "PreviewXApp", targets: ["PreviewXApp"])
    ],
    targets: [
        .target(name: "PreviewXCore"),
        .target(name: "PreviewXProviders", dependencies: ["PreviewXCore"]),
        .target(name: "PreviewXUI", dependencies: ["PreviewXCore", "PreviewXProviders"]),
        .target(name: "PreviewXQuickLook", dependencies: ["PreviewXCore", "PreviewXProviders", "PreviewXUI"]),
        .executableTarget(name: "PreviewXCLI", dependencies: ["PreviewXCore", "PreviewXProviders"]),
        .executableTarget(name: "PreviewXApp", dependencies: ["PreviewXCore", "PreviewXProviders", "PreviewXUI"]),
        .testTarget(name: "PreviewXTests", dependencies: ["PreviewXCore", "PreviewXProviders", "PreviewXUI"])
    ],
    swiftLanguageModes: [.v6]
)
