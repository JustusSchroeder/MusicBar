// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpotifyBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpotifyBar", targets: ["SpotifyBar"])
    ],
    targets: [
        .executableTarget(
            name: "SpotifyBar",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
