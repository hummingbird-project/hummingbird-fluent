// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hummingbird-fluent",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(name: "HummingbirdFluent", targets: ["HummingbirdFluent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.17.0"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        // .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        // .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0"),
    ],
    targets: [
        .target(name: "HummingbirdFluent", dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "FluentKit", package: "fluent-kit"),
        ]),
        .testTarget(name: "HummingbirdFluentTests", dependencies: [
            .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            // .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            // .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
            .byName(name: "HummingbirdFluent"),
            .product(name: "HummingbirdFoundation", package: "hummingbird"),
            .product(name: "HummingbirdXCT", package: "hummingbird"),
        ]),
    ]
)
