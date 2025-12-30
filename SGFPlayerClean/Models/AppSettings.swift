// MARK: - File: AppSettings.swift (v1.100)
import Foundation
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - Playback
    @Published var moveInterval: TimeInterval {
        didSet { UserDefaults.standard.set(moveInterval, forKey: "moveInterval") }
    }
    @Published var jitterMultiplier: Double {
        didSet { UserDefaults.standard.set(jitterMultiplier, forKey: "jitterMultiplier") }
    }
    @Published var shuffleGameOrder: Bool {
        didSet { UserDefaults.standard.set(shuffleGameOrder, forKey: "shuffleGameOrder") }
    }
    @Published var startGameOnLaunch: Bool {
        didSet { UserDefaults.standard.set(startGameOnLaunch, forKey: "startGameOnLaunch") }
    }

    // MARK: - Visuals
    @Published var showMoveNumbers: Bool {
        didSet { UserDefaults.standard.set(showMoveNumbers, forKey: "showMoveNumbers") }
    }
    @Published var showLastMoveDot: Bool {
        didSet { UserDefaults.standard.set(showLastMoveDot, forKey: "showLastMoveDot") }
    }
    @Published var showLastMoveCircle: Bool {
        didSet { UserDefaults.standard.set(showLastMoveCircle, forKey: "showLastMoveCircle") }
    }
    @Published var showBoardGlow: Bool {
        didSet { UserDefaults.standard.set(showBoardGlow, forKey: "showBoardGlow") }
    }
    @Published var showEnhancedGlow: Bool {
        didSet { UserDefaults.standard.set(showEnhancedGlow, forKey: "showEnhancedGlow") }
    }
    @Published var showDropInAnimation: Bool {
        didSet { UserDefaults.standard.set(showDropInAnimation, forKey: "showDropInAnimation") }
    }

    // MARK: - 3D Viewport Default Persistence
    @Published var camera3DRotationX: Double {
        didSet { UserDefaults.standard.set(camera3DRotationX, forKey: "cam3D.rotX") }
    }
    @Published var camera3DRotationY: Double {
        didSet { UserDefaults.standard.set(camera3DRotationY, forKey: "cam3D.rotY") }
    }
    @Published var camera3DDistance: Double {
        didSet { UserDefaults.standard.set(camera3DDistance, forKey: "cam3D.dist") }
    }
    @Published var camera3DPanX: Double {
        didSet { UserDefaults.standard.set(camera3DPanX, forKey: "cam3D.panX") }
    }
    @Published var camera3DPanY: Double {
        didSet { UserDefaults.standard.set(camera3DPanY, forKey: "cam3D.panY") }
    }

    // MARK: - UI Appearance
    @Published var panelOpacity: Double {
        didSet { UserDefaults.standard.set(panelOpacity, forKey: "panelOpacity") }
    }
    @Published var panelDiffusiveness: Double {
        didSet { UserDefaults.standard.set(panelDiffusiveness, forKey: "panelDiffusiveness") }
    }
    
    @Published var folderURL: URL? {
        didSet {
            if let url = folderURL { try? UserDefaults.standard.set(url.bookmarkData(), forKey: "folderURLBookmark") }
        }
    }

    private init() {
        self.moveInterval = UserDefaults.standard.double(forKey: "moveInterval") == 0 ? 0.5 : UserDefaults.standard.double(forKey: "moveInterval")
        self.jitterMultiplier = UserDefaults.standard.object(forKey: "jitterMultiplier") as? Double ?? 1.0
        self.shuffleGameOrder = UserDefaults.standard.bool(forKey: "shuffleGameOrder")
        self.startGameOnLaunch = UserDefaults.standard.bool(forKey: "startGameOnLaunch")
        self.showMoveNumbers = UserDefaults.standard.bool(forKey: "showMoveNumbers")
        self.showLastMoveDot = UserDefaults.standard.object(forKey: "showLastMoveDot") as? Bool ?? true
        self.showLastMoveCircle = UserDefaults.standard.bool(forKey: "showLastMoveCircle")
        self.showBoardGlow = UserDefaults.standard.bool(forKey: "showBoardGlow")
        self.showEnhancedGlow = UserDefaults.standard.bool(forKey: "showEnhancedGlow")
        self.showDropInAnimation = UserDefaults.standard.object(forKey: "showDropInAnimation") as? Bool ?? true
        self.panelOpacity = UserDefaults.standard.object(forKey: "panelOpacity") as? Double ?? 0.3
        self.panelDiffusiveness = UserDefaults.standard.object(forKey: "panelDiffusiveness") as? Double ?? 0.8

        // Load 3D Defaults (or Natural Perspective if empty)
        self.camera3DRotationX = UserDefaults.standard.object(forKey: "cam3D.rotX") as? Double ?? 0.75
        self.camera3DRotationY = UserDefaults.standard.object(forKey: "cam3D.rotY") as? Double ?? 0.0
        self.camera3DDistance = UserDefaults.standard.object(forKey: "cam3D.dist") as? Double ?? 25.0
        self.camera3DPanX = UserDefaults.standard.object(forKey: "cam3D.panX") as? Double ?? 0.0
        self.camera3DPanY = UserDefaults.standard.object(forKey: "cam3D.panY") as? Double ?? 0.0

        if let data = UserDefaults.standard.data(forKey: "folderURLBookmark") {
            var isStale = false
            self.folderURL = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        }
    }
}
