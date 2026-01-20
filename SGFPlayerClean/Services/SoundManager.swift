import Foundation
import AVFoundation

class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    private var players: [String: AVAudioPlayer] = [:]
    
    // Config
    private let fileExtension = "aiff"
    
    private init() {
        preloadSounds()
    }
    
    private func preloadSounds() {
        let sounds = [
            "game_started", "game_over", "you_win", "you_lose", "draw",
            "ten_seconds", "countdown_10", "countdown_09", "countdown_08", "countdown_07",
            "countdown_06", "countdown_05", "countdown_04", "countdown_03", "countdown_02", "countdown_01",
            "timeout", "byoyomi_start",
            "your_move", "pass", "game_restarted", "opponent_disconnected", "opponent_connected",
            "undo_requested", "undo_accepted", "undo_refused", "connection_lost", "connection_restored"
        ]
        
        for name in sounds {
            if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    players[name] = player
                } catch {
                    print("[SoundManager] ⚠️ Failed to load \(name): \(error)")
                }
            }
        }
    }
    
    func play(_ name: String) {
        if AppSettings.shared.isMuted { return }
        
        guard let player = players[name] else {
            // print("[SoundManager] ⚠️ Sound not found: \(name)")
            return
        }
        
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        
        player.play()
    }
    
    // MARK: - Specialized Helpers
    
    func playCountdown(_ number: Int) {
        if number >= 1 && number <= 10 {
            let key = number == 10 ? "countdown_10" : String(format: "countdown_%02d", number)
            play(key)
        }
    }
    
    func playClockWarning() {
        play("ten_seconds")
    }
}
