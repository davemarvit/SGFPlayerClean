import AppKit
import SwiftUI

@MainActor enum BatchCorrectionTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("batch-correction-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func load(_ text:String,history:DeferredMoveHistory?=nil)throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            try text.write(to:file,atomically:true,encoding:.utf8)
            if let history {try JSONEncoder().encode(history).write(to:file.deletingPathExtension().appendingPathExtension("reviews.json"))}
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);r.attachClock(.init(kind:.absolute,mainSeconds:100));return r
        }
        let text="(;GM[1]FF[4]AP[PhysicalGo:0.138]SZ[9]RU[Japanese];B[aa]BL[90];W[bb]WL[91];B[cc]BL[89];W[dd]WL[88])"
        let r=try load(text),original=r.autosaveURL!,originalText=r.sgf(),balances=r.clock.engine
        do {_=try HistoricalMoveCorrection(recorder:r,edits:[.init(number:1,destination:.init(1,1))]);preconditionFailure("Conflicting single edit was accepted")} catch {checks+=1}
        let batch=try HistoricalMoveCorrection(recorder:r,edits:[.init(number:2,destination:.init(0,0)),.init(number:1,destination:.init(1,1))])
        check(batch.edits.map(\.number)==[1,2] && batch.game.moves.count==4,"Batch lost order or later moves")
        check(batch.positions[4].grid[1][1] == .black && batch.positions[4].grid[0][0] == .white,"Simultaneous correction did not exchange mistaken locations")
        check(r.sgf()==originalText && r.autosaveURL==original,"Batch preview changed source")
        check(batch.text.contains("BL[90]") && batch.text.contains("WL[91]"),"Correction discarded original clock properties")
        check(HistoricalMoveCorrection.moveNumber(at:.init(1,1),through:4,game:batch.game,positions:batch.positions)==1,"Dragged older stone was confused with most recent move")
        check(HistoricalMoveCorrection.moveNumber(at:.init(0,0),through:4,game:batch.game,positions:batch.positions)==2,"Corrected stone identity was lost")
        check(HistoricalMoveCorrection.moveNumber(at:.init(8,8),through:4,game:batch.game,positions:batch.positions)==nil,"Empty intersection selected a move")
        try r.applyHistoricalCorrection(batch)
        check(r.autosaveURL != original && r.moveCount==4 && r.nextPlayer == .black,"Batch save lost history or turn")
        check(r.clock.engine.black==balances.black && r.clock.engine.white==balances.white && !r.clock.running,"Batch changed clock balances")
        check(try String(contentsOf:original,encoding:.utf8)==originalText,"Batch modified original SGF")
        try r.flushStorage()
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:r.autosaveURL!)
        check(reopened.sgf().contains("BL[90]") && reopened.sgf().contains("WL[91]"),"Restart/autosave discarded historical clock annotations")
        check(reopened.game.moves[0].1?.0==1 && reopened.game.moves[1].1?.0==0 && reopened.moveCount==4,"Batch SGF failed restart")
        do {try r.applyHistoricalCorrection(batch);preconditionFailure("Stale batch saved twice")} catch {checks+=1}
        let duplicate=try load(text)
        do {_=try HistoricalMoveCorrection(recorder:duplicate,edits:[.init(number:1,destination:.init(2,2)),.init(number:1,destination:.init(3,3))]);preconditionFailure("Duplicate edits accepted")} catch {checks+=1}
        do {_=try HistoricalMoveCorrection(recorder:duplicate,edits:[]);preconditionFailure("Empty batch accepted")} catch {checks+=1}
        // Browsing before a capture identifies a stone no longer present later.
        let captured=try load("(;GM[1]FF[4]AP[PhysicalGo:0.138]SZ[9]RU[Japanese];B[aa];W[ba];B[ii];W[ab])")
        check(HistoricalMoveCorrection.moveNumber(at:.init(0,0),through:1,game:captured.game,positions:captured.positions)==1,"Captured historical stone could not be selected")
        check(HistoricalMoveCorrection.moveNumber(at:.init(0,0),through:4,game:captured.game,positions:captured.positions)==nil,"Captured stone remained draggable in later position")
        let recapture=try HistoricalMoveCorrection(recorder:captured,edits:[.init(number:1,destination:.init(2,2)),.init(number:2,destination:.init(2,3))])
        check(recapture.positions[4].grid[2][2] == .black && recapture.positions[4].stones.count==4,"Replay did not recompute captures after earlier edits")

        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/DisplacedMoveCorrection")
        let fullText=try String(contentsOf:fixture.appendingPathComponent("demo.sgf"),encoding:.utf8)
        let tree=try SGFParser.parse(text:fullText),nodes=tree.mainLineNodes
        let indexes=nodes.indices.filter{nodes[$0].props["B"] != nil || nodes[$0].props["W"] != nil}
        let prefix=SGFWriter.serialize(SGFTree(branches:[.init(sequence:Array(nodes.prefix(indexes[6]+1)))]))
        let game=SGFGame.from(tree:try SGFParser.parse(text:prefix))
        var history=try JSONDecoder().decode(DeferredMoveHistory.self,from:Data(contentsOf:fixture.appendingPathComponent("demo.reviews.json")))
        history.baseMove=7;history.anchorSignature=RecordingIdentity.signature(for:game)
        history.sections[0].committed=false;history.sections[0].moves=nil;history.sections[0].resolvedAfter=nil
        history.sections[0].savedStart=nil;history.sections[0].resolvedAt=nil;history.sections[0].recoverySource=nil
        let demo=try load(prefix,history:history),id=history.sections[0].id
        let restoration=demo.boardRestorationPlan(id)!
        check(restoration.displacedMoveNumber==7 && restoration.kind == .displaced(from:34,to:53,color:.black),"Demo correction did not identify move 7")
        for turns in 0..<4 {
            let destination=BoardPosition(2,15)
            let orientation=BoardOrientation(turns),display=orientation.display(.init(x:Double(destination.col)/18,y:Double(destination.row)/18)),source=orientation.source(display)
            check(Int((source.x*18).rounded())==destination.col && Int((source.y*18).rounded())==destination.row,"Drag coordinates changed with rotation")
        }
        let correction=try HistoricalMoveCorrection(recorder:demo,number:7,destination:.init(2,15))
        check(!correction.reviews.active && correction.reviews.unresolved==0,"Explained physical correction left a fake review gap")
        check(correction.reviews.sections[0].before==history.sections[0].before && correction.reviews.sections[0].after==history.sections[0].after,"Correction destroyed original observed snapshots")
        check(correction.reviews.sections[0].moves==[] && correction.reviews.sections[0].committed,"Relocation was recorded as a new move")
        let demoClocks=demo.clock.engine
        try demo.applyHistoricalCorrection(correction)
        check(demo.moveCount==7 && demo.nextPlayer == .white && !demo.hasDeferredMoves,"Demo correction changed count/turn or stayed blocked")
        check(demo.clock.engine.black==demoClocks.black && demo.clock.engine.white==demoClocks.white && !demo.clock.running,"Demo correction changed clocks")
        var time=ProcessInfo.processInfo.systemUptime
        func feed(_ values:[Occupancy],count:Int) {
            for _ in 0..<count {time+=0.21;demo.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:time,handObstructed:false),now:time)}
        }
        check(demo.resume() == .checking,"Corrected board did not enter verification")
        feed(history.sections[0].before,count:6)
        check(!demo.clock.running,"Old wrong board restarted corrected game's clock")
        feed(history.sections[0].after,count:10)
        check(demo.clock.running && demo.synchronized && demo.moveCount==7,"Corrected physical location could not resume normally")
        demo.pause()
        try demo.flushStorage()
        let demoReloaded=GameRecorder(storage:root);demoReloaded.clock.audible=false;try demoReloaded.restoreSavedGame(from:demo.autosaveURL!)
        check(!demoReloaded.hasDeferredMoves && demoReloaded.game.moves[6].1?.1==2,"Corrected demo did not restore")
        var conflicting=history;conflicting.sections[0].after[0] = .white
        let conflict=try load(prefix,history:conflicting),conflictPlan=try HistoricalMoveCorrection(recorder:conflict,number:7,destination:.init(2,15))
        check(conflictPlan.reviews.unresolved==1 && !conflictPlan.reviews.sections[0].committed,"Unrelated extra stone was swallowed by correction")
        var withPass=history
        withPass.sections.append(.init(before:history.sections[0].after,after:history.sections[0].after,moves:[.init(color:.white,point:nil)],reason:"Actual later pass",firstSeen:1,confirmedAt:2))
        let pass=try load(prefix,history:withPass),passPlan=try HistoricalMoveCorrection(recorder:pass,number:7,destination:.init(2,15))
        check(passPlan.reviews.unresolved==1 && passPlan.reviews.sections.last?.committed==false && passPlan.reviews.sections.last?.suggestedOrders?.first == [.init(color:.white,point:nil)],"Known later pass was silently discarded")
        let full=try load(fullText),fullPlan=try HistoricalMoveCorrection(recorder:full,edits:[.init(number:7,destination:.init(2,15)),.init(number:10,destination:.init(1,5))])
        check(fullPlan.game.moves.count==12 && fullPlan.discardedMoves==0,"After-game batch dropped later demo moves")
        let view=HistoricalMoveCorrectionView(recorder:full,orientation:.init(3),number:7,onClose:{},initialDestination:.init(2,15))
        let host=NSHostingView(rootView:view)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:880),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host;window.orderFront(nil);RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("batch-correction.png"))}
        window.orderOut(nil)
        print("PASS: \(checks) batch and demo displacement correction checks")
        return checks
    }
}
