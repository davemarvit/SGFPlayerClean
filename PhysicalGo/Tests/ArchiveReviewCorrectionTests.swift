import AppKit
import SwiftUI

@main struct ArchiveReviewCorrectionTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("archive-review-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:root)}
        let auto=root.appendingPathComponent("automatic"),manual=root.appendingPathComponent("continuous")
        func archive(_ parent:URL,_ name:String,_ date:Double,_ count:Int,pinned:Bool=false)throws->URL {
            let folder=parent.appendingPathComponent("Diagnostic "+name)
            try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            try Data(repeating:7,count:count).write(to:folder.appendingPathComponent("frame.png"))
            try JSONSerialization.data(withJSONObject:["schemaVersion":1,"startedAt":date,"byteLimit":count,"status":"complete"]).write(to:folder.appendingPathComponent("session.json"))
            if pinned {try Data().write(to:folder.appendingPathComponent("KEEP"))}
            return folder
        }
        let oldest=try archive(auto,"old",1,2_000_000),newest=try archive(manual,"new",2,2_000_000)
        let store=DiagnosticArchiveStorage(roots:[auto,manual],limit:6_000_000)
        let deleted=try store.allocate(payload:2_000_000) {_,removed in removed}
        check(deleted==1 && !fm.fileExists(atPath:oldest.path) && fm.fileExists(atPath:newest.path),"Shared archive failed oldest-first rotation")
        let kept=try archive(auto,"kept",0,1_000_000,pinned:true)
        _=try store.allocate(payload:3_000_000) {_,_ in ()}
        check(fm.fileExists(atPath:kept.path) && !fm.fileExists(atPath:newest.path),"Pinned capture deleted")
        let active=try archive(auto,"active",3,10)
        let lease=try DiagnosticArchiveLock(active.appendingPathComponent(".writer.lock"))
        try JSONSerialization.data(withJSONObject:["schemaVersion":1,"startedAt":3,"byteLimit":4_000_000,"status":"recording"]).write(to:active.appendingPathComponent("session.json"))
        do {_=try store.allocate(payload:2_000_000) {_,_ in ()};preconditionFailure("Active reservation ignored")} catch {checks+=1}
        check(fm.fileExists(atPath:active.path) && fm.fileExists(atPath:kept.path),"Active/protected archive removed")
        withExtendedLifetime(lease) {}
        let outside=root.appendingPathComponent("recording.sgf");try Data("original".utf8).write(to:outside)
        try fm.createSymbolicLink(at:auto.appendingPathComponent("Diagnostic link"),withDestinationURL:outside)
        let unknown=auto.appendingPathComponent("notes");try Data("keep".utf8).write(to:unknown)
        do {_=try store.allocate(payload:4_000_000) {_,_ in ()};preconditionFailure("Protected storage was discarded")} catch {checks+=1}
        let outsideText=try String(contentsOf:outside,encoding:.utf8)
        check(fm.fileExists(atPath:unknown.path) && outsideText=="original","Unknown or symlink target altered")
        // An actual second clip rotates the finished first clip and writes frames.
        let image=CGContext(data:nil,width:128,height:96,bitsPerComponent:8,bytesPerRow:512,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let clips=root.appendingPathComponent("clips")
        let first=MoveEvidenceCapture(root:clips,byteLimit:70_000_000,scheduleDeadlines:false)
        first.offer(image,at:1,online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        let firstURL=URL(fileURLWithPath:first.trigger(["game":"one"],now:1)!)
        first.closeForExit()
        try Data(repeating:0,count:8_000_000).write(to:firstURL.appendingPathComponent("extra-evidence.bin"))
        let second=MoveEvidenceCapture(root:clips,byteLimit:70_000_000,scheduleDeadlines:false)
        second.offer(image,at:2,online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        let secondURL=URL(fileURLWithPath:second.trigger(["game":"two"],now:2)!)
        second.closeForExit()
        check(!fm.fileExists(atPath:firstURL.path) && fm.fileExists(atPath:secondURL.appendingPathComponent("frames/000001.png").path),"Rotation did not recover real frame capture")
        check(DiagnosticArchiveStorage.defaultLimit==10_000_000_000,"Default archive is not 10 GB")

        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/Move55Correction")
        let file=root.appendingPathComponent("game.sgf")
        for suffix in ["sgf","reviews.json","clock.json"] {try fm.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:file.deletingPathExtension().appendingPathExtension(suffix))}
        let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file)
        let reviewID=r.reviewHistory.sections.last!.id,from=BoardPosition(12,17),to=BoardPosition(12,16)
        let combined=try ReviewObservationEdit(recorder:r,reviewID:reviewID,from:from,to:to)
        check(combined.savedMoveNumber==55,"Drag of a wrongly saved stone did not route to move55")
        let plan=try HistoricalMoveCorrection(recorder:r,number:55,destination:to,reviewEdit:combined)
        let clocks=r.clock.engine
        check(plan.reviews.sections.last!.after[244] == .white && plan.reviews.sections.last!.after[245] == .empty,"Combined history/review preview retained stale N18")
        check(plan.reviews.sections.last!.originalCameraAfter==combined.original,"Raw camera interpretation lost")
        try r.applyHistoricalCorrection(plan)
        check(r.moveCount==62 && r.game.moves[54].1?.0==16 && r.reviewHistory.unresolved==1,"Drag guessed move order or dropped later moves")
        check(!r.clock.running && r.clock.engine.black==clocks.black && r.clock.engine.white==clocks.white,"Review correction changed clocks")
        // Actual 0.128 state: history already corrected, but review still at N18.
        let old=GameRecorder(storage:root);old.clock.audible=false;try old.restoreSavedGame(from:file)
        let historyOnly=try HistoricalMoveCorrection(recorder:old,number:55,destination:to)
        try old.applyHistoricalCorrection(historyOnly)
        let snapshot=try ReviewObservationEdit(recorder:old,reviewID:reviewID,from:from,to:to)
        check(snapshot.savedMoveNumber==nil,"Stale snapshot was mistaken for another saved move")
        let sgf=old.sgf()
        try fm.setAttributes([.posixPermissions:0o555],ofItemAtPath:root.path)
        do {try old.correctReviewObservation(snapshot);preconditionFailure("Failed review save published an edit")} catch {checks+=1}
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        check(old.reviewHistory.sections.last!.after==snapshot.original && old.sgf()==sgf,"Write failure changed review or moves")
        try old.correctReviewObservation(snapshot)
        check(old.sgf()==sgf && old.reviewHistory.sections.last!.after==snapshot.corrected,"Snapshot correction changed accepted moves")
        check(old.reviewHistory.sections.last!.originalCameraAfter==snapshot.original,"Snapshot original not preserved")
        do {try old.correctReviewObservation(snapshot);preconditionFailure("Stale drag applied twice")} catch {checks+=1}
        let restored=GameRecorder(storage:root);restored.clock.audible=false;try restored.restoreSavedGame(from:old.autosaveURL!)
        check(restored.reviewHistory.sections.last!.after==snapshot.corrected && !restored.recoveryReadBlocked,"Corrected review failed restart")
        do {_=try ReviewObservationEdit(recorder:restored,reviewID:reviewID,from:from,to:to);preconditionFailure("Empty source accepted")} catch {checks+=1}
        let host=NSHostingView(rootView:ReviewSectionView(recorder:restored,id:reviewID,orientation:.init(3)))
        host.frame=NSRect(x:0,y:0,width:940,height:820);host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("review-drag-correction.png"))}
        print("PASS: \(checks) archive/review checks: shared rotation, newest retention, active reservations, KEEP protection, actual clip writes, move55 drag routing, corrected-copy preservation, snapshot-only correction, unchanged clocks/SGF, stale edits, restart and native review render")
    }
}
