import Foundation

/// Acknowledge an interrupted view only after repeated fresh clear frames.
/// Clock resumption has its own announcement; this never resumes play itself.
@MainActor final class BoardViewRecoveryFeedback {
    private let speech:RecoverySpeech
    private var began:Double?
    private var last:Double?
    private var clearSince:Double?
    private var clearFrames=0
    private var acknowledgementOwed=false
    init(speech:RecoverySpeech) {self.speech=speech}
    func reset() {
        began=nil;last=nil;clearSince=nil;clearFrames=0;acknowledgementOwed=false
        speech.cancel(.viewRecovered,reason:"camera view interrupted")
    }
    func observe(clear:Bool,fresh:Bool,now:Double,enabled:Bool,clocksEnabled:Bool,clockRunning:Bool,settings:LocalClockSounds) {
        guard fresh,now.isFinite,last.map({now>$0}) ?? true else {return}
        if let last,now-last>1.5 {clearSince=nil;clearFrames=0}
        last=now
        if !clear {
            if began==nil {began=now;speech.forgetAnnouncement(.clockResume)}
            clearSince=nil;clearFrames=0
            acknowledgementOwed = acknowledgementOwed || now-began!>=0.8
            speech.cancel(.viewRecovered,reason:"board view unclear again")
            return
        }
        guard began != nil else {return}
        if clearSince==nil {clearSince=now}
        clearFrames += 1
        guard clearFrames>=5,now-clearSince!>=1 else {return}
        let owed=acknowledgementOwed || speech.wasHeard(.alignment) || speech.wasHeard(.lighting)
        began=nil;clearSince=nil;clearFrames=0;acknowledgementOwed=false
        speech.resolved(.alignment);speech.resolved(.lighting)
        guard enabled,owed else {return}
        if clockRunning,speech.hasAnnouncement(.clockResume) {return}
        speech.request(.viewRecovered,text:clocksEnabled && !clockRunning
            ? "Board view clear. Clocks remain paused." : "Board view clear.",settings:settings)
    }
}
