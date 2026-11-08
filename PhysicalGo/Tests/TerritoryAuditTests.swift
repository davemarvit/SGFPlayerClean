import AppKit
import SwiftUI

@MainActor func runTerritoryAuditTests() async throws {
    var checks=0
    func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/TerritoryAudit")
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("territory-audit-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
    for ext in ["sgf","reviews.json","pending.json","clock.json"] {
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+ext),to:folder.appendingPathComponent("game."+ext))
    }
    let r=GameRecorder(storage:folder);r.clock.audible=false
    try r.restoreSavedGame(from:folder.appendingPathComponent("game.sgf"))
    let original=r.sgf(),moves=r.moveCount,clock=r.clock.engine
    let scoring=PhysicalScoring();scoring.open(recorder:r,analyzeImmediately:false)
    let a=try JSONDecoder().decode(AIAnalysis.self,from:Data(contentsOf:fixture.appendingPathComponent("analysis.json")))
    check(scoring.receiveAnalysis(a),"Saved-game ownership rejected")
    check(scoring.session!.board.stones.count==175 && scoring.finalReview,"Scoring used a cleared camera or incomplete SGF")
    check(scoring.session!.deadStones.filter {scoring.session!.board.stones[$0] == .black}.count==38,"AI's major Black loss assumption is hidden from the final proposal")
    check(scoring.session!.deadStones.filter {scoring.session!.board.stones[$0] == .white}.count==2,"White dead groups changed")
    print("Actual proposal: \(scoring.countedResult!.black.territory) Black territory, \(scoring.countedResult!.white.territory) White territory; \(scoring.unassignedEmptyPoints) unassigned")
    check(scoring.countedResult!.black.territory==74 && scoring.countedResult!.white.territory==107,"Large territory regions were omitted or living stones counted as territory")
    check(scoring.countedResult!.black.total==78 && scoring.countedResult!.white.total==153.5,"Territory, dead prisoners and komi arithmetic incorrect")
    check(scoring.unassignedEmptyPoints==45,"Unassigned points were silently awarded")
    check(abs(scoring.displayedScoreLead!+80.6684537)<0.001,"AI forecast replaced with discrete proposal count")
    check(!scoring.canAccept,"Unreviewed AI map can be saved as an agreed result")
    scoring.prisonersConfirmed=true
    check(!scoring.canAccept,"Prisoner confirmation bypassed marking agreement")
    scoring.markingsConfirmed=true
    check(scoring.canAccept,"Agreed count cannot be saved")
    scoring.boardDisplay = .counted
    // Actual 19x19 case, in the user's playing orientation.
    let view=PhysicalScoringView(scoring:scoring,recorder:r,orientation:BoardOrientation(3))
    let host=NSHostingView(rootView:view.background(Color(nsColor:.windowBackgroundColor)))
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:930,height:860),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance;window.contentView=host;window.orderFront(nil);host.layoutSubtreeIfNeeded()
    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("physical-score-audit/reviewed-territory.png"));window.orderOut(nil)
    // Point corrections change both the drawn map and count, and revoke agreement.
    let p=scoring.countedTerritory.first {$0.value == .black && scoring.session!.board.stones[$0.key]==nil}!.key
    let before=scoring.countedResult!
    scoring.markingTool = .whiteTerritory;scoring.toggle(p)
    check(scoring.countedTerritory[p] == .white && scoring.countedResult!.white.total==before.white.total+1 && scoring.countedResult!.black.total==before.black.total-1,"Ownership correction and arithmetic diverged")
    check(!scoring.markingsConfirmed && !scoring.canAccept,"Changing a point left previous agreement valid")
    scoring.markingTool = .neutral;scoring.toggle(p)
    check(scoring.countedTerritory[p]==nil,"Neutral point remains counted")
    scoring.markingTool = .blackTerritory;scoring.toggle(p)
    check(scoring.countedResult!.black.total==before.black.total && scoring.countedResult!.white.total==before.white.total,"Restoring ownership did not restore totals")
    let dead=scoring.session!.deadStones.first {scoring.session!.board.stones[$0] == .black}!
    scoring.markingTool = .deadGroups;scoring.toggle(dead)
    check(scoring.countedTerritory[dead]==nil && !scoring.session!.deadStones.contains(dead),"Revived stone still counted as territory/prisoner")
    check(r.sgf()==original && r.moveCount==moves && r.clock.engine.black==clock.black && r.clock.engine.white==clock.white,"Scoring edits changed game history or clock totals")
    scoring.toggle(dead);scoring.markingsConfirmed=true
    scoring.accept(recorder:r)
    check(scoring.accepted && r.game.info.result=="W+75.5","Accepted result did not use the displayed territory count")
    let report=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("game.score.json"))) as! [String:Any]
    check((report["territory"] as? [[String:Any]])?.count==181 && report["markingsConfirmed"] as? Bool==true,"Saved audit omitted territory map/agreement")
    scoring.shutdown()
    print("PASS: \(checks) actual-game territory audit checks (74 Black / 107 White territory, proposed groups, neutral/owner corrections, agreement, history preservation, exported result and map)")
}
