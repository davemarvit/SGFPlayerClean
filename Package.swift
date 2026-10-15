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
                    "Services/LegacyOGSClient.swift.txt",
                    "Services/SoundManager.swift",
                    "ViewModels/BoardViewModel.swift",
                    "ViewModels/GameCacheManager.swift",
                    "ViewModels/LayoutViewModel.swift",
                    "ViewModels/VIEWMODELS_README.md",
                    "Views",
                    "build_log.txt",
                    "build_log_2.txt",
                    "ogs_challenges_sample.json",
                    "scripts",
                ],
                sources: [
                    "Services/Networking",
                    "Services/KataGoEngine.swift",
                    "Models/AIModels.swift",
                    "Services/OGSClient.swift",
                    "Models/OGSModels.swift",
                    "Models/OGSScoringState.swift",
                    "Models/AppSettings.swift",
                    "Models/SGFPlayerEngine.swift",
                    "ViewModels/OGSGameViewModel.swift",
                    "ViewModels/TimeControlManager.swift",
                ]),
        .testTarget(name: "SGFPlayerNetworkingTests", dependencies: ["SGFPlayerNetworking"],
                    path: "Tests/Networking")
    ]
)
