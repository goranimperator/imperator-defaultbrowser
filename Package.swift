// swift-tools-version:6.4

import PackageDescription

// The deployment target stays at macOS 14. This is a public repo whose README
// promises macOS 14 or later, so raising it would drop every user below 27 for
// nothing. The SDK the binary reports is stamped separately in the Makefile;
// see the comment on PLATFORM_VERSION there for why that matters.
//
// Swift 6 language mode. The one thing that blocked it was a plain static image
// cache in GlobeIcon, which is main-actor isolated now; everything else in the
// app was already @MainActor. Do not drop back to .v5 to silence a new
// diagnostic: in this app a concurrency error has meant a real main-thread
// assumption that was not written down.
let package = Package(
    name: "DefaultBrowser",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DefaultBrowser",
            path: "Sources/DefaultBrowser",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
