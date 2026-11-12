import AppKit
import SwiftUI

@main struct ClockReviewTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        try runLocalClockTests()
        var checks=0
        func check(_ value:Bool,_ text:String) {checks += 1;precondition(value,text)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("clock-review-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime
        recorder.start(size:9,now:now,clockSettings:.init(kind:.canadian,mainSeconds:600))
        let empty=BoardObservation(readings:(0..<81).map {.init(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)},size:9)
        for _ in 0..<6 {now += 0.21;recorder.consume(empty,now:now)}
        check(recorder.clock.running,"Test clock never started")
        recorder.clock.recover(toBlack:true,reason:"Several moves were recovered together.",at:now)
        recorder.clock.recordMove(number:3,black:false,at:now)
        check(recorder.clock.needsCorrection && recorder.clock.notice.contains("Several moves"),"Later move hid original review reason")
        recorder.pause()
        let black=recorder.clock.engine.black,white=recorder.clock.engine.white
        let sgf=recorder.sgf()
        var invalid=black;invalid.remaining=0
        check(!recorder.confirmClockReview(black:invalid,white:white,resume:true),"Invalid time accepted")
        check(recorder.state == .paused && recorder.clock.requiresReview,"Invalid review resumed play")
        let output=URL(fileURLWithPath:"PhysicalGo/.build/ClockReviewUI")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func render<V:View>(_ view:V,_ name:String,width:CGFloat,height:CGFloat)throws {
            let host=NSHostingView(rootView:view);host.frame=NSRect(x:0,y:0,width:width,height:height)
            let window=NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false)
            window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.1))
            host.appearance=NSAppearance(named:.darkAqua);host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            window.orderOut(nil)
        }
        try render(LocalClockPanel(clock:recorder.clock,recorder:recorder),"review-action",width:1280,height:300)
        try render(LocalClockCorrection(clock:recorder.clock,recorder:recorder,resumeAfterReview:true),"review-sheet",width:570,height:470)
        check(recorder.confirmClockReview(black:black,white:white,resume:true),"Unchanged agreed times rejected")
        check(!recorder.clock.needsCorrection && !recorder.clock.running && [.recording,.verifying].contains(recorder.state),"Review skipped board verification")
        check(recorder.clock.engine.black.remaining==black.remaining && recorder.clock.engine.white.remaining==white.remaining,"Review altered agreed times")
        check(recorder.sgf()==sgf,"Clock review changed saved moves")
        var blocked=empty;blocked.lightingBlocked=true
        recorder.consume(blocked,now:now+0.2)
        check(!recorder.clock.running,"Blocked view started clocks")
        for _ in 0..<8 {now += 0.21;recorder.consume(empty,now:now)}
        check(recorder.synchronized && recorder.clock.running && recorder.clock.engine.blackToPlay,"Verified board failed to resume correct clock")
        recorder.pause();recorder.clock.recover(toBlack:true,reason:"Review",at:now)
        let restored=LocalGameClock();restored.audible=false
        // Read the actual checkpoint signature, then exercise persisted review.
        let file=recorder.autosaveURL!,clockFile=file.deletingPathExtension().appendingPathExtension("clock.json")
        try recorder.flushStorage()
        let data=try JSONSerialization.jsonObject(with:Data(contentsOf:clockFile)) as! [String:Any]
        restored.restore(from:file,signature:data["signature"] as! String,moveCount:0,blackToPlay:true)
        check(restored.requiresReview && restored.notice.contains("Review & resume"),"Restored review gave misleading resume instructions")
        check(recorder.confirmClockReview(black:black,white:white,resume:false) && recorder.state == .paused && !recorder.clock.running,"Save-only review resumed play")
        recorder.finish()
        check(!recorder.confirmClockReview(black:black,white:white,resume:true),"Review reopened finished game")
        // Real 86-move game: both pending turns reappeared on every resume,
        // immediately reopening the review the players had just confirmed.
        let incidentRoot=root.appendingPathComponent("incident")
        try FileManager.default.createDirectory(at:incidentRoot,withIntermediateDirectories:true)
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClockResumeLoop")
        for name in ["game.sgf","game.clock.json","game.pending.json","game.reviews.json"] {
            try FileManager.default.copyItem(at:fixtures.appendingPathComponent(name),to:incidentRoot.appendingPathComponent(name))
        }
        let incident=GameRecorder(storage:incidentRoot);incident.clock.audible=false
        try incident.restoreSavedGame(from:incidentRoot.appendingPathComponent("game.sgf"))
        check(incident.moveCount==86 && incident.pendingMoveCount==2 && incident.clock.requiresReview,"Resume-loop fixture lost its pending turns")
        let beforeSGF=incident.sgf(),agreedBlack=incident.clock.engine.black,agreedWhite=incident.clock.engine.white
        let target=DeferredMoveHistory.states(incident.tentativeHistory.candidates.max(by:{$0.moves.count<$1.moves.count})!.boards.last!)
        check(incident.confirmClockReview(black:agreedBlack,white:agreedWhite,resume:true),"Pending clock review was rejected")
        check(incident.clock.provisionalMoves.count==2 && incident.clock.provisionalMoves.allSatisfy{$0.reviewed == true && $0.estimate==nil},"Agreed boundary was lost or manufactured press timestamps")
        check(incident.clock.engine.black==agreedBlack && incident.clock.engine.white==agreedWhite && !incident.clock.running,"Review changed agreed balances or skipped verification")
        check(incident.sgf()==beforeSGF,"Clock review accepted unverified SGF moves")
        var stamp=ProcessInfo.processInfo.systemUptime
        for _ in 0..<8 {
            stamp+=0.21
            incident.consume(.init(readings:target.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:stamp,handObstructed:false),now:stamp)
        }
        check(!incident.clock.requiresReview && incident.clock.running,"Same pending stones reopened the timing review or never resumed")
        check(incident.clock.engine.blackToPlay && incident.clock.lastTimedMove==88,"Confirmed pending turns selected the wrong live player")
        check(incident.clock.engine.white==agreedWhite,"Verification awarded an overtime reset")
        incident.pause();try incident.flushStorage()
        let reopened=GameRecorder(storage:incidentRoot);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:incident.autosaveURL!)
        check(reopened.clock.saveError==nil && !reopened.clock.requiresReview && reopened.clock.lastTimedMove==88,"Restart lost the acknowledged timing boundary")
        // A genuinely new move after the acknowledged position still switches
        // once, even while the old placements have not reached SGF.
        var freshBlack=agreedBlack;freshBlack.remaining=15
        check(incident.confirmClockReview(black:freshBlack,white:agreedWhite,resume:true),"A second explicit balance correction failed")
        stamp=ProcessInfo.processInfo.systemUptime
        func feedIncident(_ values:[Occupancy],_ count:Int) {
            for _ in 0..<count {
                stamp+=0.21
                incident.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:stamp,handObstructed:false),now:stamp)
            }
        }
        feedIncident(target,8)
        var nextTarget=target;nextTarget[0] = .black
        check(target[0] == .empty,"Test next move was occupied")
        feedIncident(nextTarget,6)
        check(!incident.clock.requiresReview && incident.clock.lastTimedMove==89 && !incident.clock.engine.blackToPlay,"Acknowledged history swallowed or duplicated the next live turn")
        incident.pause();try incident.flushStorage()
        let acknowledged=LocalGameClock();acknowledged.audible=false
        acknowledged.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1),blackToPlay:true)
        let balances=acknowledged.engine
        check(acknowledged.correct(black:balances.black,white:balances.white,blackToPlay:true,moveCount:0,at:100),"Agreement rejected")
        acknowledged.acknowledgePendingTurns([[10],[20]],firstBlack:true,moveCount:0)
        acknowledged.recordCatchUp(first:1,last:2,blackToPlay:true,at:100)
        check(acknowledged.baseMove==2 && acknowledged.engine.black==balances.black,"Saving agreed placements changed time or lost correction boundary")
        acknowledged.undo(to:1,blackToPlay:false,at:100)
        check(acknowledged.requiresReview && acknowledged.engine.black==balances.black && acknowledged.engine.white==balances.white,"Undo invented thinking times for acknowledged turns")
        print("PASS: \(checks) clock-review checks plus native review action and sheet renders")
    }
}
