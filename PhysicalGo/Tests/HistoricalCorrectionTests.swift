import AppKit
import SwiftUI

@main struct HistoricalCorrectionTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("historical-correction-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/Move55Correction")
        func make()throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            for suffix in ["sgf","reviews.json","clock.json"] {
                try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:file.deletingPathExtension().appendingPathExtension(suffix))
            }
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);return r
        }
        let r=try make(),original=r.autosaveURL!,clock=r.clock.engine
        check(r.moveCount==62 && r.game.moves[54].1?.0==17 && r.game.moves[54].1?.1==12,"Wrong incident fixture")
        let originalText=r.sgf()
        let plan=try HistoricalMoveCorrection(recorder:r,number:55,destination:.init(12,16))
        check(plan.game.moves.count==62 && plan.positions.count==63,"Correction dropped later moves")
        check(plan.positions[55].grid[12][16] == .white && plan.positions[55].grid[12][17] == nil,"N18 to N17 did not change the correct intersection")
        check(plan.reviews.unresolved==1 && plan.reviews.sections.last?.id==r.reviewHistory.sections.last?.id,"Pending review identity/evidence lost")
        check(plan.reviews.sections.last?.after==r.reviewHistory.sections.last?.after,"Correction rewrote observed evidence")
        check(r.sgf()==originalText && r.autosaveURL==original,"Preview changed recording")
        try r.applyHistoricalCorrection(plan)
        check(r.autosaveURL != original && r.moveCount==62,"Correction did not create a copy")
        // Saving the current session can refresh AP/comments, but accepted moves
        // in the original must remain byte-for-byte equivalent as game history.
        let old=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:original,encoding:.utf8)))
        check(RecordingIdentity.signature(for:old)==plan.sourceSignature,"Original game changed")
        check(r.clock.engine.black==clock.black && r.clock.engine.white==clock.white && !r.clock.running,"Correction changed clock balances or restarted play")
        check(r.state == .paused && r.hasDeferredMoves && r.reviewNotice?.contains("55") == true,"Correction lost paused recovery state/notice")
        do {try r.applyHistoricalCorrection(plan);preconditionFailure("Stale correction applied twice")} catch {checks+=1}
        r.retryRecordingSave()
        check(r.sgf().contains("Move corrected from SGF rm to qm"),"Autosave lost correction provenance")
        let loaded=GameRecorder(storage:root);loaded.clock.audible=false;try loaded.restoreSavedGame(from:r.autosaveURL!)
        check(loaded.game.moves[54].1?.0==16 && loaded.moveCount==62 && loaded.hasDeferredMoves && !loaded.recoveryReadBlocked,"Corrected copy did not restore")
        let failure=try make(),failurePlan=try HistoricalMoveCorrection(recorder:failure,number:55,destination:.init(12,16))
        let failureURL=failure.autosaveURL!,beforeFailure=failure.sgf()
        try FileManager.default.setAttributes([.posixPermissions:0o555],ofItemAtPath:root.path)
        do {try failure.applyHistoricalCorrection(failurePlan);preconditionFailure("Unwritable directory accepted correction")} catch {checks+=1}
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        check(failure.autosaveURL==failureURL && failure.sgf()==beforeFailure && failure.game.moves[54].1?.0==17,"Failed write changed the open game")
        let brokenClock=try make(),brokenURL=brokenClock.autosaveURL!
        try Data("damaged".utf8).write(to:brokenURL.deletingPathExtension().appendingPathExtension("clock.json"))
        let brokenRestore=GameRecorder(storage:root);brokenRestore.clock.audible=false;try brokenRestore.restoreSavedGame(from:brokenURL)
        check(HistoricalMoveCorrection.unavailableReason(brokenRestore) != nil,"Correction could discard an unreadable clock sidecar")
        let occupied=try make()
        do { _=try HistoricalMoveCorrection(recorder:occupied,number:55,destination:.init(3,15));preconditionFailure("Occupied point accepted") } catch {checks+=1}
        let small=root.appendingPathComponent("small.sgf")
        try "(;GM[1]FF[4]SZ[9]RU[Japanese]AP[PhysicalGo:0.128];B[aa];W[bb];B[cc])".write(to:small,atomically:true,encoding:.utf8)
        let simple=GameRecorder(storage:root);simple.clock.audible=false;try simple.restoreSavedGame(from:small)
        do {_=try HistoricalMoveCorrection(recorder:simple,number:1,destination:.init(1,1));preconditionFailure("Illegal later move allowed")} catch {check(error.localizedDescription.contains("Move 2"),"First invalid continuation not identified")}
        let cut=try HistoricalMoveCorrection(recorder:simple,number:1,destination:.init(1,1),keepsLaterMoves:false)
        check(cut.discardedMoves==2 && cut.game.moves.count==1,"Explicit truncation did not isolate suffix")
        try simple.applyHistoricalCorrection(cut)
        check(simple.moveCount==1 && FileManager.default.fileExists(atPath:small.path),"Truncation lost original")
        // Camera delivery remains continuous during a long hand placement.
        let live=GameRecorder(storage:nil);live.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime
        live.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:100))
        var values=Array(repeating:Occupancy.empty,count:81)
        func feed(_ count:Int,hand:Bool=false) {
            for _ in 0..<count {now+=0.21;live.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now,handObstructed:hand),now:now)}
        }
        feed(8);check(live.clock.running,"Clock failed to start")
        var pauses=0;live.clock.onAutomaticPause={_ in pauses+=1}
        values[20] = .black;feed(20,hand:true)
        check(live.clock.running && live.moveCount==0 && pauses==0,"Hand frames paused clock or recorded a move")
        feed(12)
        check(live.moveCount==1 && pauses==0 && live.clock.running,"Hand clearance became a camera interruption")
        now+=2;feed(1)
        check(pauses==1 && !live.clock.running,"Real camera gap went undetected")
        live.pause()
        let review=GameRecorder(storage:nil);review.clock.audible=false
        review.start(size:9,now:now)
        var warnings=0;review.onReviewNeeded={warnings+=1}
        var changes=Array(repeating:Occupancy.empty,count:81)
        func reviewFeed(_ count:Int) {
            for _ in 0..<count {now+=0.21;review.consume(.init(readings:changes.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9),now:now)}
        }
        reviewFeed(8);changes[10] = .black;changes[30] = .black;changes[50] = .white;reviewFeed(75)
        check(review.hasDeferredMoves && warnings>0,"A new unresolved review stayed silent without a clock-pause transition")
        check(review.spokenRecoveryInstruction().contains("Open Review"),"Review warning did not explain the issue")
        review.pause()
        let view=HistoricalMoveCorrectionView(recorder:loaded,orientation:.init(3),number:55,onClose:{})
        let host=NSHostingView(rootView:view);host.frame=NSRect(x:0,y:0,width:600,height:820);host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("historical-correction.png"))
        }
        print("PASS: \(checks) historical correction checks: actual move55, legal replay, copy/provenance, review preservation, unchanged clocks, invalid continuation, explicit truncation, stale preview, long hand, true camera gap, review notice, native editor render")
    }
}
