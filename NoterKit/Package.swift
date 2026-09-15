// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoterKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "NoterKit", targets: ["NoterKit"])],
    targets: [
        .target(name: "NoterKit"),
        .testTarget(name: "NoterKitTests", dependencies: ["NoterKit"]),
    ]
)
