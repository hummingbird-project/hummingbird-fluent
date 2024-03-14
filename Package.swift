// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hummingbird-fluent",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "HummingbirdFluent", targets: ["HummingbirdFluent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0-beta.1"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.45.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "HummingbirdFluent", dependencies: [
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            .product(name: "FluentKit", package: "fluent-kit"),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        ]),
        .testTarget(name: "HummingbirdFluentTests", dependencies: [
            .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            .byName(name: "HummingbirdFluent"),
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]),
    ]
)
