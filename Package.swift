// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VerityLabsFoundation",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "VerityLabsFoundation",
            targets: [
                "VLExtensions",
                "VLSharedModels",
                "VLServices",
                "VLViews"
            ]
        ),
        .library(name: "VLServices", targets: ["VLServices"]),
        .library(name: "VLLogging", targets: ["VLLogging"]),
        .library(name: "VLCache", targets: ["VLCache"]),
        .library(name: "VLFiles", targets: ["VLFiles"]),
        .library(name: "VLHTTP", targets: ["VLHTTP"]),
        .library(name: "VLData", targets: ["VLData"]),
        .library(name: "VLUtilities", targets: ["VLUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", .upToNextMajor(from: "1.3.9")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", .upToNextMajor(from: "1.23.1"))
    ],
    targets: [
        .target(name: "VLExtensions", path: "Sources/Extensions"),
        .target(
            name: "VLSharedModels",
            dependencies: ["VLExtensions"],
            path: "Sources/SharedModels"
        ),
        .target(
            name: "VLLogging",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/Logging"
        ),
        .target(
            name: "VLCache",
            dependencies: [
                .target(name: "VLSharedModels"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/Cache"
        ),
        .target(
            name: "VLFiles",
            dependencies: [
                .target(name: "VLSharedModels"),
                .target(name: "VLCache"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/Files"
        ),
        .target(
            name: "VLHTTP",
            dependencies: [
                .target(name: "VLSharedModels"),
                .target(name: "VLExtensions"),
                .target(name: "VLFiles"),
                .target(name: "VLLogging"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/HTTP"
        ),
        .target(
            name: "VLData",
            dependencies: [
                .target(name: "VLSharedModels"),
                .target(name: "VLCache"),
                .target(name: "VLHTTP"),
                .target(name: "VLLogging"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/Data"
        ),
        .target(
            name: "VLUtilities",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/Utilities"
        ),
        .target(
            name: "VLServices",
            dependencies: [
                .target(name: "VLLogging"),
                .target(name: "VLCache"),
                .target(name: "VLFiles"),
                .target(name: "VLHTTP"),
                .target(name: "VLData"),
                .target(name: "VLUtilities"),
            ],
            path: "Sources/ServiceExports"
        ),
        .target(
            name: "VLViews",
            dependencies: [
                .target(name: "VLData"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .target(name: "VLLogging"),
                .target(name: "VLSharedModels"),
            ],
            path: "Sources/Views"
        )
    ]
)
