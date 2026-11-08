import SwiftUI
import AppKit

@MainActor func runScoreApprovalTests() throws {
    var checks=0
    func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
    let r=GameRecorder(storage:nil);r.clock.audible=false
    r.start(size:9,info:.init(komi:"6.5",rules:"Japanese"));r.pause();r.pass();r.pass()
    let s=PhysicalScoring();s.open(recorder:r,analyzeImmediately:false)
    s.approveAll(true)
    check(!s.allApproved,"Approved before analysis")
    let a=AIAnalysis(id:"approvals",isDuringSearch:false,turnNumber:2,moveInfos:[],rootInfo:.init(winrate:0.5,scoreLead:0,visits:1000),ownership:Array(repeating:0,count:81))
    _=s.receiveAnalysis(a)
    check(s.requiredApprovals.count==4 && !s.partlyApproved && !s.canAccept,"Japanese approval requirements wrong")
    s.approveAll(true)
    check(s.allApproved && s.canAccept && s.approvalStatus=="All details approved. Ready to save.","Single approval did not enable save")
    s.setApproval(.prisoners,to:false)
    check(s.partlyApproved && !s.canAccept && s.approvalStatus=="Approve prisoner totals to save.","Partial selection lacks specific next step")
    s.setApproval(.prisoners,to:true)
    s.setPrisoners(black:1,white:0)
    check(s.pendingApprovals == [.prisoners] && s.markingsConfirmed,"Prisoner edit cleared unrelated approvals")
    s.approveAll(true);s.setPrisoners(black:1,white:0)
    check(s.allApproved,"Unchanged prisoner totals invalidated agreement")
    s.markingTool = .blackTerritory;s.toggle(BoardPosition(0,0))
    check(s.pendingApprovals == [.territory] && s.prisonersConfirmed,"Territory edit cleared unrelated approvals")
    s.approveAll(true);s.toggle(BoardPosition(0,0))
    check(s.allApproved,"No-op territory assignment revoked approval")
    s.markingTool = .neutral;s.toggle(BoardPosition(0,0))
    check(s.pendingApprovals == [.neutral],"Neutral edit cleared unrelated approvals")
    s.approveAll(true);s.markingTool = .deadGroups;s.toggle(BoardPosition(0,0))
    check(s.allApproved,"Clicking an empty point with dead-group tool revoked agreement")
    // Use a fixture stone solely to exercise group editing.
    var g=SGFGame();g.boardSize=9;g.info.rules="Japanese";g.info.komi="6.5";g.setup=[(.black,4,4)]
    let player=SGFPlayer();player.load(game:g);s.session=LocalScoringSession(player:player,handicap:0)
    s.toggle(BoardPosition(4,4))
    check(s.pendingApprovals == [.deadGroups],"Dead-group edit cleared unrelated approvals")
    let output=try TestArtifacts.directory("physical-score-approval")
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    func render(_ expanded:Bool,_ name:String)throws->NSHostingView<PhysicalScoreApprovals> {
        let host=NSHostingView(rootView:PhysicalScoreApprovals(scoring:s,expanded:expanded))
        host.appearance=NSAppearance(named:.darkAqua)
        host.frame=NSRect(x:0,y:0,width:330,height:expanded ? 300:80);host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        return host
    }
    func buttons(_ v:NSView)->[NSButton] {(v as? NSButton).map {[$0]} ?? v.subviews.flatMap(buttons)}
    let partial=try render(true,"partial")
    let checkbox=buttons(partial).first {$0.title=="Approve all scoring details"}!
    check(checkbox.state == .mixed,"Partial approval lacks native mixed checkbox")
    checkbox.performClick(nil)
    check(s.allApproved && s.canAccept,"Clicking mixed parent did not approve every component")
    let all=try render(false,"all")
    buttons(all).first {$0.title=="Approve all scoring details"}!.performClick(nil)
    check(s.approvedComponents.isEmpty && !s.partlyApproved,"Clicking approved parent did not clear all")
    s.approveAll(true);_=s.receiveAnalysis(a)
    check(!s.allApproved && s.approvedComponents.isEmpty,"Refined analysis retained approvals for old markings")
    var area=g;area.info.rules="Chinese";player.load(game:area);s.session=LocalScoringSession(player:player,handicap:0)
    s.approveAll(true)
    check(s.requiredApprovals.count==3 && s.allApproved && !s.needsPrisonerConfirmation,"Area scoring required irrelevant prisoner approval")
    s.open(recorder:r,analyzeImmediately:false)
    check(s.approvedComponents.isEmpty,"Reopened score retained old consent")
    s.shutdown()
    print("PASS: \(checks) scoring-approval checks (approve all, native mixed checkbox, individual approvals, component-only invalidation, no-op edits, updated analysis, area rules and reopening)")
}
