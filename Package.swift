// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VerityLabsFoundation",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VerityLabsFoundation",
            targets: [
                "VLExtensions",
                "VLSharedModels",
                "VLServices",
                "VLSampleable",
                "VLQuery",
                "VLViews"
            ]
        ),
        .library(name: "VLServices", targets: ["VLServices"]),
        .library(name: "VLLogging", targets: ["VLLogging"]),
        .library(name: "VLCache", targets: ["VLCache"]),
        .library(name: "VLFiles", targets: ["VLFiles"]),
        .library(name: "VLPhotos", targets: ["VLPhotos"]),
        .library(name: "VLHTTP", targets: ["VLHTTP"]),
        .library(name: "VLSampleable", targets: ["VLSampleable"]),
        .library(name: "VLQuery", targets: ["VLQuery"]),
        .library(name: "VLKeychain", targets: ["VLKeychain"]),
        .library(name: "VLUtilities", targets: ["VLUtilities"]),
        .library(name: "VLRouter", targets: ["VLRouter"]),
        .library(name: "VLViews", targets: ["VLViews"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", .upToNextMajor(from: "1.23.1")),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.5.0")),
        .package(url: "https://github.com/SDWebImage/SDWebImageWebPCoder.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.10.0"))
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
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Sources/Logging"
        ),
        .target(
            name: "VLCache",
            dependencies: [],
            path: "Sources/Cache"
        ),
        .target(
            name: "VLFiles",
            dependencies: [
                .target(name: "VLSharedModels"),
                .target(name: "VLCache"),
            ],
            path: "Sources/Files"
        ),
        .target(
            name: "VLPhotos",
            dependencies: [
                .target(name: "VLFiles"),
                .target(name: "VLSharedModels"),
                .target(name: "VLUtilities"),
                "SDWebImageWebPCoder",
            ],
            path: "Sources/Photos"
        ),
        .target(
            name: "VLHTTP",
            dependencies: [
                .target(name: "VLSharedModels"),
                .target(name: "VLFiles"),
                .product(name: "Alamofire", package: "Alamofire"),
            ],
            path: "Sources/HTTP",
            exclude: ["README.md"]
        ),
        .target(
            name: "VLQuery",
            path: "Sources/Query",
            exclude: ["README.md"]
        ),
        .target(
            name: "VLSampleable",
            dependencies: [
                .target(name: "VLHTTP"),
                .target(name: "VLSharedModels"),
            ],
            path: "Sources/Sampleable",
            exclude: ["README.md"]
        ),
        .target(
            name: "VLKeychain",
            dependencies: [],
            path: "Sources/Keychain"
        ),
        .target(name: "VLUtilities", path: "Sources/Utilities"),
        .target(
            name: "VLRouter",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Sources/Router"
        ),
        .target(
            name: "VLServices",
            dependencies: [
                .target(name: "VLLogging"),
                .target(name: "VLCache"),
                .target(name: "VLFiles"),
                .target(name: "VLPhotos"),
                .target(name: "VLHTTP"),
                .target(name: "VLSampleable"),
                .target(name: "VLQuery"),
                .target(name: "VLKeychain"),
                .target(name: "VLUtilities"),
                .target(name: "VLRouter"),
            ],
            path: "Sources/ServiceExports"
        ),
        .target(
            name: "VLViews",
            dependencies: [
                .target(name: "VLQuery"),
                "Kingfisher",
            ],
            path: "Sources/Views",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "VerityLabsFoundationTests",
            dependencies: [
                .target(name: "VLExtensions"),
                .target(name: "VLCache"),
                .target(name: "VLSharedModels"),
                .target(name: "VLFiles"),
                .target(name: "VLKeychain"),
                .target(name: "VLUtilities"),
            ],
            path: "Tests/VerityLabsFoundationTests"
        ),
        .testTarget(
            name: "VLHTTPTests",
            dependencies: [
                .target(name: "VLHTTP"),
                .product(name: "Alamofire", package: "Alamofire"),
            ],
            path: "Tests/VLHTTPTests"
        ),
        .testTarget(
            name: "VLSampleableTests",
            dependencies: [
                .target(name: "VLSampleable"),
                .target(name: "VLHTTP"),
                .target(name: "VLSharedModels"),
            ],
            path: "Tests/VLSampleableTests"
        ),
        .testTarget(
            name: "VLQueryTests",
            dependencies: [
                .target(name: "VLQuery"),
            ],
            path: "Tests/VLQueryTests"
        ),
        .testTarget(
            name: "VLViewsTests",
            dependencies: [
                .target(name: "VLViews"),
                .target(name: "VLQuery"),
            ],
            path: "Tests/VLViewsTests"
        )
    ]
)
