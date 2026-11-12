import AppKit
import SwiftUI

@main struct LivePositionIssueTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=try LiveIssueTimingTests.run()
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        // All ten cases: an action and a hold are independent decisions. Global
        // recovery must never turn an arbitrary intersection into a marker.
        for kind in LivePositionIssue.Case.allCases {
            let automatic=LivePositionIssue(id:"case",kind:kind,points:[10],action:nil,reconciling:true)
            check(automatic.markers.isEmpty && automatic.hold==nil,"Automatic reconciliation created an action or hold")
            let actionable=LivePositionIssue(id:"case",kind:kind,points:[10],action:kind == .outage ? .recoverView:.discrepancy(point:10))
            check(actionable.markers==(kind == .outage ? []:[10]) && actionable.hold==nil,"An action stopped clocks or marked a global outage")
        }
        let captureID=UUID()
        let grouped=LivePositionIssue.coalesced([
            .init(id:captureID.uuidString,kind:.capture,points:[10,11,12],action:.review(captureID),hold:.capture),
            .init(id:"absence",kind:.displaced,points:[11,12],action:.discrepancy(point:11)),
            .init(id:"separate",kind:.placement,points:[20],action:.pendingPlacement(number:3))])
        check(grouped.count==2 && grouped[0].points==[10,11,12] && grouped[1].hold==nil,"Mixed capture/placement created duplicate reviews or shared a hold")
        var monitor=BoardAdjustmentMonitor()
        monitor.update(issues:[10:.conflict],clear:[],now:1)
        for _ in 0..<12 {monitor.update(issues:[10:.conflict],clear:[],now:1)}
        check(monitor.visible.isEmpty,"One image became temporal evidence")
        for n in 1...4 {monitor.update(issues:[10:.conflict],clear:[],now:1+Double(n)*0.22)}
        check(monitor.visible[10] == .conflict,"Persistent absence hidden by history")
        for n in 1...8 {monitor.update(issues:[:],clear:[],now:2+Double(n)*0.22)}
        check(monitor.visible[10] == .conflict,"Obscuration falsely cleared real absence")
        for n in 1...6 {monitor.update(issues:[:],clear:[10],now:4+Double(n)*0.22)}
        check(monitor.visible.isEmpty,"Fresh agreement retained a false marker")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("live-issues-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var now=ProcessInfo.processInfo.systemUptime
        func observation(_ values:[Occupancy],stamp:Double?=nil)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:stamp)
        }
        func feed(_ r:GameRecorder,_ values:[Occupancy],count:Int=7) {
            for _ in 0..<count {now += 0.21;r.consume(observation(values,stamp:now),now:now)}
        }
        let r=GameRecorder(storage:root);r.clock.audible=false
        r.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:100));r.pause()
        r.manualMove(at:.init(1,1))
        _=r.confirmClockReview(black:r.clock.engine.black,white:r.clock.engine.white,resume:false)
        r.resume();var board=DeferredMoveHistory.states(r.positions.last!);feed(r,board)
        check(r.state == .recording && r.clock.running,"Live issue setup failed")
        var missing=board;missing[10] = .empty
        feed(r,missing,count:5)
        check(RecordingClarity.action(at:10,recorder:r) == .discrepancy(point:10),"Absent stone opened a historical editor")
        check(RecordingClarity.checkPoints(recorder:r,observation:nil).contains(10),"Absent stone has no action marker")
        let record=r.sgf(),clock=r.clock.engine,position=r.issuePositionSignature
        check(r.acknowledgeRecordedPosition(point:10,position:position)==nil,"Record-correct acknowledgment failed")
        check(r.sgf()==record && r.clock.engine==clock && r.state == .recording,"Acknowledgment mutated history or timing")
        check(r.acknowledgeRecordedPosition(point:10,position:position)==nil && r.clock.engine==clock,"Duplicate acknowledgment changed balances")
        check(RecordingClarity.action(at:10,recorder:r) == .recognition(point:10),"Persistent recognition failure repeated the original question")
        feed(r,board)
        check(r.positionAcknowledgments.isEmpty && !RecordingClarity.checkPoints(recorder:r,observation:nil).contains(10),"Automatic agreement did not clear an open issue")
        check(r.acknowledgeRecordedPosition(point:10,position:position) != nil,"Resolved issue accepted obsolete action")
        let staleDraft=MoveRecoveryDraft(recorder:r,observation:nil),revision=ReviewRevision(r)
        r.browse(0)
        board[20] = .white;feed(r,board,count:10)
        check(r.reviewIndex==0 && r.clock.running,"Saved-position inspection froze tracking or moved the viewed cursor")
        r.returnToLatest()
        check(r.moveCount==2 && r.clock.running && !revision.matches(r),"New move failed to advance while inspecting")
        check(r.approveRecovery(staleDraft) != nil && r.clock.running,"Stale acceptance paused or changed the live game")
        r.pause()
        let stable=DeferredMoveHistory.states(r.positions.last!)
        var absent=stable;absent[10] = .empty
        let captured=now
        for _ in 0..<10 {now += 0.21;r.consume(observation(absent,stamp:captured),now:now)}
        check(r.adjustmentIssues[10]==nil,"Repeated/delayed image created a discrepancy")
        feed(r,absent)
        check(r.adjustmentIssues[10] != nil,"Fresh missing-stone evidence suppressed")
        let state=r.state,paused=r.clock.engine
        let selection=LiveIssueSelection(point:10,position:r.issuePositionSignature,observed:r.discrepancyObservation(at:10))
        let output=try TestArtifacts.directory("live-position-issues")
        let host=NSHostingView(rootView:LiveIssueReviewView(recorder:r,selection:selection,orientation:.init(0),onCorrect:{_ in},onClose:{}).background(Color(nsColor:.windowBackgroundColor)))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:590,height:760),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance
        window.contentView=host;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.15));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("disagreement.png"))
        window.orderOut(nil)
        check(r.state==state && r.clock.engine==paused,"Native inspection changed an explicit pause")
        let beforeAcknowledgment=r.sgf()
        var changedObservation=absent;changedObservation[10] = .white
        feed(r,changedObservation)
        check(r.acknowledgeRecordedPosition(point:10,position:selection.position,observed:selection.observed) != nil,"Changed camera evidence accepted an obsolete acknowledgment")
        check(r.sgf()==beforeAcknowledgment,"Stale acknowledgment rewrote the record")
        try r.flushStorage()
        print("PASS: \(checks) live-issue checks; ten cases, mixed identity, fresh evidence, absent-stone routing, acknowledgment, automatic clearing, stale acceptance and native review")
    }
}
