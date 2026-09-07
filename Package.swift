// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DefaultBrowser",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DefaultBrowser",
            path: "Sources/DefaultBrowser"
        )
    ]
)
