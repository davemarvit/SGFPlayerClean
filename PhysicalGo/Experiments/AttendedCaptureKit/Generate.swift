import Foundation

/// Artifact-only generator. Uses the real SGFPlayer rules engine; never opens
/// app support, preferences, camera, laser, audio, or an existing game folder.
@main struct GenerateCaptureKit {
    static func main() throws {
        guard CommandLine.arguments.count==2 else {
            throw NSError(domain:"CaptureKit",code:1,userInfo:[NSLocalizedDescriptionKey:"Usage: GenerateCaptureKit NEW_ARTIFACT_DIRECTORY"])
        }
        let fm=FileManager.default
        let destination=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
        guard !destination.pathComponents.contains("Library") else {
            throw NSError(domain:"CaptureKit",code:3,userInfo:[NSLocalizedDescriptionKey:"Artifact output cannot be inside Library/app-support storage."])
        }
        guard !fm.fileExists(atPath:destination.path) else {
            throw NSError(domain:"CaptureKit",code:2,userInfo:[NSLocalizedDescriptionKey:"Refusing existing destination; choose a new artifact directory."])
        }
        let specs:[(String,[String],String,[String])]=[
            ("single-white-prisoner",["A18","A19","T1","C19"],"B19",["A19"]),
            ("two-white-prisoners",["B19","A19","B18","A18"],"A17",["A19","A18"])
        ]
        var manifests:[[String:Any]]=[]
        var outputs:[(String,Data)]=[]
        func point(_ name:String)->Int {
            let columns=Array("ABCDEFGHJKLMNOPQRST"),characters=Array(name)
            guard let col=columns.firstIndex(of:characters[0]),let number=Int(String(characters.dropFirst())),(1...19).contains(number) else {preconditionFailure("Bad fixture coordinate")}
            return (19-number)*19+col
        }
        func name(_ p:Int)->String {"\(Array("ABCDEFGHJKLMNOPQRST")[p%19])\(19-p/19)"}
        func cells(_ player:SGFPlayer)->[String] {player.board.grid.flatMap {$0}.map {$0?.rawValue ?? "empty"}}
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])}
        var checks=0
        func check(_ value:Bool,_ detail:String) {precondition(value,detail);checks+=1}
        for (label,opening,next,prisoners) in specs {
            let player=SGFPlayer();var game=SGFGame();game.boardSize=19;player.load(game:game)
            let moves=opening.map(point)
            for (index,p) in moves.enumerated() {
                check(player.turn==(index%2==0 ? Stone.black:.white),"Alternation")
                check(player.tryPlayMove(color:player.turn,x:p%19,y:p/19)==nil,"Fixture history must be legal")
            }
            let before=cells(player),capturePoint=point(next),expected=prisoners.map(point).sorted()
            check(player.currentIndex==4 && player.turn == .black,"Human Black to move after four accepted fixture moves")
            check(before.filter {$0=="black"}.count==2 && before.filter {$0=="white"}.count==2,"Four stone pre-capture board")
            check(before[capturePoint]=="empty","Capturing intersection starts empty")
            check(player.tryPlayMove(color:.black,x:capturePoint%19,y:capturePoint/19)==nil,"Requested capture legal")
            let after=cells(player),removed=before.indices.filter {before[$0] != "empty" && after[$0]=="empty"}
            check(removed==expected,"Exact prisoner set")
            check(expected.allSatisfy {before[$0]=="white"},"Captured color")
            check(after[capturePoint]=="black" && player.turn == .white,"Black capture yields White turn")
            check(player.whiteStonesCaptured==expected.count && player.blackStonesCaptured==0,"Actual engine capture counters")
            var physicalAfter=before;physicalAfter[capturePoint]="black"
            for p in expected.reversed() {physicalAfter[p]="empty"}
            check(physicalAfter==after,"Out-of-order physical removal reaches exact legal board")
            // Explicitly synthetic zero elapsed balances, with no running anchor.
            let timing=try JSONSerialization.jsonObject(with:JSONEncoder().encode(PhysicalAITiming()))
            let session=UUID().uuidString
            let snapshot:[String:Any]=[
                "id":session,
                "settings":["size":19,"humanBlack":true,"komi":6.5,"rules":"Japanese","strength":"quick","humanRank":NSNull(),"fastTestMode":true],
                "moves":moves.map {["point":$0]},
                "pendingPlacement":false,"pendingCaptureCleanup":false,"ended":false,"timing":timing
            ]
            // No decisionReceivedAtUnix, captureIndication or verifiedPosition:
            // the real attended fifth move must create its own evidence/time.
            outputs.append((label+"/current.json",try json(snapshot)))
            let root=SGFNode(props:["GM":["1"],"FF":["4"],"SZ":["19"],"RU":["Japanese"],"KM":["6.5"],"PB":["Synthetic fixture: Human"],"PW":["Synthetic fixture: AI"],"C":["OFFLINE TEST FIXTURE. Four synthetic legal moves; no observed timestamps or real game history. Reference export only; Physical AI has no SGF-import UI."]])
            let nodes=[root]+moves.enumerated().map {index,p in SGFNode(props:[index%2==0 ? "B":"W":[SGFCoordinates.toSGF(x:p%19,y:p/19)]])}
            outputs.append((label+"/reference.sgf",Data(SGFWriter.serialize(SGFTree(branches:[.init(sequence:nodes)])).utf8)))
            var physical=before;physical[capturePoint]="black"
            let matrix=expected.map {p->[String:Any] in
                var partial=physical;partial[p]="empty"
                return ["firstRemoved":name(p),"remaining":expected.filter {$0 != p}.map(name),"physicalCells":partial]
            }
            manifests.append([
                "fixture":label,"session":session,"synthetic":true,"state":"before_capture_four_moves",
                "size":19,"humanBlack":true,"opening":opening,"nextHumanMove":next,
                "prisonerColor":"white","expectedPrisoners":expected.map(name),"expectedPrisonerIndices":expected,
                "clockPolicy":expected.count>=2 ? "Hold elapsed clocks until all prisoners removed":"Next player's elapsed clock continues during cleanup",
                "beforeCells":before,"afterLegalCaptureCells":after,"physicalAfterPlacementBeforeRemoval":physical,
                "singleRemovalCases":matrix,"snapshot":"\(label)/current.json","sgfReference":"\(label)/reference.sgf"
            ])
        }
        let manifest:[String:Any]=[
            "schemaVersion":1,"artifactOnly":true,"physicallyValidated":false,
            "coordinateConvention":"Canonical camera grid: A19 is row0,col0; T1 is row18,col18; I is skipped. Verify display/camera orientation before use.",
            "historyProvenance":"Synthetic legal fixture. No real move timestamps, clock history or camera evidence are asserted.",
            "generationDate":ISO8601DateFormatter().string(from:Date()),"legalEngine":"SGFPlayerEngine.swift, unchanged repository source",
            "legalChecks":checks,"fixtures":manifests
        ]
        outputs.append(("manifest.json",try json(manifest)))
        // Validate everything before first write, and create only a new folder.
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        for (relative,data) in outputs {
            let url=destination.appendingPathComponent(relative)
            try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url,options:.atomic)
        }
        print("PASS \(checks) real-engine legal checks; wrote \(outputs.count) artifact files to \(destination.path)")
    }
}
