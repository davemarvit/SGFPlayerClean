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
    @Published var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: "isMuted") }
    }
    @Published var voiceVolume: Double {
        didSet { 
            UserDefaults.standard.set(voiceVolume, forKey: "voiceVolume");
            SoundManager.shared.setVolume(Float(voiceVolume))
        }
    }
    @Published var stoneVolume: Double {
        didSet { UserDefaults.standard.set(stoneVolume, forKey: "stoneVolume") }
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
            if let url = folderURL {
                do {
                    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(data, forKey: "folderURLBookmark")
                } catch {
                     print("❌ Failed to save folder bookmark: \(error)")
                }
            }
        }
    }
    
    @Published var lastPlayedGameURL: URL? {
        didSet {
            if let url = lastPlayedGameURL {
                // For the specific file, we can also try security scope, or just rely on path if folder is open.
                // Let's use security scope to be safe.
                do {
                    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(data, forKey: "lastPlayedGameBookmark")
                } catch {
                    print("❌ Failed to save last game bookmark: \(error)")
                }
            }
        }
    }

    private init() {
        self.moveInterval = UserDefaults.standard.double(forKey: "moveInterval") == 0 ? 0.5 : UserDefaults.standard.double(forKey: "moveInterval")
        self.jitterMultiplier = UserDefaults.standard.object(forKey: "jitterMultiplier") as? Double ?? 1.0
        self.shuffleGameOrder = UserDefaults.standard.bool(forKey: "shuffleGameOrder")
        self.startGameOnLaunch = UserDefaults.standard.bool(forKey: "startGameOnLaunch")
        self.isMuted = UserDefaults.standard.bool(forKey: "isMuted")
        // Volume Init
        let vVol = UserDefaults.standard.object(forKey: "voiceVolume") as? Double
        self.voiceVolume = (vVol == nil) ? 1.0 : vVol!
        
        let sVol = UserDefaults.standard.object(forKey: "stoneVolume") as? Double
        self.stoneVolume = (sVol == nil) ? 1.0 : sVol!
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
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale { print("⚠️ Folder bookmark is stale") }
                self.folderURL = url
            } catch {
                print("❌ Failed to resolve folder bookmark: \(error)")
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: "lastPlayedGameBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                self.lastPlayedGameURL = url
            } catch {
                print("❌ Failed to resolve last game bookmark: \(error)")
            }
        }
    }
}

// MARK: - Sound Manager (Embedded for Compilation)
import AVFoundation

class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    private var players: [String: AVAudioPlayer] = [:]
    private let fileExtension = "aiff"
    
    // State for Debouncing
    private var lastPlayedCountdown: Int? = nil
    private var lastWarningTime: TimeInterval = 0
    
    private init() {
        preloadSounds()
    }
    
    private func preloadSounds() {
        // Updated List
        let sounds = [
            "game_started", "game_over", "you_win", "you_lose", "draw",
            "won_resignation", "lost_resignation", "won_timeout", "lost_timeout",
            "ten_seconds", "countdown_10", "countdown_09", "countdown_08", "countdown_07",
            "countdown_06", "countdown_05", "countdown_04", "countdown_03", "countdown_02", "countdown_01",
            "timeout", "byoyomi_start", "byoyomi_simple",
            // "your_move", // REMOVED
            "pass", "game_restarted",
            "opponent_disconnected", "opponent_connected",
            "undo_requested", "undo_accepted", "undo_refused", "connection_lost", "connection_restored",
            // Periods
            "periods_1", "periods_2", "periods_3", "periods_4", "periods_5"
        ]
        
        var loadedCount = 0
        for name in sounds {
            if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    players[name] = player
                    loadedCount += 1
                } catch {
                    print("[SoundManager] ⚠️ Failed to load \(name): \(error)")
                }
            } else {
                 print("[SoundManager] ❌ File Not Found in Bundle: \(name).\(fileExtension)")
            }
        }
        print("[SoundManager] 🏁 Preload Complete. Loaded \(loadedCount)/\(sounds.count) sounds.")
    }
    
    func setVolume(_ vol: Float) {
        for p in players.values { p.volume = vol }
    }
    
    func play(_ name: String) {
        if AppSettings.shared.isMuted { return }
        
        guard let player = players[name] else { return }
        if player.volume != Float(AppSettings.shared.voiceVolume) {
            player.volume = Float(AppSettings.shared.voiceVolume)
        }
        
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }
    
    func playCountdown(_ number: Int) {
        // Debounce: Don't repeat the same number
        guard lastPlayedCountdown != number else { return }
        
        if number >= 1 && number <= 10 {
            let key = number == 10 ? "countdown_10" : String(format: "countdown_%02d", number)
            play(key)
            lastPlayedCountdown = number
        } else {
            // Reset if out of range (so we can count down again later)
            lastPlayedCountdown = nil
        }
    }
    
    func playClockWarning() {
        // Debounce: Only warn once per 10s roughly? Or rely on caller?
        // Caller calls this when exactly 10s left. 
        // Logic in OGSClient checks 'main <= 10 && main >= 1'. 
        // We should just play "ten_seconds" once.
        play("ten_seconds")
    }
    
    func playPeriodCount(_ count: Int) {
        if count >= 1 && count <= 5 {
            play("periods_\(count)")
        }
    }
    
    func playByoyomiStart() {
        play("byoyomi_simple") // Use simple phonetic version
    }
    
    func playWinner(isMe: Bool, isDraw: Bool, method: String? = nil) {
        if isDraw {
            play("draw")
        } else if isMe {
            if let m = method?.lowercased() {
                if m.contains("resignation") { play("won_resignation"); return }
                if m.contains("timeout") { play("won_timeout"); return }
            }
            play("you_win")
        } else {
            if let m = method?.lowercased() {
                if m.contains("resignation") { play("lost_resignation"); return }
                if m.contains("timeout") { play("lost_timeout"); return }
            }
            play("you_lose")
        }
    }
}
