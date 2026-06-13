// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - Targets

let core = AppTarget(
    name: "Core",
    testTargetName: "CoreTests"
)
let infra = AppTarget(
    name: "Infra",
    dependencies: []
)
let libraryFeature = AppTarget(
    name: "Library",
    testTargetName: "LibraryTests",
    dependencies: [core]
)

let app = AppTarget(
    name: "App",
    dependencies: [libraryFeature, core, infra]
)


// MARK: - Package Definition

let package = Package(
    name: "LocalPackage",
    platforms: [.iOS(.v18), .macOS(.v26)],
    products: [
        .library(
            name: "App",
            targets: ["App"]
        ),
        .library(
            name: libraryFeature.name,
            targets: [libraryFeature.name]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SRGSSR/google-cast-sdk.git", exact: "4.8.4")
    ],
    targets: [
        .target(
            name: app.name,
            dependencies: app.targetDependencies
        ),
        .target(
            name: libraryFeature.name,
            dependencies: libraryFeature.targetDependencies,
            path: "Sources/Features/Library"
        ),
        .target(
            name: core.name
        ),
        .target(
            name: infra.name,
            dependencies: [
                .product(name: "GoogleCast", package: "google-cast-sdk")
            ]
        ),
        .testTarget(
            name: libraryFeature.testTargetName!,
            dependencies: libraryFeature.testDependencies
        ),
        .testTarget(
            name: core.testTargetName!,
            dependencies: core.testDependencies
        ),
    ],
    swiftLanguageModes: [.v6]
)

struct AppTarget {
    let name: String
    let testTargetName: String?
    let dependencies: [AppTarget]
    
    var targetDependencies: [Target.Dependency] {
        dependencies.map { Target.Dependency(stringLiteral: $0.name) }
    }
    var testDependencies: [Target.Dependency] {
        [.init(stringLiteral: name)] + targetDependencies
    }
    
    init(name: String, testTargetName: String? = nil, dependencies: [AppTarget] = []) {
        self.name = name
        self.testTargetName = testTargetName
        self.dependencies = dependencies
    }
}
