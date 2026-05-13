// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macfanctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macfanctl", targets: ["macfanctl"]),
        .library(name: "SMCKit", targets: ["SMCKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SMCKit"),
        .executableTarget(
            name: "macfanctl",
            dependencies: [
                "SMCKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"]
        ),
    ]
)
