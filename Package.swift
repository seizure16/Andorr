// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Andorr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AndorrCore", targets: ["AndorrCore"]),
        .executable(name: "AndorrDesktop", targets: ["AndorrDesktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0")
    ],
    targets: [
        .target(name: "AndorrCore", dependencies: ["Yams", .product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "AndorrDesktop", dependencies: ["AndorrCore", "Highlightr"], path: "Sources/Andorr"),
        .testTarget(name: "AndorrCoreTests", dependencies: ["AndorrCore"]),
        .testTarget(name: "AndorrDesktopTests", dependencies: ["AndorrDesktop", "AndorrCore"])
    ],
    swiftLanguageModes: [.v5]
)
