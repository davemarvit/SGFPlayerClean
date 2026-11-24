import AVFoundation

/// Audio APIs can synchronously wait on the audio server. Keep preparation,
/// seeking and playback off the main thread that renews the laser lease.
final class StonePlacementAudio: @unchecked Sendable {
    enum Outcome {case started,unavailable(String)}
    private let queue=DispatchQueue(label:"PhysicalGo.stoneAudio",qos:.userInitiated)
    private var player: AVAudioPlayer? // accessed only on queue
    private var preparationFailure:String? // queue-owned
    private let playbackForTesting: ((Double)->Void)?
    init(playbackForTesting: ((Double)->Void)?=nil,
         resourceURL:URL?=Bundle.main.url(forResource:"Stone_click_1",withExtension:"mp3")) {
        self.playbackForTesting=playbackForTesting
        queue.async { [self] in
            guard playbackForTesting==nil else {return}
            guard let resourceURL else {preparationFailure="The stone click sound is missing from this app.";return}
            do {
                player=try AVAudioPlayer(contentsOf:resourceURL)
                // Preparation is best-effort. A transient audio-output problem
                // must not prevent a later Test click from trying playback again.
                _ = player?.prepareToPlay()
            } catch {preparationFailure="Could not load the stone click: \(error.localizedDescription)"}
        }
    }
    func play(volume:Double,completion:@escaping (Outcome)->Void = {_ in}) {
        guard volume.isFinite,volume>0 else {completion(.unavailable("Stone click volume is muted."));return}
        let volume=min(1,volume)
        queue.async { [self] in
            if let playbackForTesting {playbackForTesting(volume);completion(.started);return}
            guard let player,preparationFailure==nil else {
                completion(.unavailable(preparationFailure ?? "The stone click is unavailable."));return
            }
            player.volume=Float(volume);player.currentTime=0
            completion(player.play() ? .started:.unavailable("The Mac could not start stone click playback. Check the selected audio output."))
        }
    }
}
