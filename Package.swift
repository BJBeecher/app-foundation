// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppFoundation",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "AppFoundation",
            targets: [
                "Extensions",
                "Models",
                "Services",
                "Views"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", .upToNextMajor(from: "1.3.9")),
        .package(url: "https://github.com/BJBeecher/Keychain.git", .upToNextMajor(from: "0.0.1")),
    ],
    targets: [
        .target(name: "Extensions"),
        .target(
            name: "Models",
            dependencies: ["Extensions"]
        ),
        .target(name: "Services", dependencies: [
            .target(name: "Models"),
            .target(name: "Extensions"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "Keychain", package: "Keychain")
        ]),
        .target(
            name: "Views",
            dependencies: [
                .target(name: "Services"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        )
    ]
)
