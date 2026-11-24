import Foundation

@main struct PhysicalAIMoveClickTests {
    final class Playback:@unchecked Sendable {
        private let lock=NSLock()
        private var values=[Double]()
        func record(_ value:Double) {lock.lock();values.append(value);lock.unlock()}
        var volumes:[Double] {lock.lock();defer{lock.unlock()};return values.filter{$0 != 0.01}}
    }
    @MainActor static func main() async throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        let suite="AIMoveClickTests-"+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        settings.set("off",forKey:"PhysicalGo.soundMode")
        settings.set(Data(#"{"volume":0.73}"#.utf8),forKey:"PhysicalGo.clockSounds")
        let playback=Playback(),audio=StonePlacementAudio(playbackForTesting:playback.record)
        let click=PhysicalAIMoveClick(settings:settings,audio:audio)
        @MainActor func wait(_ predicate:()->Bool) async throws {
            for _ in 0..<200 {
                if predicate() {return}
                try await Task.sleep(nanoseconds:10_000_000)
            }
            preconditionFailure("Timed out waiting for background audio result")
        }
        @MainActor func drain() async throws {
            var done=false
            audio.play(volume:0.01) {_ in Task { @MainActor in done=true }}
            try await wait {done}
        }
        check(click.enabled && abs(click.volume-0.73)<1e-9,"Existing click remains enabled at its saved clock volume")
        click.indicate();try await drain()
        check(playback.volumes==[0.73],"Warnings off must not mute first-light cue")
        settings.set(Data(#"{"volume":0}"#.utf8),forKey:"PhysicalGo.clockSounds")
        let relaunched=PhysicalAIMoveClick(settings:settings,audio:audio)
        check(relaunched.volume==0.73,"Later clock volume changes must not remute independent click")
        click.enabled=false;click.indicate();click.preview();try await drain()
        check(playback.volumes==[0.73],"Click toggle mutes both indications and preview")
        click.enabled=true;click.volume=0;click.indicate();try await drain()
        check(playback.volumes==[0.73],"Explicit zero click volume remains muted")
        click.volume=0.52;click.preview();try await drain()
        check(playback.volumes==[0.73,0.52],"Preview uses the same output and configured level")
        click.indicate();try await drain()
        check(playback.volumes==[0.73,0.52,0.52],"First-light event uses independent click level")
        click.enabled=false
        let restored=PhysicalAIMoveClick(settings:settings,audio:audio)
        check(!restored.enabled && restored.volume==0.52,"Click toggle and level persist independently")
        check(settings.string(forKey:"PhysicalGo.soundMode")=="off","Click controls must not re-enable warning feedback")
        click.volume=2;check(click.volume==1,"Volume must clamp high values")
        click.volume = .nan;check(click.volume==0,"Nonfinite volume must remain muted")
        let missing=PhysicalAIMoveClick(audio:StonePlacementAudio(resourceURL:nil))
        missing.preview();try await wait {missing.status != nil}
        check(missing.status!.contains("missing"),"Missing audio asset must report a visible failure")
        check(playback.volumes.count==3,"No synthetic audio should escape test output")
        print("PASS: \(checks) AI move-click preference, warning independence, migration, preview and failure checks; no audio played")
    }
}
