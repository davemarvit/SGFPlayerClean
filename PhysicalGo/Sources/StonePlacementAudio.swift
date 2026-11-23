import AVFoundation

/// Audio APIs can synchronously wait on the audio server. Keep preparation,
/// seeking and playback off the main thread that renews the laser lease.
final class StonePlacementAudio: @unchecked Sendable {
    private let queue=DispatchQueue(label:"PhysicalGo.stoneAudio",qos:.userInitiated)
    private var player: AVAudioPlayer? // accessed only on queue
    private let playbackForTesting: ((Double)->Void)?
    init(playbackForTesting: ((Double)->Void)?=nil) {
        self.playbackForTesting=playbackForTesting
        let url=Bundle.main.url(forResource:"Stone_click_1",withExtension:"mp3")
        queue.async { [self] in
            guard playbackForTesting==nil,let url else {return}
            player=try? AVAudioPlayer(contentsOf:url)
            player?.prepareToPlay()
        }
    }
    func play(volume:Double) {
        guard volume.isFinite,volume>0 else {return}
        let volume=min(1,volume)
        queue.async { [self] in
            if let playbackForTesting {playbackForTesting(volume);return}
            guard let player else {return}
            player.volume=Float(volume);player.currentTime=0;player.play()
        }
    }
}
