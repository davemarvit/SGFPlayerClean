// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SGFPlayerNetworking",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SGFPlayerNetworking", path: "SGFPlayerClean/Services/Networking"),
        .testTarget(name: "SGFPlayerNetworkingTests", dependencies: ["SGFPlayerNetworking"],
                    path: "Tests/Networking")
    ]
)
