// swift-tools-version:6.4

import PackageDescription

// The deployment target stays at macOS 14. This is a public repo whose README
// promises macOS 14 or later, so raising it would drop every user below 27 for
// nothing. The SDK the binary reports is stamped separately in the Makefile;
// see the comment on PLATFORM_VERSION there for why that matters.
//
// swift-tools-version 6.4 turns on Swift 6 language mode, which stops on this
// app's pre-concurrency AppKit code. swiftLanguageMode(.v5) keeps the current
// semantics; moving to Swift 6 concurrency is its own migration.
let package = Package(
    name: "DefaultBrowser",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DefaultBrowser",
            path: "Sources/DefaultBrowser",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
