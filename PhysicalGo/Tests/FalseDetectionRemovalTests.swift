import AppKit
import SwiftUI

@MainActor enum FalseDetectionRemovalTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("false-detection-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/FalseB19")
        func make()throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            for ext in ["sgf","clock.json","reviews.json"] {
                try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+ext),to:file.deletingPathExtension().appendingPathExtension(ext))
            }
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);return r
        }
        let r=try make(),url=r.autosaveURL!,balances=r.clock.engine,original=r.sgf()
        check(r.moveCount==11 && r.positions.last!.grid[17][0] == .black && r.clock.baseMove==11,"Wrong B19 fixture")
        let plan=try HistoricalMoveCorrection(recorder:r,edits:[.init(number:11,destination:nil)])
        check(plan.removesFalseDetection && plan.game.moves.count==10 && plan.positions.count==11,"Removal added a pass or kept false move")
        check(plan.positions.last==r.positions[10] && plan.positions.last!.grid[17][0]==nil,"Removal did not restore position after 10")
        check(plan.positions.last!.grid[14][15]==nil,"Removal restored a prisoner from a valid earlier capture")
        check(r.autosaveURL==url && r.sgf()==original,"Preview modified the active game")
        try r.applyHistoricalCorrection(plan)
        check(r.autosaveURL != url && r.moveCount==10 && r.nextPlayer == .black,"Removal failed to return Black's turn")
        check(r.clock.engine.black==balances.black && r.clock.engine.white==balances.white && !r.clock.running && r.clock.requiresReview,"Removal invented clock refund or skipped review")
        check(r.clock.baseMove==10 && r.state == .paused,"Removal left a nonreloadable clock or resumed play")
        check(SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:url,encoding:.utf8))).moves.count==11,"Original recording lost")
        r.retryRecordingSave()
        check(r.sgf().contains("False detection removed: move 11"),"Autosave lost removal provenance")
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:r.autosaveURL!)
        check(reopened.moveCount==10 && reopened.nextPlayer == .black && reopened.clock.saveError==nil && reopened.clock.requiresReview,"Corrected recording failed restart")
        do {try r.applyHistoricalCorrection(plan);preconditionFailure("Stale removal accepted twice")} catch {checks+=1}
        let invalid=try make()
        for edits:[HistoricalMoveCorrection.Edit] in [[.init(number:9,destination:nil)],[.init(number:11,destination:nil),.init(number:1,destination:.init(0,0))]] {
            do {_=try HistoricalMoveCorrection(recorder:invalid,edits:edits);preconditionFailure("Unsafe mixed or earlier removal accepted")} catch {checks+=1}
        }
        let failed=try make(),failedURL=failed.autosaveURL!,failedPlan=try HistoricalMoveCorrection(recorder:failed,edits:[.init(number:11,destination:nil)])
        try FileManager.default.setAttributes([.posixPermissions:0o555],ofItemAtPath:root.path)
        do {try failed.applyHistoricalCorrection(failedPlan);preconditionFailure("Unwritable removal accepted")} catch {checks+=1}
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        check(failed.autosaveURL==failedURL && failed.moveCount==11,"Failed save changed active game")
        // Removing a false capturing move restores only its own prisoners.
        let captureURL=root.appendingPathComponent("capture.sgf")
        try "(;GM[1]FF[4]AP[PhysicalGo:0.190]SZ[9]PL[B];B[ba];W[aa];B[ab])".write(to:captureURL,atomically:true,encoding:.utf8)
        let capture=GameRecorder(storage:root);try capture.restoreSavedGame(from:captureURL)
        let undoCapture=try HistoricalMoveCorrection(recorder:capture,edits:[.init(number:3,destination:nil)])
        check(undoCapture.game.moves.count==2 && undoCapture.positions.last!.grid[0][0] == .white && undoCapture.positions.last!.grid[1][0]==nil,"False capture removal lost setup/prisoner")
        try capture.applyHistoricalCorrection(undoCapture);capture.retryRecordingSave()
        check(capture.sgf().contains("False detection removed: move 3"),"Empty-game removal lost provenance")
        let singleURL=root.appendingPathComponent("single.sgf")
        try "(;GM[1]FF[4]AP[PhysicalGo:0.190]SZ[9];B[aa])".write(to:singleURL,atomically:true,encoding:.utf8)
        let single=GameRecorder(storage:root);try single.restoreSavedGame(from:singleURL)
        let emptyPlan=try HistoricalMoveCorrection(recorder:single,edits:[.init(number:1,destination:nil)])
        try single.applyHistoricalCorrection(emptyPlan);single.retryRecordingSave()
        check(single.moveCount==0 && single.nextPlayer == .black && single.sgf().contains("False detection removed: move 1"),"First false move removal did not preserve empty game/provenance")
        let emptyHost=NSHostingView(rootView:HistoricalMoveCorrectionView(recorder:single,orientation:.init(0),number:1,onClose:{}))
        emptyHost.frame=NSRect(x:0,y:0,width:620,height:850);emptyHost.layoutSubtreeIfNeeded()
        // Native correction entry point includes the removal action for B19.
        let host=NSHostingView(rootView:HistoricalMoveCorrectionView(recorder:invalid,orientation:.init(1),number:11,onClose:{}))
        host.frame=NSRect(x:0,y:0,width:620,height:850);host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("false-detection-correction.png"))
        }
        print("PASS: \(checks) false-detection removal checks: real B19, Black still to play, retained captures, copy/restart, no inferred clock refund, stale/failure protection")
        return checks
    }
}
