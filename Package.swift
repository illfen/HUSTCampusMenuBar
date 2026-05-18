// swift-tools-version: 6.0

import PackageDescription

#if os(macOS)
let coreLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Network")
]
let menuBarLinkerSettings: [LinkerSetting] = [
    .linkedFramework("AppKit")
]
#else
let coreLinkerSettings: [LinkerSetting] = []
let menuBarLinkerSettings: [LinkerSetting] = []
#endif

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
        ),
        .executable(
            name: "hust-autologin",
            targets: ["HUSTCampusCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.4.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "HUSTCampusCore",
            dependencies: [
                .product(name: "BigInt", package: "BigInt")
            ],
            linkerSettings: coreLinkerSettings
        ),
        .executableTarget(
            name: "HUSTCampusMenuBar",
            dependencies: ["HUSTCampusCore"],
            linkerSettings: menuBarLinkerSettings
        ),
        .executableTarget(
            name: "HUSTCampusCLI",
            dependencies: [
                "HUSTCampusCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "HUSTCampusCoreTests",
            dependencies: ["HUSTCampusCore"]
        )
    ]
)
