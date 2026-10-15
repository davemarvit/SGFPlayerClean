// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SGFPlayerNetworking",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SGFPlayerNetworking", path: "SGFPlayerClean",
                exclude: [
                    "Assets",
                    "Current documentation",
                    "HIDDEN_OLD",
                    "Models/AIModels.swift",
                    "Models/AppModel.swift",
                    "Models/DiagnosticTests.swift",
                    "Models/GameSettings.swift",
                    "Models/SGFPlayerClean.entitlements",
                    "Models/SGFPlayerCleanApp.swift",
                    "Models/SceneManager3D.swift",
                    "Models/StoneJitter.swift",
                    "Models/StoneMeshFactory.swift",
                    "Resources",
                    "SGFPlayerClean.xcodeproj",
                    "Services/FileLoadingService.swift",
                    "Services/KataGoEngine.swift",
                    "Services/LegacyOGSClient.swift.txt",
                    "Services/SoundManager.swift",
                    "ViewModels",
                    "Views",
                    "build_log.txt",
                    "build_log_2.txt",
                    "ogs_challenges_sample.json",
                    "scripts",
                ],
                sources: [
                    "Services/Networking",
                    "Services/OGSClient.swift",
                    "Models/OGSModels.swift",
                    "Models/AppSettings.swift",
                    "Models/SGFPlayerEngine.swift",
                ]),
        .testTarget(name: "SGFPlayerNetworkingTests", dependencies: ["SGFPlayerNetworking"],
                    path: "Tests/Networking")
    ]
)
