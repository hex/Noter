// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Noter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Noter",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Noter"
        ),
        .testTarget(
            name: "NoterTests",
            dependencies: ["Noter"],
            path: "Tests/NoterTests"
        ),
    ]
)
