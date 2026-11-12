import Foundation
import AVFoundation

@main struct KokoroVoiceTests {
    static func main() throws {
        setbuf(stdout,nil)
        let args=CommandLine.arguments
        let directory=args.count>1 ? URL(fileURLWithPath:args[1]):KokoroResourceBundle.modelDirectory
        let output=directory.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let engine=try KokoroEngine(modelDirectory:directory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        var gate=SpeechRequestGate();let old=gate.advance();let current=gate.advance()
        check(!gate.accepts(old) && gate.accepts(current),"Stale speech completion accepted")
        _=gate.advance();check(!gate.accepts(current),"Stopped speech could restart")
        check(KokoroSpeech.selected("") && !KokoroSpeech.selected("system"),"Voice preference migration failed")
        var phrases=(1...10).map(String.init)
        phrases += ["Ten. Nine. Three periods left.","One minute thirty seconds","Black time expired","White time expired",
                    "Please pause play. Adjust the camera or board so the whole board is visible, then hold it steady.",
                    "Please pause play. Improve the lighting on the whole board and reduce glare. Keep the stones in place while I check the view."]
        for count in 1...10 {
            phrases += ["\(count) \(count==1 ? "period":"periods") left","Black. \(count) periods left","White. \(count) periods left"]
        }
        for count in 1...30 {phrases += ["Black. \(count) moves left","White. \(count) moves left"]}
        phrases += ["Overtime. 25 moves in 30 seconds","Overtime. 25 moves in 60 seconds"]
        phrases += (1...10).map {"Entering byoyomi. \($0) \($0==1 ? "period":"periods") left"}
        for player in ["Black","White"] {phrases += (1...10).map {"Corrected: \(player), \($0) \($0==1 ? "period":"periods") left"}}
        phrases += ["Clocks paused. Please check the screen."]
        phrases += ["Clocks resumed. Black to play.","Clocks resumed. White to play."]
        // Match LocalGameClock's complete recovery announcement, including the
        // prefix. Caching only "Clocks resumed" leaves these routine messages
        // dependent on cold synthesis and its 1.5-second system-voice fallback.
        for action in ["Capture complete.","Board position restored."] {
            for player in ["Black","White"] {
                phrases.append("\(action) Clocks resumed. \(player) to play.")
            }
        }
        let verifiedPrompts=["Board position verified.","Board position verified. Clocks remain paused."]
        phrases += verifiedPrompts
        let verifiedPhonemes="vˈɛɹəfˌId"
        let pronunciation=EnglishG2P(british:false)
        for text in ["verified","Verified"] {
            check(pronunciation.phonemize(text:text).0==verifiedPhonemes,"Verified fell back to spelling instead of its spoken pronunciation")
        }
        let previous=(try? Data(contentsOf:output.appendingPathComponent("manifest.json")))
            .flatMap{try? JSONDecoder().decode([String:String].self,from:$0)} ?? [:]
        var manifest=[String:String]()
        let start=Date()
        for (index,text) in phrases.enumerated() {
            let data:Data
            // Regenerate these short clips so the same-text cache cannot retain
            // the letter-spelled pronunciation from an earlier lexicon.
            if !verifiedPrompts.contains(text),let name=previous[text],let cached=try? Data(contentsOf:output.appendingPathComponent(name)) {
                data=cached
            } else {
                let result=try engine.synthesize(text:text,voice:"af_heart",speed:1.12)
                if verifiedPrompts.contains(text) {check(result.phonemes.contains(verifiedPhonemes),"Recovery audio used the wrong verified pronunciation")}
                check(!result.samples.isEmpty && result.samples.allSatisfy(\.isFinite),"Invalid audio: \(text)")
                check(result.samples.contains{abs($0)>0.01},"Silent audio: \(text)")
                data=try KokoroSpeech.wav(result.samples)
            }
            let file=String(format:"%03d.wav",index)
            try data.write(to:output.appendingPathComponent(file),options:.atomic)
            let decoded=try AVAudioPlayer(data:data)
            check(decoded.duration>0.10,"Undecodable voice audio")
            if index<10 {check(decoded.duration<1,"Countdown would overlap its next second: \(text) \(decoded.duration)")}
            manifest[text]=file
            if index<10 || index%20==0 {print("\(index+1)/\(phrases.count): \(text) (\(String(format:"%.2f",decoded.duration))s)")}
        }
        try JSONEncoder().encode(manifest).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
        let service=KokoroSpeech(directory:directory)
        check(service.available,"Bundled model unavailable")
        for text in phrases {check(service.cached(text) != nil,"Missing cached prompt: \(text)")}
        let sem=DispatchSemaphore(value:0)
        service.synthesize("White. Thirty-seven moves left.") {data in
            precondition((data?.count ?? 0)>1000,"On-demand synthesis failed");sem.signal()
        }
        check(sem.wait(timeout:.now()+60) == .success,"Offline runtime synthesis timed out")
        print("PASS: \(checks) speech checks; \(phrases.count) cached phrases plus uncached synthesis; \(String(format:"%.1f",Date().timeIntervalSince(start)))s")
    }
}
