import Foundation
import Combine

/// A separate preference for the AI's first-light cue. Warning feedback and
/// clock speech neither mute it nor change its volume after migration.
@MainActor final class PhysicalAIMoveClick:ObservableObject {
    private struct Settings:Codable {let enabled:Bool;let volume:Double}
    private struct LegacyVolume:Decodable {let volume:Double}
    private static let key="PhysicalGo.aiMoveClick"
    private let preferences:UserDefaults?
    private let audio:StonePlacementAudio
    @Published var enabled:Bool {didSet {status=nil;save()}}
    @Published private var storedVolume:Double
    var volume:Double {
        get {storedVolume}
        set {storedVolume=newValue.isFinite ? min(1,max(0,newValue)):0;status=nil;save()}
    }
    @Published private(set) var status:String?
    init(settings:UserDefaults?=nil,audio:StonePlacementAudio?=nil) {
        preferences=settings;self.audio=audio ?? StonePlacementAudio()
        let saved=settings?.data(forKey:Self.key).flatMap {try? JSONDecoder().decode(Settings.self,from:$0)}
        let legacy=settings?.data(forKey:"PhysicalGo.clockSounds").flatMap {try? JSONDecoder().decode(LegacyVolume.self,from:$0)}
        enabled=saved?.enabled ?? true
        let initial=saved?.volume ?? legacy?.volume ?? 0.3
        storedVolume=initial.isFinite ? min(1,max(0,initial)):0
        // Freeze migration now so later clock-volume changes do not silently
        // change the new independent click setting across app launches.
        save()
    }
    private func save() {
        guard let preferences,let data=try? JSONEncoder().encode(Settings(enabled:enabled,volume:volume)) else {return}
        preferences.set(data,forKey:Self.key)
    }
    /// Called only by guidance's once-per-move confirmed-illumination event.
    func indicate() {play(source:"first_light")}
    func preview() {play(source:"preview")}
    private func play(source:String) {
        PhysicalLatencyTrace.shared?.record("ai_move_click_requested",fields:["source":source,"enabled":String(enabled)],metrics:["volume":volume])
        guard enabled,volume>0 else {return}
        audio.play(volume:volume) { [weak self] result in
            Task { @MainActor in
                guard let self else {return}
                switch result {
                case .started:self.status="Playback started on the Mac’s selected audio output."
                case let .unavailable(message):self.status=message
                }
                PhysicalLatencyTrace.shared?.record("ai_move_click_playback",fields:["source":source,"result":self.status ?? "unknown"])
            }
        }
    }
}
