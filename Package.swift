// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Moves",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Moves",
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
