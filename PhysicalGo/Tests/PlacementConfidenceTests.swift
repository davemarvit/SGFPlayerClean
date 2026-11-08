import Foundation

@MainActor enum PlacementConfidenceTests {
    static func run()->Int {
        var checks=0,time=0.0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        func edgeView(_ point:Int, dx:Double, dy:Double, quality:Double=0.94) -> BoardObservation {
            let row=point/9, col=point%9
            let shape=StoneFootprint(row:row,col:col,center:.init(x:Double(col)+dx,y:Double(row)+dy),
                                     radiusCol:0.48,radiusRow:0.49,quality:quality)
            return BoardObservation(readings:(0..<81).map {
                .init(row:$0/9,col:$0%9,occupancy:$0==point ? .white : .empty,confidence:1,delta:0)
            },size:9,footprints:[shape])
        }
        let outward=edgeView(5,dx:-0.04,dy:-0.40)
        check(outward.ambiguousPlacements.isEmpty && outward.placementOffsets[5]==0.4,
              "Margin displacement is unambiguous but must still use ordinary timing")
        check(edgeView(5,dx:0,dy:0.4).ambiguousPlacements==[5],"Inward displacement lost its warning")
        check(edgeView(5,dx:0.31,dy:-0.24).ambiguousPlacements==[5],"Along-edge ambiguity lost its warning")
        check(edgeView(0,dx:-0.38,dy:-0.38).ambiguousPlacements==[0],"Uncovered corner assigned a stone")
        check(edgeView(5,dx:0,dy:-0.4,quality:0.87).ambiguousPlacements==[5],"Weak edge fit erased a warning")
        var crowded=edgeView(40,dx:0.04,dy:-0.36)
        let neighbor=31
        var confirmed=Array(repeating:Occupancy.empty,count:81)
        confirmed[neighbor] = .white
        var marks=crowded.readings
        marks[neighbor] = .init(row:3,col:4,occupancy:.white,confidence:1,delta:0)
        crowded=BoardObservation(readings:marks,size:9,footprints:crowded.footprints)
        check(crowded.assignmentOffsets(confirmedBoard:confirmed)[40]!>=0.3,"Recorded neighbor without an outline cleared ambiguity")
        crowded.footprints.append(.init(row:3,col:4,center:.init(x:4,y:2.70),radiusCol:0.46,radiusRow:0.46,quality:0.90))
        check(crowded.assignmentOffsets(confirmedBoard:confirmed)[40]!<0.24,"Separate established neighbor did not resolve a displaced stone")
        confirmed[neighbor] = .empty
        check(crowded.assignmentOffsets(confirmedBoard:confirmed)[40]!>=0.3,"Unconfirmed neighbor erased assignment ambiguity")
        let recorder=GameRecorder(storage:nil)
        var colors=[Occupancy](repeating:.empty,count:81),offsets=[Int:Double]()
        func view()->BoardObservation {
            BoardObservation(readings:colors.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,
                footprints:offsets.map{point,offset in .init(row:point/9,col:point%9,center:.init(x:Double(point%9),y:Double(point/9)+offset),radiusCol:0.46,radiusRow:0.46,quality:0.99)})
        }
        func feed(_ count:Int) {for _ in 0..<count {time += 0.21;recorder.consume(view(),now:time)}}
        recorder.start(size:9);feed(5)
        colors[10] = .black;offsets[10]=0.36;feed(15)
        check(recorder.moveCount==0 && recorder.pendingMoveCount==1,"Repeated off-center sightings incorrectly confirmed a move")
        check(recorder.pendingConfidence.first?.placementUncertain==true && recorder.pendingConfidence.first?.level=="low","Physical ambiguity is missing from confidence")
        colors[20] = .white;offsets[20]=0.10;feed(8)
        colors[30] = .black;offsets[30]=0.32;feed(300)
        check(recorder.pendingMoveCount==3 && recorder.moveCount==0,"Placement uncertainty blocked later chronology or expired")
        check(recorder.pendingConfidence.map(\.level)==["low","high","low"],"Repeated sightings erased physical uncertainty or penalized the clear move")
        offsets[10]=0.28;feed(12)
        check(recorder.moveCount==0,"Threshold jitter erased the placement concern")
        offsets.removeValue(forKey:10);feed(10)
        check(recorder.moveCount==0,"Missing geometry was treated as a centered stone")
        offsets[10]=0.12;feed(4)
        check(recorder.moveCount==0,"A single adjusted view bypassed confirmation")
        feed(1)
        check(recorder.moveCount==2 && recorder.pendingMoveCount==1,"Tidying the first stone did not save the clear prefix")
        check(recorder.pendingConfidence.first?.point==30 && recorder.pendingConfidence.first?.placementUncertain==true,"Rebasing lost the remaining placement warning")
        recorder.pause()
        recorder.suspendVision("Grid alignment lost",preserveObservations:true)
        check(recorder.pendingMoveCount==1,"Alignment checks erased paused pending history")
        recorder.suspendVision("Finding the grid",preserveOrder:true)
        check(recorder.pendingMoveCount==1,"Full grid search erased paused pending history")
        recorder.resume();offsets[30]=0.10;feed(8)
        check(recorder.moveCount==3 && recorder.pendingMoveCount==0,"Pause/resume could not settle an adjusted stone")
        offsets[10]=0.40;colors[40] = .white;offsets[40]=0.10;feed(5)
        check(recorder.moveCount==4 && recorder.game.moves.first?.1?.1==1,"Nudging a confirmed stone reopened its accepted assignment")
        check(view().ambiguousPlacements==[10],"Geometric warnings lost the physical displacement")
        let branched=GameRecorder(storage:nil)
        var branchColors=[Occupancy](repeating:.empty,count:81)
        func branch(_ count:Int) {for _ in 0..<count {time += 0.21
            let footprint=StoneFootprint(row:1,col:1,center:.init(x:1,y:1.36),radiusCol:0.46,radiusRow:0.46,quality:0.99)
            branched.consume(BoardObservation(readings:branchColors.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:branchColors[10] == .black ? [footprint] : []),now:time)
        }}
        branched.start(size:9);branch(5);branchColors[10] = .black;branch(3)
        branchColors[20] = .white;branch(5)
        branchColors[30] = .black;branch(1);branchColors[30] = .uncertain
        branchColors[40] = .black;branch(3);branchColors[50] = .white;branch(5)
        check(branched.pendingConfidence.compactMap(\.point)==[10,20,40,50],"One-frame extra stone displaced the true later sequence behind an ambiguous placement")
        print("PASS: \(checks) placement-confidence checks: persistent spatial ambiguity, later moves, hysteresis, missing outlines, tidying, pause/resume, and confirmed identity.")
        return checks
    }
}
