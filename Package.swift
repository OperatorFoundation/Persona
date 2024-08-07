// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Persona",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "Persona",
            targets: ["Persona"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/sushichop/Puppy.git", from: "0.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),

        .package(url: "https://github.com/OperatorFoundation/Datable", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Gardener", branch: "main"),
        .package(url: "https://github.com/Kitura/HeliumLogger.git", from: "2.0.0"),
        .package(url: "https://github.com/OperatorFoundation/InternetProtocols", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Net", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Straw", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/swift-log-file", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionAsync", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "Persona",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FileLogging", package: "swift-log-file"),
                .product(name: "Logging", package: "swift-log"),

                "Datable",
                "Gardener",
                "HeliumLogger",
                "InternetProtocols",
                "Net",
                "Puppy",
                "Straw",
                "SwiftHexTools",
                "TransmissionAsync",
            ]),
        .testTarget(
            name: "PersonaTests",
            dependencies: ["Persona"]),
    ],
    swiftLanguageVersions: [.v5]
)
