// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Aliniere",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aliniere", targets: ["AliniereApp"]),
        .library(name: "AliniereCore", targets: ["AliniereCore"])
    ],
    targets: [
        .target(
            name: "AliniereCore",
            path: "Sources/AliniereCore"
        ),
        .executableTarget(
            name: "AliniereApp",
            dependencies: ["AliniereCore"],
            path: "Sources/AliniereApp"
        ),
        .testTarget(
            name: "AliniereCoreTests",
            dependencies: ["AliniereCore"],
            path: "Tests/AliniereCoreTests"
        )
    ]
)
