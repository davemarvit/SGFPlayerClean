import Foundation
import AVFoundation

struct LocalClockSounds:Codable,Equatable {
    var moveBeep=true
    var tickEverySecond=false
    var tickFinalTen=false
    var speakFinalTen=true
    var announcePeriods=true
    var announceNinety=true
    var timeoutSound=true
    var volume=0.3
    var voiceID=""
}

typealias SpeechEventHandler=(String,[String:Any])->Void

/// Remember each player's overtime independently across turns and pauses.
struct ByoyomiAnnouncements {
    private var periods=[Bool:Int]()
    mutating func reset(to engine:LocalClockEngine?=nil) {
        periods=[:]
        guard let engine,engine.settings.kind == .byoyomi else {return}
        if engine.black.overtime {periods[true]=engine.black.periods}
        if engine.white.overtime {periods[false]=engine.white.periods}
    }
    mutating func observe(_ engine:LocalClockEngine)->String? {
        guard engine.settings.kind == .byoyomi else {return nil}
        let side=engine.blackToPlay ? engine.black:engine.white
        guard side.overtime else {periods[engine.blackToPlay]=nil;return nil}
        let prior=periods.updateValue(side.periods,forKey:engine.blackToPlay)
        let left="\(side.periods) \(side.periods==1 ? "period":"periods") left"
        if prior==nil {return "Entering byoyomi. "+left}
        return side.periods < prior! ? left:nil
    }
}

@MainActor protocol RecoverySpeechOutput:AnyObject {
    var hasStartedSpeech:Bool {get}
    var onSpeechFinished:(()->Void)? {get set}
    var onSpeechEvent:SpeechEventHandler? {get set}
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool)
    func stop(reason:String)
}

