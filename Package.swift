// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "solcito",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HIDTransport", targets: ["HIDTransport"]),
        .library(name: "HIDPP", targets: ["HIDPP"]),
        .executable(name: "solcito", targets: ["SolcitoCLI"]),
    ],
    targets: [
        .target(name: "HIDTransport"),
        .target(name: "HIDPP", dependencies: ["HIDTransport"]),
        .executableTarget(
            name: "SolcitoCLI",
            dependencies: ["HIDTransport", "HIDPP"]
        ),
        .testTarget(name: "HIDTransportTests", dependencies: ["HIDTransport"]),
        .testTarget(name: "HIDPPTests", dependencies: ["HIDPP"]),
    ]
)
