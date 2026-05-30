// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalPackage",
    products: [
        .library(
            name: "App",
            targets: ["App"]
        ),
    ],
    targets: [
        .target(
            name: "App"
        ),
        .target(
            name: "Main",
            path: "Sources/Features/Main"
        ),
        .target(
            name: "Core"
        ),
        .target(
            name: "Infra"
        ),
        .testTarget(
            name: "MainTests",
            dependencies: ["Main"]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
