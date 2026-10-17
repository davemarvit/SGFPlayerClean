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
                    "Models/AppModel.swift",
                    "Models/DiagnosticTests.swift",
                    "Models/GameSettings.swift",
                    "Models/SGFPlayerClean.entitlements",
                    "Models/SGFPlayerCleanApp.swift",
                    "Models/StoneMeshFactory.swift",
                    "Resources",
                    "SGFPlayerClean.xcodeproj",
                    "Services/FileLoadingService.swift",
                    "Services/ScreensaverManager.swift",
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
                    "Services/BackgroundGameAnalysis.swift",
                    "Models/AIModels.swift",
                    "Models/ScreensaverConfiguration.swift",
                    "Models/SceneManager3D.swift",
                    "Services/OGSClient.swift",
                    "Models/OGSModels.swift",
                    "Models/OGSScoringState.swift",
                    "Models/LocalScoring.swift",
                    "Models/AppSettings.swift",
                    "Models/SGFPlayerEngine.swift",
                    "Models/StoneJitter.swift",
                    "ViewModels/OGSGameViewModel.swift",
                    "ViewModels/TimeControlManager.swift",
                ]),
        .testTarget(name: "SGFPlayerNetworkingTests", dependencies: ["SGFPlayerNetworking"],
                    path: "Tests/Networking")
    ]
)
