// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Moves",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Global hotkey for Capture. Pulls in the Carbon shim, persistence of
        // user-chosen shortcuts, and the SwiftUI recorder we'd otherwise have
        // to hand-roll. Phase 2 wires one shortcut name: `.capture`.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "1.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Moves",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Moves",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MovesTests",
            dependencies: ["Moves"],
            path: "Tests/MovesTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
