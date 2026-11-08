import AppKit
import SwiftUI

@main struct ClockFeedbackTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        try runLocalClockTests()
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("clock-feedback-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let clock=LocalGameClock();clock.audible=false
        clock.configure(.init(kind:.fischer,mainSeconds:100,incrementSeconds:10,maximumSeconds:200),blackToPlay:true)
        clock.bind(to:root.appendingPathComponent("clock.sgf"),signature:"test")
        clock.ready(at:0);clock.recordCatchUp(first:1,last:2,blackToPlay:true,at:4)
        check(clock.running && !clock.requiresReview && clock.engine.blackToPlay,"Catch-up stopped the live clock")
        check(clock.engine.black.remaining==96 && clock.engine.white.remaining==100,"Catch-up invented clock presses or bonuses")
        check(clock.timingNote?.contains("1–2") == true,"Catch-up omitted timing uncertainty")
        let once=clock.engine;clock.recordCatchUp(first:1,last:2,blackToPlay:true,at:5)
        check(clock.engine==once,"Duplicate catch-up charged time")
        clock.recordMove(number:3,black:true,at:6)
        check(clock.running && !clock.requiresReview && !clock.engine.blackToPlay,"Next ordinary move reopened the catch-up gate")
        check(clock.engine.black.remaining==104,"Next ordinary move lost its real increment")
        clock.pause(at:7)
        let restored=LocalGameClock();restored.audible=false
        restored.restore(from:root.appendingPathComponent("clock.sgf"),signature:"test",moveCount:3,blackToPlay:false)
        check(!restored.requiresReview && !restored.running && restored.timingNote != nil,"Catch-up timing state did not survive restart")
        restored.recordCatchUp(first:4,last:5,blackToPlay:false,at:8)
        check(!restored.running,"Catch-up overrode manual pause")
        let expired=LocalGameClock();expired.audible=false;expired.configure(.init(kind:.absolute,mainSeconds:1),blackToPlay:true);expired.ready(at:0)
        expired.recordCatchUp(first:1,last:2,blackToPlay:true,at:2)
        check(expired.requiresReview && !expired.running && expired.engine.expiredBlack==true,"Catch-up silently cleared a genuine timeout")
        let review=LocalGameClock();review.audible=false;review.configure(.init(kind:.absolute,mainSeconds:60),blackToPlay:true);review.ready(at:0)
        review.recover(toBlack:true,reason:"Explicit correction",at:1);review.recordCatchUp(first:1,last:2,blackToPlay:true,at:2)
        check(review.requiresReview && !review.running,"Catch-up cleared an explicit review request")

        let r=GameRecorder(storage:root);r.clock.audible=false;var now=ProcessInfo.processInfo.systemUptime
        r.start(size:9,clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:10,maximumSeconds:200))
        var colors=Array(repeating:Occupancy.empty,count:81),alerts=0
        r.onAttention={alerts+=1}
        func feed(_ count:Int) {
            for _ in 0..<count {
                now+=0.21
                r.consume(BoardObservation(readings:colors.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9),now:now)
            }
        }
        feed(8);colors[10] = .black;colors[20] = .white;feed(12)
        check(r.moveCount==2 && r.clock.running && !r.clock.requiresReview,"Recorder batch confirmation still stopped clocks")
        colors[30] = .black;feed(12)
        check(r.moveCount==3 && r.clock.running && !r.clock.engine.blackToPlay && !r.clock.requiresReview,"Recorder failed the move after catch-up")
        check(alerts==0,"Ordinary recognition beeped before confirmation")

        // Reproduce the exact mixed state: recording active, clock review required.
        r.clock.recover(toBlack:false,reason:"Explicit timing review",at:now)
        check(r.state == .recording && r.clock.requiresReview,"Mixed-state UI fixture failed")
        let host=NSHostingView(rootView:LocalClockPanel(clock:r.clock,recorder:r))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:740),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        let output=try TestArtifacts.file("physical-clock-catchup/clock-review-while-recording.png")
        try bitmap.representation(using:.png,properties:[:])!.write(to:output);window.orderOut(nil);r.pause()
        // Persistent unreadability follows the user's camera-pause preference;
        // short hand occlusion and sequence-only gaps must not stop timing.
        for pauses in [true,false] {
            let health=GameRecorder(storage:nil);health.clock.audible=false;health.clock.pauseOnInterruption=pauses
            var t=ProcessInfo.processInfo.systemUptime
            health.start(size:9,clockSettings:.init(kind:.absolute,mainSeconds:600))
            var values=Array(repeating:Occupancy.empty,count:81)
            func observe(_ count:Int) {
                for _ in 0..<count {t+=0.21;health.consume(BoardObservation(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9),now:t)}
            }
            observe(6);check(health.clock.running,"Health test failed to start clock")
            for i in 20..<45 {values[i] = .uncertain}
            observe(12);check(health.clock.running,"Brief hand occlusion paused the clock")
            observe(50)
            check(health.clock.running && health.needsAttention,"Partial uncertainty incorrectly stopped timing")
            // CameraViewContinuity requires loss of more than a third of the board;
            // 25 uncertain points on a 9x9 board remain a partial view.
            for i in 0..<60 {values[i] = .uncertain}
            observe(50)
            check(health.clock.running != pauses && health.needsAttention,"Persistent unreadability ignored camera-pause preference")
            check(health.recordingProblemTitle=="Camera cannot read the board reliably","Unclear view reported as player error")
            values=Array(repeating:.empty,count:81);observe(6)
            check(health.clock.running && !health.needsAttention,"Readable view failed to resume automatic hold")
            health.pause();observe(60);check(!health.clock.running,"Clear view overrode manual pause")
        }
        var episode=RecordingWarningMonitor(),episodeAlerts=0
        var noisy=Array(repeating:Occupancy.empty,count:81)
        for step in 0...200 {
            if step%20==0 {noisy[step/20] = .black}
            if episode.update(readings:noisy,accepted:Array(repeating:.empty,count:81),now:Double(step)*0.2,blocked:episodeAlerts>0,coalesceEpisode:episodeAlerts>0) != nil {episodeAlerts+=1}
        }
        check(episodeAlerts==2,"Changing noisy candidates produced an alarm storm")
        if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_HEALTH_REPLAY"] {
            struct Sample:Decodable {let session:String;let frame:Int;let readings:[IntersectionReading];let shapes:[StoneFootprint]}
            struct Manifest:Decodable {struct Frame:Decodable {let session:String;let frame:Int;let uptime:Double};let cases:[Frame]}
            let folder=URL(fileURLWithPath:path)
            let samples=try JSONDecoder().decode([Sample].self,from:Data(contentsOf:folder.appendingPathComponent("v3.json")))
            let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("incident/manifest.json")))
            let copy=root.appendingPathComponent("historical-game");try FileManager.default.copyItem(at:folder.appendingPathComponent("before"),to:copy)
            let file=copy.appendingPathComponent("Physical Go 872BBC5C-A49F-4C12-9691-CDA50F8867A5.sgf")
            let replay=GameRecorder(storage:copy);replay.clock.audible=false;try replay.restoreSavedGame(from:file);replay.resume();replay.clock.requestResume()
            let base=replay.moveCount;let start=ProcessInfo.processInfo.systemUptime;let first=manifest.cases.first!.uptime
            for sample in samples {
                let stamp=manifest.cases.first{$0.session==sample.session && $0.frame==sample.frame}!.uptime
                replay.consume(BoardObservation(readings:sample.readings,size:19,footprints:sample.shapes),now:start+stamp-first)
            }
            let points=replay.game.moves.dropFirst(base).compactMap{$0.1.map{$0.1*19+$0.0}}
            print("Incident replay: saved",points,"pending",replay.pendingMoveCount,"reviews",replay.reviewHistory.unresolved,"status",replay.status)
            check(Array([154,59,41,42,23].prefix(points.count))==points,"Photographed replay invented or reordered a move")
            check(!points.isEmpty,"Photographed replay still failed to save the next black move")
            replay.pause()
            if let output=ProcessInfo.processInfo.environment["PHYSICAL_GO_HEALTH_REPAIR"] {
                let destination=URL(fileURLWithPath:output)
                try FileManager.default.copyItem(at:folder.appendingPathComponent("before"),to:destination)
                let repairedFile=destination.appendingPathComponent(file.lastPathComponent)
                let repair=GameRecorder(storage:destination);repair.clock.audible=false;try repair.restoreSavedGame(from:repairedFile)
                let oldBlack=repair.clock.engine.black,oldWhite=repair.clock.engine.white
                var draft=MoveRecoveryDraft(recorder:repair,observation:nil)
                for point in [154,59,41,42,23] {check(draft.add(BoardPosition(point/19,point%19),checkCameraColor:false)==nil,"Photographed recovery order was illegal")}
                let target=DeferredMoveHistory.states(draft.board),final=samples.last!.readings
                check(target.indices.allSatisfy {point in
                    if target[point]==final[point].occupancy {return true}
                    guard final[point].occupancy == .uncertain,!Set([154,59,41,42,23]).contains(point) else {return false}
                    return target[point] == .empty || samples.suffix(10).filter{$0.readings[point].occupancy==target[point]}.count>=3
                },"Recovered game disagrees with final photograph and preceding clear sightings")
                // The last photo catches the final move on its first sighting.
                // Subsequent archived live frames independently retain that stone.
                let log=try String(contentsOf:folder.appendingPathComponent("before/"+file.deletingPathExtension().lastPathComponent+".observations.jsonl"),encoding:.utf8)
                let tail=try log.split(separator:"\n").suffix(8).map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
                check(tail.allSatisfy{row in let p=Array(row["position"] as? String ?? "");return p.count==361 && p[23]=="B"},"Final photographed black stone lacks subsequent sightings")
                check(repair.approveRecovery(draft,allowDeferred:true,manualMoveNumbers:[])==nil,"Photo-backed recovery failed")
                repair.clock.recordCatchUp(first:71,last:75,blackToPlay:false,at:ProcessInfo.processInfo.systemUptime)
                try repair.sgf().write(to:repairedFile,atomically:true,encoding:.utf8);try repair.savePendingCheckpoint()
                check(repair.clock.engine.black==oldBlack && repair.clock.engine.white==oldWhite,"Historical recovery changed clock totals")
                let restarted=GameRecorder(storage:nil);restarted.clock.audible=false;try restarted.restoreSavedGame(from:repairedFile)
                check(restarted.moveCount==75 && restarted.nextPlayer == .white && !restarted.clock.requiresReview,"Recovered game failed restart")
                print("Prepared photo-backed 75-move recovery; both clock totals preserved:",destination.path)
            }
        }
        let warnings=try RecordingWarningTests.run()
        print("PASS: \(checks) clock-feedback checks, \(warnings) recording-warning checks, plus local-clock suite and mixed-state UI render")
    }
}
