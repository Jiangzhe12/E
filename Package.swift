// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnglishCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EnglishCoach", targets: ["EnglishCoach"])
    ],
    targets: [
        .executableTarget(
            name: "EnglishCoach",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
