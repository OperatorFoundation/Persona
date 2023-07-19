// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Persona",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "Persona",
            targets: ["Persona"]
        ),
        .executable(
            name: "UdpEchoServer",
            targets: ["UdpEchoServer"]
        ),
        .executable(
            name: "TcpEchoServer",
            targets: ["TcpEchoServer"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/sushichop/Puppy.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "1.0.0-alpha.11"),

        .package(url: "https://github.com/OperatorFoundation/Chord", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Datable", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Flower", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Gardener", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/InternetProtocols", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/KeychainCli", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Nametag", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Net", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Spacetime", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Straw", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Transmission", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionAsync", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionTypes", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "Persona",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                "Datable",
                "Flower",
                "Gardener",
                "InternetProtocols",
                "KeychainCli",
                "Nametag",
                "Net",
                "Puppy",
                "Straw",
                "SwiftHexTools",
                "Transmission",
                "TransmissionAsync",
                "TransmissionTypes",
                .product(name: "Simulation", package: "Spacetime"),
                .product(name: "Spacetime", package: "Spacetime"),
                .product(name: "Universe", package: "Spacetime"),
            ]),
        .executableTarget(
            name: "UdpEchoServer",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Simulation", package: "Spacetime"),
                .product(name: "Spacetime", package: "Spacetime"),
                .product(name: "Universe", package: "Spacetime"),

                "Datable",
                "Persona",
                "Puppy",
                "SwiftHexTools",
                "TransmissionTypes",
            ]),
        .executableTarget(
            name: "TcpEchoServer",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),

                "Chord",
                "Datable",
                "Persona",
                "Puppy",
                "SwiftHexTools",
                "TransmissionAsync",
            ]),
        .testTarget(
            name: "PersonaTests",
            dependencies: ["Persona"]),
    ],
    swiftLanguageVersions: [.v5]
)
