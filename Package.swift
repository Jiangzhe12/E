// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nova",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Nova", targets: ["Nova"])
    ],
    targets: [
        .executableTarget(
            name: "Nova",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
