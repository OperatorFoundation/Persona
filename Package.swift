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
        .package(url: "https://github.com/sushichop/Puppy", from: "0.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        
        .package(url: "https://github.com/OperatorFoundation/Datable", from: "4.0.1"),
        .package(url: "https://github.com/OperatorFoundation/Gardener", from: "0.1.1"),
        .package(url: "https://github.com/Kitura/HeliumLogger", from: "2.0.0"),
        .package(url: "https://github.com/OperatorFoundation/InternetProtocols", from: "2.2.4"),
        .package(url: "https://github.com/OperatorFoundation/Net", from: "0.0.10"),
        .package(url: "https://github.com/OperatorFoundation/Straw", from: "1.0.1"),
        .package(url: "https://github.com/OperatorFoundation/swift-log-file", from: "0.1.0"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools", from: "1.2.6"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionAsync", from: "0.1.4"),
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
