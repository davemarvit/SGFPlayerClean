import AppKit
import SwiftUI

@main struct ProvisionalPlayTests {
    @MainActor static func main()throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ text:String) {checks+=1;precondition(value,text)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("provisional-play-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let r=GameRecorder(storage:root);r.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime,values=Array(repeating:Occupancy.empty,count:81)
        var shapes=[StoneFootprint](),tones=0,warnings=0
        r.onAmbiguity={tones+=1};r.onAttention={warnings+=1}
        r.start(size:9,now:now,clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:2,maximumSeconds:200))
        func feed(_ count:Int,hand:Bool=false) {
            for _ in 0..<count {
                now+=0.21
                r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:shapes,capturedAt:now,handObstructed:hand),now:now)
                r.clock.tick(at:now)
            }
        }
        feed(8);check(r.clock.running,"Starting clock failed")
        feed(4,hand:true);check(r.clock.provisionalMoves.isEmpty && r.clock.engine.blackToPlay,"An empty hand wave pressed the clock")
        values[10] = .black
        shapes=[.init(row:1,col:1,center:.init(x:1.49,y:1),radiusCol:0.46,radiusRow:0.46,quality:0.99)]
        let boundary=now+0.21
        feed(10)
        print("TRACE first",r.moveCount,r.pendingMoveCount,r.status,r.clock.provisionalMoves.count,r.tentativeHistory.tentativeSequences,r.placementAmbiguities.map(\.points))
        check(r.moveCount==0 && r.pendingMoveCount==1,"Ambiguous location entered final SGF")
        check(r.clock.provisionalMoves.count==1 && !r.clock.engine.blackToPlay,"A clear completed turn did not switch the clock")
        check(abs(r.clock.provisionalMoves[0].estimate!.time-boundary)<0.001,"Provisional press lost first clear frame")
        check(r.placementAmbiguities.filter{$0.color == .black}.count==1,"Two alternatives counted as two stones")
        check(tones==1,"Ambiguity tone was absent or repeated")
        let originalShapes=shapes
        shapes=[.init(row:1,col:1,center:.init(x:1,y:1),radiusCol:0.46,radiusRow:0.46,quality:0.99)]
        feed(1)
        check(r.tentativeHistory.candidates.count==2,"One centered-looking frame erased a historical alternative")
        shapes=originalShapes;feed(3)
        feed(60)
        check(warnings==0 && tones==1 && r.clock.running,"A timed ambiguous placement repeated the stop-playing warning")
        let firstBlack=r.clock.provisionalMoves[0].after.black,firstPress=r.clock.provisionalMoves[0].estimate
        values[50] = .white;feed(10)
        check(r.clock.provisionalMoves.count==2 && r.clock.engine.blackToPlay,"White's turn was lost behind Black's location ambiguity")
        check(r.placementAmbiguities.count==1 && tones==1,"A clear reply produced another ambiguity warning")
        check(r.clock.engine.black.remaining<firstBlack.remaining,"Black clock failed to run after White")
        let saved=r.autosaveURL!
        r.pause()
        let paused=r.clock.engine
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:saved)
        check(reopened.clock.saveError==nil && reopened.clock.provisionalMoves.count==2,"Restart lost provisional presses")
        check(reopened.placementAmbiguities.count==1 && reopened.pendingMoveCount==2,"Restart lost historical ambiguity")
        check(reopened.clock.engine.black==paused.black && reopened.clock.engine.white==paused.white,"Restart changed balances")
        let uiFile=root.appendingPathComponent("ui.sgf")
        for suffix in ["sgf","clock.json","pending.json","reviews.json"] {
            let source=saved.deletingPathExtension().appendingPathExtension(suffix)
            if FileManager.default.fileExists(atPath:source.path) {try FileManager.default.copyItem(at:source,to:uiFile.deletingPathExtension().appendingPathExtension(suffix))}
        }
        let checkpoint=r.tentativeHistory.checkpoint
        try r.applyPendingPlacements([0:11],expected:checkpoint)
        check(r.placementAmbiguities.isEmpty,"Explicit confirmation did not resolve the placement")
        check(r.clock.engine.black==paused.black && r.clock.engine.white==paused.white && r.clock.provisionalMoves.count==2,"Correcting location changed clock presses")
        do {try r.applyPendingPlacements([0:12],expected:checkpoint);preconditionFailure("Stale placement edit applied")} catch {checks+=1}
        values[10] = .empty;values[11] = .black;shapes=[]
        r.clock.requestResume();r.resume();feed(12)
        print("TRACE resolved",r.moveCount,r.pendingMoveCount,r.status,r.clock.notice)
        check(r.moveCount==2 && r.game.moves[0].1?.0==2 && r.game.moves[0].1?.1==1,"Pending correction did not produce corrected SGF")
        check(r.clock.provisionalMoves.isEmpty && r.clock.moves.count==2,"Finalization duplicated or lost a provisional press")
        check(r.clock.moves[0].estimate==firstPress,"Recognition catch-up replaced the first turn's timestamp")
        check(r.clock.moves[0].after.black==firstBlack,"Finalization awarded another increment")
        r.pause()
        let complete=GameRecorder(storage:root);complete.clock.audible=false;try complete.restoreSavedGame(from:saved)
        check(complete.moveCount==2 && complete.clock.saveError==nil,"Finalized game failed restart")
        // A capture is evidence about an earlier location, not an invented move.
        let captured=GameRecorder(storage:nil);captured.clock.audible=false
        var t=now+1,board=Array(repeating:Occupancy.empty,count:81)
        captured.start(size:9,now:t)
        func captureFeed(_ count:Int,shapes:[StoneFootprint]=[],hand:Bool=false) {
            for _ in 0..<count {t+=0.21;captured.consume(.init(readings:board.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:shapes,capturedAt:t,handObstructed:hand),now:t)}
        }
        captureFeed(8)
        // A1 or B1; White A2 then B2 would capture A1 only after White B1.
        board[0] = .black
        let ambiguous=[StoneFootprint(row:0,col:0,center:.init(x:0.49,y:0),radiusCol:0.46,radiusRow:0.46,quality:0.99)]
        captureFeed(8,shapes:ambiguous)
        check(captured.pendingMoveCount==1 && captured.placementAmbiguities.count==1,"Capture fixture ambiguity missing")
        board[9] = .white;captureFeed(8,shapes:ambiguous)
        board[80] = .black;captureFeed(8,shapes:ambiguous)
        // White B1 is legal only if original Black was A1. Its removal supplies
        // independent evidence; a hand hiding A1 must not resolve it early.
        board[0] = .uncertain;board[1] = .white;captureFeed(5,hand:true)
        check(captured.moveCount==0,"A hand was treated as capture evidence")
        board[0] = .empty;captureFeed(12)
        print("TRACE capture",captured.moveCount,captured.pendingMoveCount,captured.status,captured.tentativeHistory.tentativeSequences)
        check(captured.moveCount==4 && captured.game.moves[0].1?.0==0,"Observed capture did not resolve earlier A1/B1 ambiguity")
        check(captured.placementAmbiguities.isEmpty,"Captured historical ambiguity remained unresolved")
        captured.pause()
        // Capture removal while an unrelated earlier location is provisional.
        let captureFile=root.appendingPathComponent("capture-pending.sgf")
        try "(;AP[PhysicalGo:0.140]FF[4]GM[1]SZ[9]RU[Japanese];B[bb];W[ba];B[cb];W[ca];B[ii];W[ab];B[gi];W[db];B[ei];W[bc])".write(to:captureFile,atomically:true,encoding:.utf8)
        let hold=GameRecorder(storage:root);hold.clock.audible=false;try hold.restoreSavedGame(from:captureFile)
        hold.attachClock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:2));hold.resume()
        var htime=t+1,hboard=DeferredMoveHistory.states(hold.positions.last!),hshapes=[StoneFootprint]()
        func holdFeed(_ count:Int,hand:Bool=false) {
            for _ in 0..<count {htime+=0.21;hold.consume(.init(readings:hboard.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:hshapes,capturedAt:htime,handObstructed:hand),now:htime);hold.clock.tick(at:htime)}
        }
        holdFeed(8);hboard[60] = .black
        hshapes=[.init(row:6,col:6,center:.init(x:6.49,y:6),radiusCol:0.46,radiusRow:0.46,quality:0.99)]
        holdFeed(8)
        check(hold.clock.provisionalMoves.count==1,"Capture setup's ambiguous turn did not switch")
        let capturingBefore=hold.clock.engine
        hboard[20] = .white;hboard[10] = .empty
        let captureStart=htime+0.21;holdFeed(1);holdFeed(8,hand:true);holdFeed(3)
        check(hold.clock.provisionalCapturePaused && !hold.clock.running,"Capture behind an ambiguous placement did not pause both clocks")
        check(abs(hold.clock.engine.white.remaining-(capturingBefore.white.remaining-(captureStart-capturingBefore.anchor!)))<0.001,"Provisional capture charged recognition delay")
        let held=hold.clock.engine
        holdFeed(8,hand:true)
        check(hold.clock.engine.black==held.black && hold.clock.engine.white==held.white,"Removal time charged while location remained provisional")
        let resumeHold=GameRecorder(storage:root);resumeHold.clock.audible=false;try resumeHold.restoreSavedGame(from:captureFile)
        check(resumeHold.clock.provisionalCapturePaused && resumeHold.clock.provisionalMoves.count==1 && resumeHold.pendingMoveCount==1,"Restart lost a provisional capture pause")
        hboard[11] = .empty
        let finalClear=htime+0.21;holdFeed(8)
        print("TRACE hold",hold.moveCount,hold.pendingMoveCount,hold.status,hold.clock.notice,hold.clock.provisionalMoves.count)
        check(hold.clock.running && !hold.clock.automaticCapturePaused && hold.clock.provisionalMoves.count==2,"Capture did not resume after removal with earlier ambiguity retained")
        check(hold.clock.provisionalMoves.last?.estimate?.time==captureStart,"Capture press timestamp was replaced by final removal")
        check(abs(hold.clock.engine.black.remaining-(held.black.remaining-(htime-finalClear)))<0.001,"Capture verification charged the wrong player or time")
        check(hold.placementAmbiguities.count==1,"Unrelated capture erased earlier placement ambiguity")
        hboard[40] = .white;holdFeed(20)
        check(!hold.clock.running && hold.clock.needsCorrection && hold.clock.provisionalMoves.count==2,"Conflicting same-colour addition silently continued")
        hold.pause()
        // Every clock mode must produce exactly the same balances as physical
        // presses, even when SGF catches up much later or in partial prefixes.
        for kind in LocalClockSettings.Kind.allCases where kind != .none {
            let c=LocalGameClock();c.audible=false
            c.configure(.init(kind:kind,mainSeconds:[LocalClockSettings.Kind.byoyomi,.canadian].contains(kind) ? 0:100,periodSeconds:20,periods:5,incrementSeconds:3,maximumSeconds:150,stonesPerPeriod:3),blackToPlay:true);c.ready(at:100)
            var expected=c.engine
            for (i,time) in [102.0,105,108].enumerated() {
                let estimate=ClockPressEstimate(time:time,method:.handMotion,observedLower:time-0.03,observedUpper:time+0.03,estimatedError:0.02,samples:3)
                check(expected.move(black:i%2==0,at:time),"Reference turn failed")
                c.recordMove(number:i+1,black:i%2==0,at:time+0.8,observedAt:time,estimate:estimate,provisional:true)
            }
            expected.advance(to:110);c.tick(at:110)
            check(c.engine==expected && c.provisionalMoves.count==3,"Provisional clock arithmetic differs for \(kind)")
            let estimates=c.provisionalMoves.map(\.estimate)
            c.recordCatchUp(first:1,last:2,blackToPlay:true,at:110)
            check(c.engine==expected && c.provisionalMoves.count==1 && c.moves.count==2,"Partial finalization changed clocks for \(kind)")
            c.recordMove(number:3,black:true,at:110)
            check(c.engine==expected && c.provisionalMoves.isEmpty && c.moves.map(\.estimate)==estimates,"Finalization lost individual presses for \(kind)")
            c.pause(at:110)
            c.recordMove(number:4,black:false,at:112,observedAt:111,estimate:.init(time:111,method:.clearFrame),provisional:true)
            check(c.provisionalMoves.isEmpty && !c.running,"A provisional press bypassed manual pause")
        }
        let expiry=LocalGameClock();expiry.audible=false;expiry.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true)
        let expiryFile=root.appendingPathComponent("expiry.sgf");expiry.bind(to:expiryFile,signature:"expiry");expiry.ready(at:100)
        expiry.recordMove(number:1,black:true,at:111,observedAt:109.9,estimate:.init(time:109.9,method:.handMotion,observedLower:109.8,observedUpper:110.2),provisional:true)
        check(expiry.needsCorrection && !expiry.running && expiry.provisionalMoves.isEmpty,"Uncertain provisional expiry was silently decided")
        let expiryRestored=LocalGameClock();expiryRestored.audible=false;expiryRestored.restore(from:expiryFile,signature:"expiry",moveCount:0,blackToPlay:true)
        check(expiryRestored.saveError==nil && expiryRestored.needsCorrection,"Provisional expiry made saved clocks unreadable")
        // Render the live, clickable per-player counters and historical browser.
        let uiRecorder=GameRecorder(storage:root);uiRecorder.clock.audible=false;try uiRecorder.restoreSavedGame(from:uiFile)
        NSApplication.shared.appearance=NSAppearance(named:.darkAqua)
        let view=LocalClockPanel(clock:uiRecorder.clock,recorder:uiRecorder).environment(\.colorScheme,.dark)
        let host=NSHostingView(rootView:view);host.frame=NSRect(x:0,y:0,width:1050,height:800);host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("ambiguity-clock.png"))}
        print("PASS: \(checks) provisional play checks")
        if CommandLine.arguments.contains("--ui") {
            NSApplication.shared.setActivationPolicy(.regular)
            let window=NSWindow(contentRect:host.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title="Physical Go Ambiguity UI Test";window.contentView=host;window.center();window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps:true)
            print("UI READY",uiFile.path)
            NSApplication.shared.run()
        }
    }
}
