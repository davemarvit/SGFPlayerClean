import AppKit
import SwiftUI

@main struct ScoreOverlayTests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
        let output=URL(fileURLWithPath:"/Users/Dave/Documents/SGF PLayer/work/physical-score-audit")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("score-overlay-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("position.sgf")
        try "(;GM[1]FF[4]AP[PhysicalGo:0.113]SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb])".write(to:file,atomically:true,encoding:.utf8)
        let fixture=SGFGame.from(tree:try SGFParser.parse(text:"(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5]PL[B]AB[aa][ba][ca][ab][cb][ac][bc][cc]AW[bb][gg][hg][ig][gh][ih][gi][hi][ii])"))
        let fixturePlayer=SGFPlayer();fixturePlayer.load(game:fixture)
        let fixtureSession=LocalScoringSession(player:fixturePlayer,handicap:0)
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:file);recorder.pause()
        let original=recorder.sgf()
        let scoring=PhysicalScoring();scoring.open(recorder:recorder,analyzeImmediately:false)
        check(scoring.ownership.isEmpty && scoring.likelyDead.isEmpty,"No analysis must mean no AI overlay")
        let values=(0..<81).map {index -> Double in
            let col=index%9
            return col<3 ? 1:col>5 ? -1:0
        }
        func analysis(_ ownership:[Double],deviations:[Double]?=nil,visits:Int=300)->AIAnalysis {
            .init(id:"overlay",isDuringSearch:false,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.6,scoreLead:2.5,visits:visits),ownership:ownership,ownershipStdev:deviations)
        }
        check(scoring.receiveAnalysis(analysis(values)),"Valid ownership not accepted")
        let owners=scoring.ownership
        check(owners[BoardPosition(4,1)]?.color == .black && owners[BoardPosition(4,7)]?.color == .white,"Ownership perspective reversed")
        check(owners[BoardPosition(4,4)]==nil,"Neutral/unsettled gap was painted")
        check(scoring.likelyDead[BoardPosition(1,1)]==1,"Predicted dead stone not marked")
        check(scoring.session!.deadStones.isEmpty,"An in-progress estimate adjudicated death")
        check(recorder.sgf()==original,"Overlay modified the game")
        let white=AILikelyDeadStones.ownershipEstimates(analysis:analysis(values.map {-$0}),size:9,playerToMove:.white)
        check(white==owners,"Side-to-move changed ownership colors")
        for bad in [analysis(values,deviations:Array(repeating:1,count:81)),analysis(Array(repeating:Double.nan,count:81)),analysis(values,visits:1)] {
            check(scoring.receiveAnalysis(bad),"Fixture root rejected unexpectedly")
            check(scoring.ownership.isEmpty && scoring.likelyDead.isEmpty,"Unreliable ownership painted territory or death")
        }
        _=scoring.receiveAnalysis(analysis(values))
        func render<V:View>(_ view:V,_ name:String,width:CGFloat=500,height:CGFloat=500)throws->NSBitmapImageRep {
            let host=NSHostingView(rootView:view.background(Color(nsColor:.windowBackgroundColor)))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance;window.contentView=host
            window.orderFront(nil);host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            window.orderOut(nil);return bitmap
        }
        func red(_ image:NSBitmapImageRep,at point:BoardPosition,orientation:BoardOrientation)->CGFloat {
            let p=orientation.display(ImagePoint(x:Double(point.col)/8,y:Double(point.row)/8))
            // Sample slightly off the grid line at an unoccupied point.
            let x=Int((30+p.x*440+5)*Double(image.pixelsWide)/500)
            let y=Int((30+p.y*440+5)*Double(image.pixelsHigh)/500)
            return image.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!.redComponent
        }
        scoring.session=fixtureSession
        for turns in 0..<4 {
            let orientation=BoardOrientation(turns)
            let rotated=PhysicalScoreBoard.displayedOwnership(owners,size:9,orientation:orientation)
            check(rotated.count==owners.count,"Rotation dropped ownership points")
            for (p,value) in owners {
                let d=orientation.display(ImagePoint(x:Double(p.col)/8,y:Double(p.row)/8))
                let display=BoardPosition(Int((d.y*8).rounded()),Int((d.x*8).rounded()))
                check(rotated[display]==value,"Ownership does not align with stone coordinates")
            }
            let image=try render(PhysicalScoreBoard(session:scoring.session!,ownership:owners,likelyDead:scoring.likelyDead,finalReview:false,orientation:orientation),"estimate-rotation-\(turns)")
            let black=red(image,at:BoardPosition(4,1),orientation:orientation),neutral=red(image,at:BoardPosition(4,4),orientation:orientation),white=red(image,at:BoardPosition(4,7),orientation:orientation)
            check(black<neutral && neutral<white,"Rendered ownership colors/gap are reversed or misaligned at rotation \(turns): \(black),\(neutral),\(white)")
        }
        _=try render(PhysicalScoringView(scoring:scoring,recorder:recorder,orientation:BoardOrientation(1)),"estimate-screen",width:930,height:740)
        recorder.finish();scoring.open(recorder:recorder,analyzeImmediately:false)
        _=scoring.receiveAnalysis(analysis(values,visits:1000))
        scoring.session=PhysicalScoring.suggestedSession(fixtureSession,analysis:analysis(values,visits:1000),playerToMove:.black)
        check(scoring.finalReview && !scoring.showsCountedTerritory,"Finished game must default to AI shading")
        _=try render(PhysicalScoringView(scoring:scoring,recorder:recorder,orientation:BoardOrientation(1)),"finished-estimate-screen",width:930,height:740)
        scoring.boardDisplay = .counted
        check(scoring.showsCountedTerritory,"Final-count switch did not select editable territory")
        check(scoring.finalReview && scoring.session!.deadStones.contains(BoardPosition(1,1)),"Final score lacks proposed dead group")
        check(scoring.session!.territory[BoardPosition(1,1)] == .black && scoring.session!.territory[BoardPosition(7,7)] == .white,"Final territory disagrees with dead groups")
        _=try render(PhysicalScoringView(scoring:scoring,recorder:recorder,orientation:BoardOrientation(1)),"final-screen",width:930,height:740)
        let final=try render(PhysicalScoreBoard(session:scoring.session!,ownership:owners,likelyDead:scoring.likelyDead,finalReview:true,orientation:BoardOrientation(0)),"final-board")
        let noAI=try render(PhysicalScoreBoard(session:scoring.session!,ownership:[:],likelyDead:[:],finalReview:true,orientation:BoardOrientation(0)),"final-no-ai")
        check(final.representation(using:.png,properties:[:])==noAI.representation(using:.png,properties:[:]),"AI ownership overrides reviewed final territory")
        scoring.markingTool = .neutral;scoring.toggle(BoardPosition(7,7))
        check(scoring.countedTerritory[BoardPosition(7,7)]==nil,"Neutral correction did not remove counted territory")
        _=try render(PhysicalScoreBoard(session:scoring.session!,ownership:owners,likelyDead:scoring.likelyDead,finalReview:true,orientation:BoardOrientation(0)),"neutral-correction")
        scoring.markingTool = .deadGroups;scoring.toggle(BoardPosition(1,1))
        check(!scoring.session!.deadStones.contains(BoardPosition(1,1)) && scoring.session!.territory[BoardPosition(1,1)]==nil,"Living group correction leaves stale territory")
        let fresh=GameRecorder(storage:nil);fresh.clock.audible=false;fresh.start(size:19);fresh.pause()
        scoring.open(recorder:fresh,analyzeImmediately:false)
        check(scoring.ownership.isEmpty && scoring.likelyDead.isEmpty,"New game shows stale previous ownership")
        check(!scoring.showsCountedTerritory && scoring.boardDisplay == .estimate,"Reopening must reset to AI shading")
        scoring.shutdown()
        print("PASS: \(checks) scoring-overlay checks including player perspective, uncertain gaps, invalid data, all four native board rotations, manual final-score corrections and new-position reset")
        try runScoreApprovalTests()
        try await runTerritoryAuditTests()
        try await runPhysicalScoringTests()
    }
}