/// Bundled Kokoro speech, system fallback and generated short tones; clock arithmetic remains platform independent.
@MainActor final class LocalClockAudio:NSObject,RecoverySpeechOutput,AVAudioPlayerDelegate,AVSpeechSynthesizerDelegate {
    private let speech=AVSpeechSynthesizer()
    private var tone:AVAudioPlayer?
    private var voice:AVAudioPlayer?
    private var speechGate=SpeechRequestGate()
    private var pendingSpeech=false
    private var lastTickKey=""
    private var announcing=false
    private var byoyomiAnnouncements=ByoyomiAnnouncements()
    private struct PeriodSpeech {let black:Bool;let count:Int;var correction=false}
    private var periodSpeech:PeriodSpeech?
    private var spokenPeriods=[Bool:Int]()
    private var correctingPeriods:Bool {periodSpeech?.correction == true && activeText != nil}
    func resetAnnouncements(to engine:LocalClockEngine?=nil) {byoyomiAnnouncements.reset(to:engine);spokenPeriods=[:]}
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    private var activeText:String?
    private var utteranceID:String?
    private var expectedDuration:Double?
    private var startedAt:Double?
    private var activeUtterance:AVSpeechUtterance?
    var hasStartedSpeech:Bool {startedAt != nil}
    override init() {super.init();speech.delegate=self}
    private func event(_ name:String,reason:String?=nil,engine:String?=nil) {
        guard let activeText else {return}
        var details:[String:Any]=["phrase":activeText,"announcement":announcing]
        if let utteranceID {details["utteranceID"]=utteranceID}
        if let expectedDuration {details["durationSeconds"]=expectedDuration}
        if let reason {details["reason"]=reason}
        if let engine {details["engine"]=engine}
        if let periodSpeech {
            details["player"]=periodSpeech.black ? "Black":"White"
            details["periods"]=periodSpeech.count;details["correction"]=periodSpeech.correction
        }
        if let startedAt {details["playedSeconds"]=max(0,ProcessInfo.processInfo.systemUptime-startedAt)}
        onSpeechEvent?(name,details)
    }
    private func cancelSpeech(reason:String) {
        event(startedAt == nil ? "cancelled before playback":"interrupted",reason:reason)
        activeText=nil;utteranceID=nil;expectedDuration=nil;startedAt=nil;activeUtterance=nil;periodSpeech=nil
        _=speechGate.advance();pendingSpeech=false
        speech.stopSpeaking(at:.immediate);voice?.stop();voice=nil
    }
    func stop(reason:String="explicit stop") {
        cancelSpeech(reason:reason)
        tone?.stop();lastTickKey="";announcing=false
    }
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool=false) {
        beginSpeech(text,settings:settings,announcement:announcement)
    }
    private func beginSpeech(_ text:String,settings:LocalClockSounds,announcement:Bool,period:PeriodSpeech?=nil) {
        if !announcement && announcing && (speech.isSpeaking || voice?.isPlaying == true || pendingSpeech || activeUtterance != nil) {return}
        cancelSpeech(reason:"replaced by a newer speech request")
        let token=speechGate.advance()
        announcing=announcement;activeText=text;periodSpeech=period;utteranceID=UUID().uuidString;event("requested")
        guard KokoroSpeech.selected(settings.voiceID),KokoroSpeech.shared.available else {
            systemSay(text,settings:settings);return
        }
        if let data=KokoroSpeech.shared.cached(text),playVoice(data,settings:settings) {return}
        // Never synthesize a countdown on the critical path. Build-time assets
        // cover 1...10; if missing, speak immediately with the system voice.
        if !announcement {systemSay(text,settings:settings);return}
        pendingSpeech=true
        KokoroSpeech.shared.synthesize(text) {[weak self] data in
            Task {@MainActor [weak self] in
                guard let self,self.speechGate.accepts(token) else {return}
                self.pendingSpeech=false
                if let data,self.playVoice(data,settings:settings) {return}
                self.systemSay(text,settings:settings)
            }
        }
        // Cold model loading must not delay a time-sensitive announcement.
        // Invalidate a late result after falling back, so it cannot speak twice.
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) {[weak self] in
            guard let self,self.speechGate.accepts(token),self.pendingSpeech else {return}
            _=self.speechGate.advance();self.pendingSpeech=false;self.systemSay(text,settings:settings)
        }
    }
    private func playVoice(_ data:Data,settings:LocalClockSounds)->Bool {
        guard let player=try? AVAudioPlayer(data:data) else {return false}
        voice=player;player.delegate=self;player.volume=Float(settings.volume)
        guard player.play() else {voice=nil;return false}
        startedAt=ProcessInfo.processInfo.systemUptime;expectedDuration=player.duration;noteSpokenPeriod();event("started",engine:"Kokoro")
        return true
    }
    private func systemSay(_ text:String,settings:LocalClockSounds) {
        let utterance=AVSpeechUtterance(string:text)
        let systemDefault=KokoroSpeech.selected(settings.voiceID) || settings.voiceID==KokoroSpeech.systemVoiceID
        utterance.voice=systemDefault ? AVSpeechSynthesisVoice(language:"en-US"):AVSpeechSynthesisVoice(identifier:settings.voiceID)
        utterance.rate=0.53;utterance.volume=Float(settings.volume)
        activeUtterance=utterance
        speech.speak(utterance)
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didStart utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.activeUtterance === utterance else {return}
            self.startedAt=ProcessInfo.processInfo.systemUptime;self.noteSpokenPeriod();self.event("started",engine:"system")
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.activeUtterance === utterance else {return}
            self.finished()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didCancel utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.activeUtterance === utterance else {return}
            self.finished(interrupted:true)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {
        Task { @MainActor [weak self] in
            guard let self,self.voice === player else {return}
            self.finished(interrupted:!flag)
        }
    }
    private func finished(interrupted:Bool=false) {
        event(interrupted ? "interrupted":"finished",reason:interrupted ? "audio system ended playback":nil)
        activeText=nil;utteranceID=nil;expectedDuration=nil;startedAt=nil;activeUtterance=nil;voice=nil;pendingSpeech=false;announcing=false;periodSpeech=nil
        onSpeechFinished?()
    }
    private func noteSpokenPeriod() {
        if let periodSpeech {spokenPeriods[periodSpeech.black]=periodSpeech.count}
    }
    private func sayPeriods(_ text:String,engine:LocalClockEngine,settings:LocalClockSounds) {
        let side=engine.blackToPlay ? engine.black:engine.white
        beginSpeech(text,settings:settings,announcement:true,period:.init(black:engine.blackToPlay,count:side.periods))
    }
    func beep(settings:LocalClockSounds,frequency:Double=880,duration:Double=0.045) {
        let rate=22050,count=Int(Double(rate)*duration)
        var data=Data()
        func ascii(_ s:String) {data.append(contentsOf:s.utf8)}
        func u16(_ n:UInt16) {data.append(UInt8(n&255));data.append(UInt8(n>>8))}
        func u32(_ n:UInt32) {for shift in stride(from:0,to:32,by:8) {data.append(UInt8((n>>shift)&255))}}
        ascii("RIFF");u32(UInt32(36+count*2));ascii("WAVEfmt ");u32(16);u16(1);u16(1);u32(UInt32(rate));u32(UInt32(rate*2));u16(2);u16(16);ascii("data");u32(UInt32(count*2))
        for i in 0..<count {
            let envelope=min(1,min(Double(i)/100,Double(count-i)/100))
            let sample=Int16(sin(2*Double.pi*frequency*Double(i)/Double(rate))*envelope*10000)
            u16(UInt16(bitPattern:sample))
        }
        tone=try? AVAudioPlayer(data:data);tone?.volume=Float(settings.volume);tone?.play()
    }
    func beganTurn(_ engine:LocalClockEngine,settings:LocalClockSounds) {
        guard !correctingPeriods else {return}
        let side=engine.blackToPlay ? engine.black:engine.white
        let byoyomi=byoyomiAnnouncements.observe(engine)
        if settings.announcePeriods,let byoyomi {sayPeriods(byoyomi,engine:engine,settings:settings)}
        if engine.settings.kind != .byoyomi,settings.announceNinety,side.remaining<=90,side.remaining>89 {
            say("One minute thirty seconds",settings:settings,announcement:true)
        }
        if settings.announcePeriods && side.overtime && engine.settings.kind == .canadian {
            let description="\(side.stones) moves left"
            say("\(engine.blackToPlay ? "Black":"White"). \(description)",settings:settings,announcement:true)
        }
    }
    func moved(_ engine:LocalClockEngine,settings:LocalClockSounds,previous:LocalClockEngine?=nil) {
        stop(reason:"turn changed");if settings.moveBeep {beep(settings:settings,frequency:660,duration:0.07)}
        if settings.announcePeriods,engine.settings.kind == .byoyomi,let previous {
            let black=previous.blackToPlay,old=black ? previous.black:previous.white,corrected=black ? engine.black:engine.white
            if old.overtime,corrected.overtime,corrected.periods>old.periods,
               let spoken=spokenPeriods[black],spoken<corrected.periods {
                let text="Corrected: \(black ? "Black":"White"), \(corrected.periods) \(corrected.periods==1 ? "period":"periods") left"
                beginSpeech(text,settings:settings,announcement:true,period:.init(black:black,count:corrected.periods,correction:true))
                // The next timer update announces any new opponent overtime
                // after this correction finishes, without consuming it early.
                return
            }
        }
        beganTurn(engine,settings:settings)
    }
    func update(previous:LocalClockEngine,current:LocalClockEngine,settings:LocalClockSounds) {
        if current.expiredBlack != nil && previous.expiredBlack == nil {
            stop(reason:"time expired")
            if settings.timeoutSound {beep(settings:settings,frequency:440,duration:0.3)}
            if settings.announcePeriods || settings.speakFinalTen {say("\(current.expiredBlack == true ? "Black":"White") time expired",settings:settings,announcement:true)}
            return
        }
        guard current.running else {return}
        let side=current.blackToPlay ? current.black:current.white
        let old=previous.blackToPlay ? previous.black:previous.white
        let seconds=Int(ceil(max(0,side.remaining)))
        let key="\(current.blackToPlay):\(side.overtime):\(side.periods):\(seconds)"
        guard key != lastTickKey else {return};lastTickKey=key
        if current.settings.kind != .byoyomi,settings.announceNinety,old.remaining>90,side.remaining<=90,side.remaining>10 {
            say("One minute thirty seconds",settings:settings,announcement:true)
        }
        if !correctingPeriods {
            let byoyomi=byoyomiAnnouncements.observe(current)
            if settings.announcePeriods,let byoyomi {sayPeriods(byoyomi,engine:current,settings:settings)}
        }
        if settings.announcePeriods,current.settings.kind == .canadian,side.overtime,!old.overtime {
            let text="Overtime. \(side.stones) moves in \(current.settings.periodSeconds) seconds"
            say(text,settings:settings,announcement:true)
        }
        if seconds>0 && seconds<=10 && settings.speakFinalTen && (current.settings.kind != .byoyomi || side.overtime) {say(String(seconds),settings:settings)}
        if settings.tickEverySecond || (settings.tickFinalTen && seconds>0 && seconds<=10) {beep(settings:settings)}
    }
}
