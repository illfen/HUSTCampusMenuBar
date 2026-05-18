// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HUSTCampusMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HUSTCampusCore",
            targets: ["HUSTCampusCore"]
        ),
        .executable(
            name: "HUSTCampusMenuBar",
            targets: ["HUSTCampusMenuBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.4.0")
    ],
    targets: [
        .target(
            name: "HUSTCampusCore",
            dependencies: [
                .product(name: "BigInt", package: "BigInt")
            ],
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "HUSTCampusMenuBar",
            dependencies: ["HUSTCampusCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "HUSTCampusCoreTests",
            dependencies: ["HUSTCampusCore"]
        )
    ]
)
