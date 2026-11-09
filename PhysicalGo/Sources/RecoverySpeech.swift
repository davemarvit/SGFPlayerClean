import Foundation

/// One voice for camera/lighting guidance. Recovery cancels unsaid instructions;
/// an audible sentence finishes naturally. Explicit mute/stop still silences it.
@MainActor final class RecoverySpeech {
    enum Topic:String {case alignment,lighting,clockPause,clockResume,viewRecovered}
    private struct Prompt {let topic:Topic;let text:String;let settings:LocalClockSounds}
    private let audio:any RecoverySpeechOutput
    private var active:Topic?
    private var activeResolved=false
    private var heard=Set<Topic>()
    private var queued=[Prompt]()
    var onSpeechEvent:SpeechEventHandler?
    init(audio:(any RecoverySpeechOutput)?=nil) {
        self.audio=audio ?? LocalClockAudio()
        self.audio.onSpeechFinished = { [weak self] in
            guard let self else {return}
            self.active=nil;self.advance()
        }
        self.audio.onSpeechEvent = { [weak self] event,details in
            guard let self else {return}
            if event == "started",let topic=self.active {self.heard.insert(topic)}
            var fields=details;fields["channel"]="recovery";fields["topic"]=self.active?.rawValue ?? "none"
            self.onSpeechEvent?(event,fields)
        }
    }
    func request(_ topic:Topic,text:String,settings:LocalClockSounds,priority:Bool=false) {
        queued.removeAll{$0.topic==topic}
        guard active != topic else {activeResolved=false;return}
        heard.remove(topic)
        let prompt=Prompt(topic:topic,text:text,settings:settings)
        if priority {queued.insert(prompt,at:0)} else {queued.append(prompt)}
        advance()
    }
    func wasHeard(_ topic:Topic)->Bool {heard.contains(topic) || (active==topic && audio.hasStartedSpeech)}
    func hasAnnouncement(_ topic:Topic)->Bool {wasHeard(topic) || active==topic || queued.contains{$0.topic==topic}}
    func forgetAnnouncement(_ topic:Topic) {heard.remove(topic)}
    /// Superseded factual clock messages must not play after the state reverses.
    func cancel(_ topic:Topic,reason:String) {
        queued.removeAll {$0.topic==topic};heard.remove(topic)
        guard active==topic else {return}
        audio.stop(reason:reason);active=nil;activeResolved=false;advance()
    }
    func resolved(_ topic:Topic,reason:String="condition recovered") {
        queued.removeAll{$0.topic==topic}
        guard active==topic else {return}
        if !audio.hasStartedSpeech {
            audio.stop(reason:reason+" before playback");active=nil;advance()
        } else if !activeResolved {
            activeResolved=true
            onSpeechEvent?("finishing guidance",["channel":"recovery","topic":topic.rawValue,"reason":reason])
        }
    }
    func finishCurrent(reason:String) {
        queued=[]
        if let active {resolved(active,reason:reason)}
    }
    func stop(reason:String) {
        queued=[];heard=[];audio.stop(reason:reason);active=nil;activeResolved=false
    }
    private func advance() {
        guard active==nil,!queued.isEmpty else {return}
        let next=queued.removeFirst();active=next.topic;activeResolved=false
        audio.say(next.text,settings:next.settings,announcement:true)
    }
}

/// Pair audible automatic pauses with their recovery; sub-second holds stay quiet.
@MainActor final class ClockPauseAnnouncements {
    private let speech:RecoverySpeech
    private let delay:UInt64
    private var pending:Task<Void,Never>?
    private var resumeOwed=false
    init(speech:RecoverySpeech,delay:TimeInterval=1) {
        self.speech=speech;self.delay=UInt64(max(0,delay)*1_000_000_000)
    }
    deinit {pending?.cancel()}
    func began(settings:LocalClockSounds,enabled:@escaping ()->Bool) {
        pending?.cancel()
        // If a queued resume was canceled by another brief hold, the original
        // audible pause still needs closure when this hold clears.
        if speech.wasHeard(.clockResume) {resumeOwed=false}
        if speech.wasHeard(.clockPause) {resumeOwed=true}
        // Camera/lighting guidance also tells players to pause. Discard old
        // completed guidance at the start of a new hold, retaining live speech.
        speech.forgetAnnouncement(.alignment);speech.forgetAnnouncement(.lighting)
        speech.cancel(.clockResume,reason:"clocks paused again")
        speech.forgetAnnouncement(.clockPause)
        guard enabled() else {return}
        pending=Task { @MainActor [weak self] in
            guard let self else {return}
            do {try await Task.sleep(nanoseconds:self.delay)} catch {return}
            guard !Task.isCancelled,enabled() else {return}
            self.speech.request(.clockPause,text:"Clocks paused. Please check the screen.",settings:settings,priority:true)
        }
    }
    func cleared(running:Bool,blackToPlay:Bool,enabled:Bool,settings:LocalClockSounds) {
        pending?.cancel();pending=nil
        let announced=resumeOwed || speech.wasHeard(.clockPause) || speech.wasHeard(.alignment) || speech.wasHeard(.lighting)
        speech.resolved(.clockPause,reason:running ? "clocks resumed":"clock hold cleared")
        if running && enabled && announced {
            resumeOwed=true
            speech.request(.clockResume,text:"Clocks resumed. \(blackToPlay ? "Black":"White") to play.",settings:settings,priority:true)
        } else {
            resumeOwed=false
            speech.cancel(.clockResume,reason:"no audible resume needed")
        }
        speech.forgetAnnouncement(.clockPause)
        speech.forgetAnnouncement(.alignment);speech.forgetAnnouncement(.lighting)
    }
}
