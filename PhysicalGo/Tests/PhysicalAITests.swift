import Foundation
import AppKit
import SwiftUI

@main struct PhysicalAITests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("physical-ai-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ value: Bool,_ message: String) {precondition(value,message);checks+=1}
        func observation(_ cells: [String],stamp: Double,hand: Bool? = false)->BoardObservation {
            var o=BoardObservation(readings:cells.enumerated().map {i,c in IntersectionReading(row:i/9,col:i%9,occupancy:Occupancy(rawValue:c)!,confidence:1,delta:0)},size:9)
            o.capturedAt=stamp;o.handObstructed=hand;return o
        }
        var time=100.0
        func feed(_ ai: PhysicalAI,_ cells: [String]) {
            for _ in 0..<4 {time+=0.2;ai.consume(observation(cells,stamp:time),now:time)}
        }
        func settle() async throws {try await Task.sleep(nanoseconds:60_000_000)}
        let empty=Array(repeating:"empty",count:81)
        let legacySettings=try JSONDecoder().decode(PhysicalAISettings.self,from:JSONEncoder().encode(PhysicalAISettings()))
        check(legacySettings.fastTestMode != true,"legacy settings default to normal play")
        let modeFolder=root.appendingPathComponent("test-mode")
        var requestedTestMode=false
        let modeAI=PhysicalAI(directory:modeFolder,generate:{_,settings in requestedTestMode=settings.fastTestMode == true;return "D4"})
        modeAI.draft.size=9;modeAI.draft.humanBlack=false
        modeAI.setFastTestMode(true)
        check(modeAI.start() && modeAI.fastTestMode,"test mode starts a real AI game")
        modeAI.setFastTestMode(false)
        check(modeAI.fastTestMode,"active game prevents changing engine mid-turn")
        feed(modeAI,empty);try await settle()
        check(requestedTestMode && modeAI.phase == .placing && modeAI.snapshot?.moves.count==1,"test mode retains physical placement lifecycle")
        modeAI.pause()
        let modeMoves=modeAI.snapshot!.moves.map(\.point),modeClock=modeAI.snapshot!.timing
        modeAI.setFastTestMode(false)
        check(modeAI.phase == .paused && modeAI.snapshot!.moves.map(\.point)==modeMoves,"changing test mode preserves paused history")
        check(modeAI.snapshot!.timing==modeClock,"changing test mode preserves clocks")
        check(modeAI.snapshot!.settings.humanRank=="5k","test mode preserves selected opponent profile")
        modeAI.setFastTestMode(true)
        let modeRestored=PhysicalAI(directory:modeFolder)
        check(modeRestored.fastTestMode && modeRestored.phase == .paused,"test mode persists with paused game")
        // On resume, a fully observed single legal move can establish the saved
        // position and the new move together, without lifting/replacing it.
        let resumeDir=root.appendingPathComponent("resume-new-move")
        try FileManager.default.createDirectory(at:resumeDir,withIntermediateDirectories:true)
        var resumeConfig=PhysicalAISettings();resumeConfig.size=9
        let resumeSnapshot=PhysicalAI.Snapshot(id:UUID(),settings:resumeConfig,moves:[0,48].map{.init(point:$0)})
        try JSONEncoder().encode(resumeSnapshot).write(to:resumeDir.appendingPathComponent("current.json"))
        let resuming=PhysicalAI(directory:resumeDir,generate:{_,_ in "pass"},uptime:{time})
        resuming.resume()
        var resumedMove=resuming.cells;resumedMove[1]="black"
        var invalidResume=resumedMove;invalidResume[48]="empty"
        feed(resuming,invalidResume);check(resuming.snapshot?.moves.count==2,"resume accepted unrelated missing stone")
        feed(resuming,resumedMove);check(resuming.snapshot?.moves.count==3 && resuming.snapshot?.moves.last?.point==1,"resume missed fully observed legal move")
        resuming.pause()
        // AI placement and the player's reply can arrive in the same frame.
        let quickDir=root.appendingPathComponent("quick-reply")
        try FileManager.default.createDirectory(at:quickDir,withIntermediateDirectories:true)
        var quickSnapshot=PhysicalAI.Snapshot(id:UUID(),settings:resumeConfig,moves:[.init(point:0),.init(point:48,decisionReceivedAtUnix:12345)])
        quickSnapshot.pendingPlacement=true
        try JSONEncoder().encode(quickSnapshot).write(to:quickDir.appendingPathComponent("current.json"))
        let quick=PhysicalAI(directory:quickDir,generate:{_,_ in "pass"},uptime:{time})
        quick.resume();var quickPosition=quick.cells;quickPosition[1]="black"
        var missingAI=quickPosition;missingAI[48]="empty";feed(quick,missingAI)
        check(quick.snapshot?.moves.count==2 && quick.snapshot?.pendingPlacement==true,"reply accepted without AI stone")
        var doubleReply=quickPosition;doubleReply[2]="black";feed(quick,doubleReply)
        check(quick.snapshot?.moves.count==2,"two quick replies accepted")
        feed(quick,quickPosition)
        check(quick.snapshot?.moves.count==3 && quick.snapshot?.moves.last?.point==1 && quick.snapshot?.pendingPlacement==false,"combined placement and human reply not accepted")
        check(quick.snapshot?.moves[1].decisionReceivedAtUnix==12345,"quick reply changed AI decision receipt")
        quick.pause()
        // An edge stone may clear the normal placement threshold without
        // reaching 0.9. A prompt human reply must not raise that threshold.
        for confidence in [0.8,0.8620689655172413] {
            let folder=root.appendingPathComponent("edge-quick-reply-\(confidence)")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try JSONEncoder().encode(quickSnapshot).write(to:folder.appendingPathComponent("current.json"))
            let edge=PhysicalAI(directory:folder,generate:{_,_ in "pass"},uptime:{time})
            edge.resume()
            func edgeFrame(_ confidence:Double,_ color:Occupancy = .white) {
                time+=0.2;var frame=observation(quickPosition,stamp:time)
                frame.readings[48] = .init(row:5,col:3,occupancy:color,confidence:confidence,delta:0)
                edge.consume(frame,now:time)
            }
            for _ in 0..<4 {edgeFrame(0.79)}
            check(edge.snapshot?.moves.count==2,"weak AI placement admitted prompt reply")
            for _ in 0..<4 {edgeFrame(confidence,.black)}
            check(edge.snapshot?.moves.count==2,"wrong-color AI placement admitted prompt reply")
            edgeFrame(confidence)
            check(edge.snapshot?.moves.count==2,"single frame admitted prompt reply")
            for _ in 0..<3 {edgeFrame(confidence)}
            check(edge.snapshot?.moves.count==3 && edge.snapshot?.moves.last?.point==1 && edge.snapshot?.pendingPlacement==false,"normal-confidence edge placement blocked prompt reply")
            check(edge.snapshot?.moves[1].decisionReceivedAtUnix==12345,"edge reply changed decision receipt")
            edge.pause()
        }
        // Physical first-line T15 then T17 in the user's rotated 19x19 view.
        // No frame ever contains just the newly placed AI stone.
        let t17Dir=root.appendingPathComponent("t15-t17")
        try FileManager.default.createDirectory(at:t17Dir,withIntermediateDirectories:true)
        var t17Settings=PhysicalAISettings();t17Settings.humanBlack=false
        var t17Snapshot=PhysicalAI.Snapshot(id:UUID(),settings:t17Settings)
        t17Snapshot.moves=[.init(point:4,decisionReceivedAtUnix:12345)]
        t17Snapshot.pendingPlacement=true
        try JSONEncoder().encode(t17Snapshot).write(to:t17Dir.appendingPathComponent("current.json"))
        let t17=PhysicalAI(directory:t17Dir,generate:{_,_ in "pass"},uptime:{time})
        t17.resume()
        var both=Array(repeating:"empty",count:361);both[4]="black";both[2]="white"
        for _ in 0..<4 {
            time+=0.2
            var frame=BoardObservation(readings:both.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19)
            frame.handObstructed=false;frame.capturedAt=time;t17.consume(frame,now:time)
        }
        check(t17.snapshot?.moves.count==2 && t17.snapshot?.moves.last?.point==2,"T15/T17 first-line quick reply blocked")
        check(t17.snapshot?.moves.first?.decisionReceivedAtUnix==12345,"T15/T17 altered receipt time")
        t17.pause()
        // Resume keeps prior camera verification only for unchanged cells in
        // the same context. It cannot invent a new stone or capture removal.
        for scenario in ["same","camera_changed","contradiction","pending_ai","capture_uncertain"] {
            let folder=root.appendingPathComponent("verified-"+scenario)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var saved=PhysicalAI.Snapshot(id:UUID(),settings:t17Settings)
            saved.moves=[.init(point:4),.init(point:2),.init(point:149,decisionReceivedAtUnix:12345)]
            var physical=Array(repeating:"empty",count:361);physical[4]="black";physical[2]="white";physical[149]="black"
            var prior=physical
            if scenario=="pending_ai" {saved.pendingPlacement=true;prior[149]="empty"}
            if scenario=="capture_uncertain" {prior[277]="black"}
            saved.verifiedPosition = .init(cells:prior,cameraContext:"verified-camera")
            try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
            let restored=PhysicalAI(directory:folder,generate:{_,_ in "pass"},uptime:{time})
            restored.laser.observeCamera(hand:false,valid:true,capturedAt:time,now:time,
                context:scenario=="camera_changed" ? "different-camera":"verified-camera")
            restored.resume()
            for _ in 0..<4 {
                time+=0.2
                var frame=BoardObservation(readings:physical.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19)
                let index=scenario=="capture_uncertain" ? 277:149
                frame.readings[index] = .init(row:index/19,col:index%19,occupancy:scenario=="contradiction" ? .empty:.uncertain,confidence:scenario=="contradiction" ? 1:0.6,delta:0)
                frame.handObstructed=false;frame.capturedAt=time;restored.consume(frame,now:time)
            }
            check((restored.phase == .human)==(scenario=="same"),"Verified resume guard failed: \(scenario)")
            check(restored.snapshot?.moves.count==3,"Resume invented a move")
            restored.pause()
            let disk=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:folder.appendingPathComponent("current.json")))
            if scenario=="same" {check(disk.verifiedPosition?.cells==physical,"Pause lost previously verified physical cells")}
            if scenario=="camera_changed" {check(disk.verifiedPosition==nil,"Changed camera persisted obsolete verification")}
        }
        // A positively seen new stone must not disappear into an old verified
        // empty label while its intersection is unresolved. Once a strong
        // outline uniquely favors S4, ordinary temporal confirmation accepts it.
        let s4Dir=root.appendingPathComponent("s4-new-stone")
        try FileManager.default.createDirectory(at:s4Dir,withIntermediateDirectories:true)
        var s4Save=PhysicalAI.Snapshot(id:UUID(),settings:t17Settings)
        s4Save.moves=[.init(point:4),.init(point:2),.init(point:149,decisionReceivedAtUnix:12345)]
        var s4Board=Array(repeating:"empty",count:361);s4Board[4]="black";s4Board[2]="white";s4Board[149]="black"
        s4Save.verifiedPosition = .init(cells:s4Board,cameraContext:"s4-camera")
        try JSONEncoder().encode(s4Save).write(to:s4Dir.appendingPathComponent("current.json"))
        let s4Laser=PhysicalLaserGuidance(directory:s4Dir.appendingPathComponent("bridge"),automatic:false,uptime:{time})
        let s4AI=PhysicalAI(directory:s4Dir,generate:{_,_ in "pass"},laser:s4Laser,uptime:{time})
        s4AI.centeringEnabled=true;s4Laser.setEnabled(true)
        s4AI.laser.observeCamera(hand:false,valid:true,capturedAt:time,now:time,context:"s4-camera")
        s4AI.resume();s4Board[34]="white"
        func s4Frame(_ centerY:Double) {
            time+=0.2
            s4Laser.observeCamera(hand:false,valid:true,capturedAt:time,now:time,context:"s4-camera")
            var frame=BoardObservation(readings:s4Board.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19,
                footprints:[.init(row:1,col:15,center:.init(x:14.88,y:centerY),radiusCol:0.46,radiusRow:0.4876,quality:0.95675)])
            frame.capturedAt=time;frame.handObstructed=false;s4AI.consume(frame,now:time)
        }
        for _ in 0..<5 {s4Frame(0.50)}
        check(s4AI.snapshot?.moves.count==3 && s4AI.phase == .checking,"Unresolved new stone falsely confirmed an unchanged board")
        check(s4AI.status.contains("new stone") && s4AI.status.contains("unclear"),"Unresolved new stone was silently hidden")
        check(s4AI.centeringStone==ImagePoint(x:14.88,y:0.50) && s4Laser.target?.purpose=="centering",
              "Unresolved new stone reset the centering hint before it could start")
        s4Board[34]="empty"
        for _ in 0..<4 {s4Frame(0.50)}
        check(s4AI.phase == .human && s4AI.centeringStone==nil,"Removed candidate retained an obsolete hint")
        s4Board[34]="white"
        for _ in 0..<4 {s4Frame(0.50)}
        check(s4AI.status.contains("unclear"),"Ambiguity during a normal human turn was hidden")
        s4Board[34]="empty"
        for _ in 0..<4 {s4Frame(0.50)}
        check(s4AI.status.hasPrefix("Your turn"),"Resolved ambiguity left stale status text")
        s4Board[34]="white"
        s4Frame(0.56)
        check(s4AI.snapshot?.moves.count==3,"One S4 outline bypassed temporal confirmation")
        for _ in 0..<3 {s4Frame(0.56)}
        check(s4AI.snapshot?.moves.count==4 && s4AI.snapshot?.moves.last?.point==34,"Strong off-center S4 was not accepted")
        check(s4AI.centeringStone==nil,"Clearly assignable S4 retained a centering hint")
        check(s4AI.snapshot?.moves[2].decisionReceivedAtUnix==12345,"S4 acceptance changed prior decision time")
        s4AI.pause()
        let hintDir=root.appendingPathComponent("centering-selection")
        try FileManager.default.createDirectory(at:hintDir,withIntermediateDirectories:true)
        var hintSave=PhysicalAI.Snapshot(id:UUID(),settings:t17Settings)
        hintSave.moves=[.init(point:4),.init(point:2),.init(point:149,decisionReceivedAtUnix:12345)]
        var hintBoard=Array(repeating:"empty",count:361);hintBoard[4]="black";hintBoard[2]="white";hintBoard[149]="black"
        hintSave.verifiedPosition = .init(cells:hintBoard,cameraContext:"hint-camera")
        try JSONEncoder().encode(hintSave).write(to:hintDir.appendingPathComponent("current.json"))
        let hintLaser=PhysicalLaserGuidance(directory:hintDir.appendingPathComponent("bridge"),automatic:false,uptime:{time})
        let hintAI=PhysicalAI(directory:hintDir,generate:{_,_ in "pass"},laser:hintLaser,uptime:{time})
        hintLaser.setEnabled(true);hintAI.resume()
        func hintFrame(_ offset:Double,hand:Bool=false) {
            time+=0.2;hintLaser.observeCamera(hand:hand,valid:true,capturedAt:time,now:time,context:"hint-camera")
            var frame=BoardObservation(readings:hintBoard.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19,
                footprints:[.init(row:7,col:16,center:.init(x:16+offset,y:7),radiusCol:0.5,radiusRow:0.5,quality:0.92)])
            frame.capturedAt=time;frame.handObstructed=hand;hintAI.consume(frame,now:time)
        }
        for _ in 0..<4 {hintFrame(0.34)}
        check(hintAI.centeringStone==nil,"centering default was not off")
        hintAI.centeringEnabled=true;hintFrame(0.34)
        check(hintAI.centeringStone==nil,"single ambiguous frame started a hint")
        for _ in 0..<3 {hintFrame(0.34)}
        check(abs((hintAI.centeringStone?.x ?? 0)-16.34)<0.001 && hintLaser.target?.purpose=="centering","stable off-center stone failed to request hint")
        // A 0.16-cell movement exceeded witness tolerance but previously kept
        // the old aim forever because target replacement required 0.18 cells.
        hintFrame(0.50)
        check(hintAI.centeringStone==nil && hintLaser.target==nil,"moved disk retained the old aim while replacement evidence accumulated")
        for _ in 0..<2 {hintFrame(0.50)}
        check(hintLaser.target==nil,"moved disk resumed before 450 ms of fresh evidence")
        hintFrame(0.50)
        check(hintLaser.target?.stoneCenter==ImagePoint(x:16.50,y:7),"stable moved disk did not acquire its measured replacement center")
        hintAI.centeringEnabled=false
        check(hintAI.centeringStone==nil && hintLaser.target==nil,"toggle did not immediately cancel hint")
        hintAI.centeringEnabled=true
        for _ in 0..<4 {hintFrame(0.34)}
        hintFrame(0.34,hand:true)
        check(hintLaser.suppressed,"hand entry did not suppress selected hint")
        for _ in 0..<4 {hintFrame(0)}
        check(hintAI.centeringStone==nil && hintLaser.target==nil,"centered stone kept its hint")
        check(hintAI.snapshot?.moves.count==3,"centering changed game history")
        // A new disk halfway between two empty intersections has NO assigned
        // intersection. Guidance must retain the measured fractional center.
        func unassignedFrame(_ color:Occupancy) {
            time+=0.2;hintLaser.observeCamera(hand:false,valid:true,capturedAt:time,now:time,context:"hint-camera")
            var frame=BoardObservation(readings:hintBoard.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19)
            for p in [160,161] {frame.readings[p] = .init(row:p/19,col:p%19,occupancy:.uncertain,confidence:0,delta:0)}
            frame.centeringEvidence=[.init(color:color,shape:.init(row:8,col:8,center:.init(x:8.5,y:8),radiusCol:0.5,radiusRow:0.5,quality:0.98))]
            frame.capturedAt=time;frame.handObstructed=false;hintAI.consume(frame,now:time)
        }
        for _ in 0..<4 {unassignedFrame(.white)}
        check(hintAI.centeringStone==ImagePoint(x:8.5,y:8),"Unassigned stone lost its measured center")
        check(hintLaser.target?.stoneCenter==ImagePoint(x:8.5,y:8),"Hint snapped to an intersection")
        check(hintAI.snapshot?.moves.count==3,"Unassigned stone was silently entered as a move")
        unassignedFrame(.black)
        check(hintAI.centeringStone==nil && hintLaser.target==nil,"different-color disk inherited an old centering target")
        for _ in 0..<2 {unassignedFrame(.black)}
        check(hintLaser.target==nil,"different-color disk reused previous color's stable witness")
        unassignedFrame(.black)
        check(hintLaser.target?.stoneCenter==ImagePoint(x:8.5,y:8) && hintLaser.target?.black==true,"stable replacement disk did not receive its own target identity")
        check(hintAI.snapshot?.moves.count==3,"replacement disk changed accepted history")
        hintAI.pause()
        var requests=0,requestedVisits=0,historyCount=0
        let ai=PhysicalAI(directory:root.appendingPathComponent("main"),generate:{game,settings in
            requests+=1;requestedVisits=settings.strength.visits;historyCount=game.moves.count;return "D4"
        },uptime:{time})
        ai.draft.size=9;ai.draft.strength = .quick
        check(ai.start(),"start")
        check(ai.phase == .checking && ai.snapshot?.moves.count==0,"verify empty first")
        var stray=empty;stray[1]="black"
        feed(ai,stray);check(ai.phase == .checking && requests==0,"nonempty startup blocked")
        feed(ai,empty);check(ai.phase == .human,"human black first")
        var human=empty;human[0]="black"
        feed(ai,human);check(ai.snapshot?.moves.count==1 && ai.phase == .checking,"one human move accepted")
        check(ai.laser.alignmentPreparation==nil,"alignment started before human board confirmation")
        feed(ai,human)
        let preparedTurn=ai.laser.alignmentPreparation
        check(preparedTurn?.session==ai.snapshot?.id && preparedTurn?.moveNumber==2,"thinking did not request alignment for upcoming AI move")
        try await settle()
        check(requests==1 && requestedVisits==8 && historyCount==1,"real history and chosen visits sent")
        check(ai.phase == .placing && ai.pendingPoint==48,"AI move pending placement")
        check(ai.laser.alignmentPreparation==preparedTurn,"AI reply discarded prepared alignment identity")
        check(ai.referenceCells==human && ai.cells[48]=="white","pending AI move changed physical reference labels")
        check(ai.guidanceTarget?.row==5 && ai.guidanceTarget?.col==3 && ai.guidanceTarget?.black==false,"canonical pointer target")
        var wrong=human;wrong[49]="white";feed(ai,wrong)
        check(ai.phase == .placing && ai.snapshot?.moves.count==2,"wrong AI stone does not advance")
        check(ai.mismatch?.remove==[49] && ai.mismatch?.place==[48],"correction guidance")
        ai.pause();check(ai.guidanceTarget==nil && ai.phase == .paused,"pause clears active pointer target")
        check(ai.laser.alignmentPreparation==nil,"pause retained alignment preparation")
        let restored=PhysicalAI(directory:root.appendingPathComponent("main"),generate:{_,_ in "pass"})
        check(restored.phase == .paused && restored.pendingPoint==48,"pending AI placement survives restart")
        check(restored.referenceCells==human,"restart lost pre-placement reference position")
        restored.resume();check(restored.phase == .placing,"resume retains placement requirement")
        check(restored.laser.alignmentPreparation==nil,"restart invented a previously checked thinking position")
        var matched=human;matched[48]="white"
        feed(restored,matched);check(restored.phase == .human && restored.pendingPoint==nil,"placed stone confirmed")
        check(restored.referenceCells==matched,"confirmed placement did not advance reference labels")
        check(restored.guidanceTarget==nil,"target clears after placement")
        restored.pass(now:time+2);check(restored.snapshot?.moves.count==2,"stale board cannot pass")
        feed(restored,matched);restored.pass(now:time)
        check(restored.snapshot?.moves.count==3 && restored.snapshot?.moves.last?.point==nil,"human pass")
        feed(restored,matched);try await settle()
        check(restored.phase == .finished && restored.snapshot?.moves.count==4,"two passes end game")
        let sgf=PhysicalAI.sgf(restored.snapshot!)
        let roundTrip=SGFGame.from(tree:try SGFParser.parse(text:sgf))
        check(roundTrip.moves.count==4 && roundTrip.boardSize==9 && roundTrip.info.result==nil,"SGF round trip, no invented result")
        check(FileManager.default.fileExists(atPath:restored.savedURL!.path),"automatic SGF save")
        // White starts only after a verified empty board. Late task completions
        // cannot add a move to a paused game, even if a generator ignores cancel.
        let white=PhysicalAI(directory:root.appendingPathComponent("white"),generate:{_,_ in
            try? await Task.sleep(nanoseconds:100_000_000);return "E5"
        })
        white.draft.size=9;white.draft.humanBlack=false
        check(white.start(),"white game starts");feed(white,empty)
        check(white.phase == .thinking,"AI black starts")
        white.pause();try await Task.sleep(nanoseconds:150_000_000)
        check(white.snapshot?.moves.isEmpty==true && white.phase == .paused,"late AI result discarded")
        white.resume();feed(white,empty);try await Task.sleep(nanoseconds:150_000_000)
        check(white.phase == .placing && white.pendingPoint==40,"resume restarts cancelled search")
        white.finish(resign:true);check(white.snapshot?.result=="B+R" && white.guidanceTarget==nil,"resign and clear target")
        // Hand/unknown/stale frames and repeated timestamps are not witnesses.
        let guarded=PhysicalAI(directory:root.appendingPathComponent("guarded"),generate:{_,_ in "pass"})
        guarded.draft.size=9;check(guarded.start(),"guarded start")
        for _ in 0..<6 {guarded.consume(observation(empty,stamp:10),now:10)}
        check(guarded.phase == .checking,"duplicates cannot establish match")
        for t in [11.0,11.2,11.6] {guarded.consume(observation(empty,stamp:t,hand:nil),now:t)}
        check(guarded.phase == .checking,"unknown hands blocked")
        for t in [12.0,12.2,12.6] {guarded.consume(observation(empty,stamp:t),now:t+3)}
        check(guarded.phase == .checking,"stale frames blocked")
        feed(guarded,empty)
        guarded.consume(observation(human,stamp:time+0.2),now:time+0.2)
        guarded.interruptObservation();time+=0.2
        guarded.consume(observation(human,stamp:time+0.2),now:time+0.2);time+=0.2
        check(guarded.snapshot?.moves.isEmpty==true,"hand interruption resets evidence")
        // Captures are legal history first, but thinking waits for removal.
        let captureDir=root.appendingPathComponent("capture")
        try FileManager.default.createDirectory(at:captureDir,withIntermediateDirectories:true)
        var config=PhysicalAISettings();config.size=9
        let capture=PhysicalAI.Snapshot(id:UUID(),settings:config,moves:[9,0,80,2].map{.init(point:$0)})
        try JSONEncoder().encode(capture).write(to:captureDir.appendingPathComponent("current.json"))
        var captureRequests=0
        let capturing=PhysicalAI(directory:captureDir,generate:{_,_ in captureRequests+=1;return "pass"},uptime:{time})
        capturing.resume();feed(capturing,capturing.cells)
        var beforeRemoval=capturing.cells;beforeRemoval[1]="black"
        feed(capturing,beforeRemoval)
        check(capturing.snapshot?.moves.count==5 && capturing.cells[0]=="empty","capture applied legally")
        check(!capturing.clockPausedForCaptureCleanup && capturing.timing.anchor != nil,"single human capture must keep AI clock running")
        let captureTime=capturing.timing.elapsed(black:false,at:time)
        time+=15
        check(abs(capturing.timing.elapsed(black:false,at:time)-captureTime-15)<0.001,"single human prisoner removal must charge AI clock")
        // Pending AI captures must also preserve the still-physical prisoner
        // and the empty destination in reference labels across a restart.
        let pendingCaptureDir=root.appendingPathComponent("pending-ai-capture")
        try FileManager.default.createDirectory(at:pendingCaptureDir,withIntermediateDirectories:true)
        var pendingCapture=capture
        pendingCapture.moves.append(.init(point:1,decisionReceivedAtUnix:67890))
        pendingCapture.pendingPlacement=true
        try JSONEncoder().encode(pendingCapture).write(to:pendingCaptureDir.appendingPathComponent("current.json"))
        let awaitingCapture=PhysicalAI(directory:pendingCaptureDir,generate:{_,_ in "pass"})
        check(awaitingCapture.cells[0]=="empty" && awaitingCapture.cells[1]=="black","pending capture logical board")
        check(awaitingCapture.referenceCells[0]=="white" && awaitingCapture.referenceCells[1]=="empty","pending capture relabeled physical prisoner or target")
        feed(capturing,beforeRemoval);check(captureRequests==0 && capturing.phase == .checking,"AI waits for prisoners")
        feed(capturing,capturing.cells);try await settle();check(captureRequests==1,"search after capture removal")
        // Exercise the exact boundary with real legal one- and two-stone AI
        // captures, including a save from the earlier all-captures-pause policy.
        for count in [1,2] {
            let folder=root.appendingPathComponent("capture-threshold-\(count)")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var settings=config;settings.humanBlack=false
            let history=count==1 ? [9,0,80,2]:[9,0,10,1]
            var saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:history.map{.init(point:$0)})
            saved.timing=PhysicalAITiming(blackSeconds:10,whiteSeconds:20,blackToPlay:true)
            try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
            let game=PhysicalAI(directory:folder,generate:{_,_ in count==1 ? "B9":"C9"},uptime:{time},wallTime:{54321})
            game.resume();feed(game,game.cells);try await settle()
            check(game.lastCapturePoints.count==count,"capture-count boundary fixture")
            check(game.clockPausedForCaptureCleanup==(count>=2),"AI capture pause threshold")
            check((game.timing.anchor==nil)==(count>=2),"AI clock anchor at threshold")
            let before=game.timing.elapsed(black:false,at:time);time+=10
            check(abs(game.timing.elapsed(black:false,at:time)-before-(count==1 ? 10:0))<0.001,"elapsed time during pending AI capture")
            var physical=game.referenceCells;physical[game.pendingPoint!]="black";feed(game,physical)
            check(game.snapshot?.pendingPlacement==true && game.clockPausedForCaptureCleanup==(count>=2),"placement without removal preserves threshold policy")
            game.pause();var legacy=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:folder.appendingPathComponent("current.json")))
            legacy.pendingCaptureCleanup=true
            try JSONEncoder().encode(legacy).write(to:folder.appendingPathComponent("current.json"))
            let balance=legacy.timing!.whiteSeconds;time+=40
            let resumed=PhysicalAI(directory:folder,generate:{_,_ in "pass"},uptime:{time});resumed.resume()
            check(resumed.snapshot?.pendingCaptureCleanup==(count>=2),"old single-capture flag normalized on resume")
            check((resumed.timing.anchor==nil)==(count>=2) && resumed.timing.whiteSeconds==balance,"resume keeps balances and correct threshold")
            check(resumed.snapshot?.moves.last?.decisionReceivedAtUnix==54321,"threshold change preserves AI receipt")
            feed(resumed,resumed.cells)
            check(resumed.phase == .human && !resumed.captureCleanupPending && resumed.timing.anchor != nil,"complete threshold capture resumes normal turn")
            resumed.pause()
        }
        let twoHumanDir=root.appendingPathComponent("two-human-capture")
        try FileManager.default.createDirectory(at:twoHumanDir,withIntermediateDirectories:true)
        let twoHumanSave=PhysicalAI.Snapshot(id:UUID(),settings:config,moves:[9,0,10,1].map{.init(point:$0)})
        try JSONEncoder().encode(twoHumanSave).write(to:twoHumanDir.appendingPathComponent("current.json"))
        let twoHuman=PhysicalAI(directory:twoHumanDir,generate:{_,_ in "pass"},uptime:{time})
        twoHuman.resume();feed(twoHuman,twoHuman.cells)
        var twoPhysical=twoHuman.cells;twoPhysical[2]="black";feed(twoHuman,twoPhysical)
        check(twoHuman.lastCapturePoints==[0,1] && twoHuman.clockPausedForCaptureCleanup,"two human prisoners must pause AI clock")
        let twoBalance=twoHuman.timing.elapsed(black:false,at:time);time+=10
        twoPhysical[0]="empty";feed(twoHuman,twoPhysical)
        check(twoHuman.clockPausedForCaptureCleanup && twoHuman.timing.elapsed(black:false,at:time)==twoBalance,"partial two-stone removal stays paused")
        feed(twoHuman,twoHuman.cells)
        check(!twoHuman.captureCleanupPending && twoHuman.timing.anchor != nil,"full two-stone human removal releases clock")
        twoHuman.pause()
        // A four-stone AI capture excludes the complete physical update, while
        // keeping the decision receipt, legal history, and laser target intact.
        let fourDir=root.appendingPathComponent("four-capture")
        try FileManager.default.createDirectory(at:fourDir,withIntermediateDirectories:true)
        var fourConfig=PhysicalAISettings();fourConfig.size=9;fourConfig.humanBlack=false
        var fourSave=PhysicalAI.Snapshot(id:UUID(),settings:fourConfig,moves:[9,0,10,1,11,2,12,3].map{.init(point:$0)})
        fourSave.timing=PhysicalAITiming(blackSeconds:10,whiteSeconds:20,blackToPlay:true)
        try JSONEncoder().encode(fourSave).write(to:fourDir.appendingPathComponent("current.json"))
        let four=PhysicalAI(directory:fourDir,generate:{_,_ in "E9"},uptime:{time},wallTime:{98765})
        four.resume();feed(four,four.cells);time+=2;try await settle()
        check(four.pendingPoint==4 && four.lastCapturePoints==[0,1,2,3],"four prisoners not identified from legal transition")
        check(four.snapshot?.moves.last?.decisionReceivedAtUnix==98765 && four.guidanceTarget?.col==4,"capture receipt or guidance lost")
        check(four.timing.blackSeconds>10 && four.timing.blackSeconds<13 && !four.timing.blackToPlay,"AI thinking charged through original receipt")
        check(four.timing.anchor==nil && four.clockPausedForCaptureCleanup,"AI capture did not pause next player's clock at receipt")
        let whiteBefore=four.timing.whiteSeconds
        time+=30
        var prisoners=four.referenceCells;prisoners[4]="black"
        feed(four,prisoners)
        check(four.snapshot?.pendingPlacement==true && four.timing.elapsed(black:false,at:time)==whiteBefore,"placed AI stone with prisoners restarted clock")
        prisoners[0]="empty";prisoners[1]="empty";feed(four,prisoners)
        check(four.clockPausedForCaptureCleanup && four.phase == .placing,"partial cleanup resumed play")
        // Explicit pause/restart must preserve cleanup, even for old saves that
        // have pendingPlacement but no new optional cleanup flag.
        four.pause();time+=100
        let disk=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:fourDir.appendingPathComponent("current.json")))
        check(disk.pendingCaptureCleanup==true && disk.timing?.whiteSeconds==whiteBefore,"cleanup pause not persisted")
        let cleanup=PhysicalAI(directory:fourDir,generate:{_,_ in "pass"},uptime:{time})
        cleanup.resume();check(cleanup.timing.anchor==nil && cleanup.clockPausedForCaptureCleanup,"resume charged pending cleanup")
        let legacyDir=root.appendingPathComponent("legacy-capture");try FileManager.default.createDirectory(at:legacyDir,withIntermediateDirectories:true)
        var legacy=disk;legacy.pendingCaptureCleanup=nil
        try JSONEncoder().encode(legacy).write(to:legacyDir.appendingPathComponent("current.json"))
        let oldCleanup=PhysicalAI(directory:legacyDir,generate:{_,_ in "pass"},uptime:{time})
        oldCleanup.resume();check(oldCleanup.captureCleanupPending && oldCleanup.timing.anchor==nil,"legacy pending capture resumed clock")
        oldCleanup.pause()
        for _ in 0..<4 {time+=0.2;cleanup.consume(observation(cleanup.cells,stamp:time,hand:true),now:time)}
        check(cleanup.clockPausedForCaptureCleanup,"hand-obscured cleanup accepted")
        var unknownPrisoner=cleanup.cells;unknownPrisoner[0]="uncertain";feed(cleanup,unknownPrisoner)
        check(cleanup.clockPausedForCaptureCleanup,"uncertain prisoner removal accepted")
        feed(cleanup,cleanup.cells)
        check(cleanup.phase == .human && !cleanup.captureCleanupPending && cleanup.snapshot?.pendingPlacement==false,"complete cleanup did not release hold")
        check(cleanup.timing.whiteSeconds==whiteBefore && cleanup.timing.anchor != nil,"cleanup duration added to White")
        time+=5
        check(abs(cleanup.timing.elapsed(black:false,at:time)-whiteBefore-5)<0.21,"White clock did not resume after verified cleanup")
        cleanup.pause()
        // Cleanup plus one legal human reply in the same observation must clear
        // the hold without charging the physical-update interval.
        let combinedDir=root.appendingPathComponent("capture-and-reply");try FileManager.default.createDirectory(at:combinedDir,withIntermediateDirectories:true)
        try JSONEncoder().encode(disk).write(to:combinedDir.appendingPathComponent("current.json"))
        let combined=PhysicalAI(directory:combinedDir,generate:{_,_ in "pass"},uptime:{time})
        combined.resume();var replyPosition=combined.cells;replyPosition[40]="white"
        time+=20;feed(combined,replyPosition)
        check(combined.snapshot?.moves.count==10 && !combined.captureCleanupPending && combined.snapshot?.pendingPlacement==false,"cleanup and legal reply failed to clear hold")
        check(combined.timing.whiteSeconds==whiteBefore,"combined reply charged cleanup time")
        combined.pause()
        // Engine failures leave resumable history; invalid moves never enter SGF.
        var shouldFail=true
        let retry=PhysicalAI(directory:root.appendingPathComponent("retry"),generate:{_,_ in
            if shouldFail {throw PhysicalAI.Failure(message:"engine unavailable")};return "I5"
        })
        retry.draft.size=9;retry.draft.humanBlack=false;check(retry.start(),"retry start")
        feed(retry,empty);try await settle();check(retry.phase == .failed && retry.snapshot?.moves.isEmpty==true,"engine failure preserves history")
        shouldFail=false;retry.resume();feed(retry,empty);try await settle()
        check(retry.phase == .failed && retry.snapshot?.moves.isEmpty==true,"invalid coordinate rejected")
        check(PhysicalAI.point("T19",size:19)==18 && PhysicalAI.point("A1",size:9)==72 && PhysicalAI.point("T19",size:9)==nil,"coordinate bounds and skipped I")
        // Failed persistence never accepts a move or silently overwrites bad input.
        let corrupt=root.appendingPathComponent("corrupt");try FileManager.default.createDirectory(at:corrupt,withIntermediateDirectories:true)
        try Data("bad".utf8).write(to:corrupt.appendingPathComponent("current.json"))
        let broken=PhysicalAI(directory:corrupt);check(!broken.start() && broken.error != nil,"failed load protected")
        let blocker=root.appendingPathComponent("file");try Data().write(to:blocker)
        let blocked=PhysicalAI(directory:blocker);check(!blocked.start() && blocked.phase == .failed,"disk failure shown")
        // Render actual setup and play controls, including a pending AI move.
        let output=try TestArtifacts.directory("AIPlay")
        let host=NSHostingView(rootView:PhysicalAIPlayView(ai:ai,orientation:BoardOrientation(0)).padding().frame(width:1000,height:900))
        host.frame=NSRect(x:0,y:0,width:1000,height:900);host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("pending-ai.png"))
        print("PASS: \(checks) AI lifecycle, physical confirmation, capture, persistence, cancellation and coordinate checks; native play render")
        // Exercise the installed local engine rather than only the injected seam.
        var live=SGFGame();live.boardSize=9;live.info.rules="Japanese";live.info.komi="6.5"
        let actual=try await PhysicalAI.kataMove(live,visits:8)
        check(actual.lowercased()=="pass" || PhysicalAI.point(actual,size:9) != nil,"real KataGo move")
        print("PASS: real local KataGo generated \(actual) for a 9×9 game")
        let rankPlayer=SGFPlayer();rankPlayer.load(game:live)
        var distribution=Array(repeating:0.0,count:82);distribution[0]=0.25;distribution[80]=0.75
        check(PhysicalAI.sampledHumanMove(distribution,player:rankPlayer,unit:0.1)=="A9","rank sampling top-left")
        check(PhysicalAI.sampledHumanMove(distribution,player:rankPlayer,unit:0.5)=="J1","rank sampling bottom-right")
        distribution=Array(repeating:0,count:82);distribution[81]=1
        check(PhysicalAI.sampledHumanMove(distribution,player:rankPlayer,unit:0.5)=="pass","rank sampling pass slot")
        distribution[0] = .nan
        check(PhysicalAI.sampledHumanMove(distribution,player:rankPlayer,unit:0.5)==nil,"invalid policy rejected")
        check(PhysicalAISettings.ranks.count==29 && PhysicalAISettings.ranks.first=="20k" && PhysicalAISettings.ranks.last=="9d","full rank range")
        live.boardSize=19
        let fastWorker=PhysicalAI.TestWorker()
        for turn in 0..<2 {
            let began=ProcessInfo.processInfo.systemUptime
            let move=try await fastWorker.move(live)
            let legal=SGFPlayer();legal.load(game:live);legal.seek(to:live.moves.count)
            let point=PhysicalAI.point(move,size:19)
            check(move=="pass" || point != nil,"real test engine coordinate")
            check(legal.tryPlayMove(color:legal.turn,x:point.map{$0%19} ?? -1,y:point.map{$0/19} ?? -1)==nil,"real test engine legal move with history")
            live.moves.append((turn==0 ? .black:.white,point.map{($0%19,$0/19)}))
            print("PASS: real test-mode \(turn==0 ? "cold":"warm") reply \(move) in \(String(format:"%.3f",ProcessInfo.processInfo.systemUptime-began))s")
        }
        check(fastWorker.isRunning,"test engine stays warm between replies")
        fastWorker.stop();check(!fastWorker.isRunning,"test engine releases on stop")
        live.moves=[]
        for rank in ["20k","5k","1d","9d"] {
            let began=ProcessInfo.processInfo.systemUptime
            let humanMove=try await PhysicalAI.kataMove(live,visits:100,rank:rank)
            check(humanMove=="pass" || PhysicalAI.point(humanMove,size:19) != nil,"real human profile")
            print("PASS: real HumanSL rank_\(rank) generated \(humanMove) in \(String(format:"%.3f",ProcessInfo.processInfo.systemUptime-began))s")
        }
        print("PASS: all \(checks) AI checks including real engine and HumanSL profiles")
    }
}
