// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YIYI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YIYI", targets: ["YIYIApp"])
    ],
    targets: [
        .executableTarget(
            name: "YIYIApp",
            path: "Sources/YIYIApp"
        )
    ]
)
