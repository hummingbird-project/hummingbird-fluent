// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hummingbird-fluent",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "HummingbirdFluent", targets: ["HummingbirdFluent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "0.5.0"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "HummingbirdFluent", dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "FluentKit", package: "fluent-kit"),
        ]),
        .testTarget(name: "HummingbirdFluentTests", dependencies: [
            .byName(name: "HummingbirdFluent"),
            .product(name: "HummingbirdXCT", package: "hummingbird"),
        ]),
    ]
)
