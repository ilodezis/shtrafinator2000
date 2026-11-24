// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(
        name: "ShtrafinatorCore",
        dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
    ),
    .testTarget(
        name: "ShtrafinatorCoreTests",
        dependencies: ["ShtrafinatorCore"],
        resources: [.copy("Fixtures")]
    ),
]

// SwiftUI-приложение собирается только на macOS; ядро и тесты — везде (CI гоняет их и на Linux).
#if os(macOS)
targets.append(
    .executableTarget(
        name: "Shtrafinator",
        dependencies: ["ShtrafinatorCore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
)
#endif

let package = Package(
    name: "Shtrafinator",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: targets
)
