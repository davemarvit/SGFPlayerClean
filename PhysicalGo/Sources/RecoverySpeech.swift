import Foundation

/// One voice for camera/lighting guidance. Recovery cancels unsaid instructions;
/// an audible sentence finishes naturally. Explicit mute/stop still silences it.
@MainActor final class RecoverySpeech {
    enum Topic:String {
        case alignment,lighting,clockPause,clockResume,viewRecovered,recordingWarning
        var isWarning:Bool {self != .clockResume && self != .viewRecovered}
    }
    private struct Prompt {
        let topic:Topic;let text:String;let settings:LocalClockSounds
        let refresh:(()->String?)?
    }
    private let audio:any RecoverySpeechOutput
    private var active:Topic?
    private var activeText:String?
    private var activeResolved=false
    private var heard=Set<Topic>()
    private var queued=[Prompt]()
    var onSpeechEvent:SpeechEventHandler?
    init(audio:(any RecoverySpeechOutput)?=nil) {
        self.audio=audio ?? LocalClockAudio()
        self.audio.onSpeechFinished = { [weak self] in
            guard let self else {return}
            self.active=nil;self.activeText=nil;self.advance()
        }
        self.audio.onSpeechEvent = { [weak self] event,details in
            guard let self else {return}
            if event == "started",let topic=self.active {self.heard.insert(topic)}
            var fields=details;fields["channel"]="recovery";fields["topic"]=self.active?.rawValue ?? "none"
            self.onSpeechEvent?(event,fields)
        }
    }
    /// Refresh queued guidance against current state before playback. Returning
    /// nil discards an obsolete instruction without claiming it was heard.
    func request(_ topic:Topic,text:String,settings:LocalClockSounds,priority:Bool=false,refresh:(()->String?)?=nil) {
        queued.removeAll{$0.topic==topic}
        if active==topic,activeText==text {activeResolved=false;return}
        heard.remove(topic)
        let prompt=Prompt(topic:topic,text:text,settings:settings,refresh:refresh)
        // Important instructions precede queued acknowledgements, but never
        // interrupt a sentence already in progress. One queued update per topic.
        let index=queued.firstIndex { topic.isWarning && !$0.topic.isWarning || priority && topic.isWarning==$0.topic.isWarning }
        queued.insert(prompt,at:index ?? queued.count)
        advance()
    }
    func wasHeard(_ topic:Topic)->Bool {heard.contains(topic) || (active==topic && audio.hasStartedSpeech)}
    func hasAnnouncement(_ topic:Topic)->Bool {wasHeard(topic) || active==topic || queued.contains{$0.topic==topic}}
    func forgetAnnouncement(_ topic:Topic) {heard.remove(topic)}
    /// Drop unsaid messages when state reverses. Once audible, finish the
    /// sentence; the current-state follow-up is queued by the caller.
    func cancel(_ topic:Topic,reason:String) {
        heard.remove(topic)
        resolved(topic,reason:reason)
    }
    func resolved(_ topic:Topic,reason:String="condition recovered") {
        queued.removeAll{$0.topic==topic}
        guard active==topic else {return}
        if !audio.hasStartedSpeech {
            audio.stop(reason:reason);active=nil;activeText=nil;advance()
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
        queued=[];heard=[];audio.stop(reason:reason);active=nil;activeText=nil;activeResolved=false
    }
    private func advance() {
        guard active==nil,!queued.isEmpty else {return}
        let next=queued.removeFirst()
        let text:String?
        if let refresh=next.refresh {text=refresh()} else {text=next.text}
        guard let text,!text.isEmpty else {
            onSpeechEvent?("cancelled before playback",["channel":"recovery","topic":next.topic.rawValue,"phrase":next.text,"reason":"condition changed while queued"])
            advance();return
        }
        active=next.topic;activeText=text;activeResolved=false
        audio.say(text,settings:next.settings,announcement:true)
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
    func began(settings:LocalClockSounds,message:@escaping ()->String = {"Clocks paused. Please check the screen."},enabled:@escaping ()->Bool) {
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
            self.speech.request(.clockPause,text:message(),settings:settings,priority:true,refresh:{enabled() ? message():nil})
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
