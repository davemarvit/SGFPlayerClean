import Foundation
import CoreGraphics
import ImageIO

@main struct G18RapidPlayTests {
    struct Photo:Decodable {let image:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double;let hasNewMoves:Bool}
    struct View:Decodable {let time:Double;let position:String}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/G18RapidPlay")
        let photos=try JSONDecoder().decode([Photo].self,from:Data(contentsOf:root.appendingPathComponent("frames.json")))
        let views=try JSONDecoder().decode([View].self,from:Data(contentsOf:root.appendingPathComponent("observations.json")))
        func image(_ name:String)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!}
        let reference=image("reference.png")
        let game=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:root.appendingPathComponent("before.sgf"))))
        let trial=SGFPlayer();trial.load(game:game);trial.seek(to:77)
        let before=DeferredMoveHistory.states(trial.board)
        var checks=0
        func check(_ value:Bool,_ text:String) {checks+=1;precondition(value,text)}
        for (color,point) in [(Stone.white,131),(.black,170),(.white,130)] {
            check(trial.tryPlayMove(color:color,x:point%19,y:point/19)==nil,"The photographed rapid sequence must be legal")
        }
        let after=DeferredMoveHistory.states(trial.board)
        check(after[169] == .empty && after[131] == .white,"J19 did not capture J18 or G18 disappeared")
        for photo in photos {
            let result=BoardDetector.detect(frame:image(photo.image),reference:reference,calibration:photo.calibration,
                threshold:photo.threshold,referenceCalibration:photo.referenceCalibration)!
            let expected=photo.hasNewMoves ? after:before
            check(result.signature[131]==expected[131],"G18 was lost at the 0.28-cell boundary in \(photo.image)")
            for p in expected.indices where expected[p] == .empty {
                check(result.signature[p].stone==nil,"Invented a stone at \(p) in \(photo.image)")
            }
            if photo.hasNewMoves {
                let shape=(result.footprints+result.placementFits).first{$0.row==6 && $0.col==17}
                check(shape != nil && shape!.quality>=0.9,"G18 bypassed independent outline evidence")
                print(photo.image,"G18",result.readings[131].confidence,"center",shape!.center)
            }
        }
        // Preserve the original rapid observation cadence and every other
        // uncertain point. Correct only the independently photographed G18.
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("g18-rapid-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("game.sgf")
        try FileManager.default.copyItem(at:root.appendingPathComponent("before.sgf"),to:file)
        let recorder=GameRecorder(storage:folder);recorder.clock.audible=false;try recorder.restoreSavedGame(from:file);recorder.resume()
        let origin=ProcessInfo.processInfo.systemUptime-views[0].time+2
        var previous=origin+views[0].time-1.5
        for i in 0..<6 {
            let t=previous+Double(i)*0.21
            recorder.consume(.init(readings:before.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19),now:t)
        }
        previous+=1.05
        for view in views {
            let t=origin+view.time
            while t-previous>0.5 {previous+=0.3;recorder.noteHandObstruction(now:previous)}
            previous=t
            var values=view.position.map{$0=="B" ? Occupancy.black:$0=="W" ? .white:$0=="?" ? .uncertain:.empty}
            if values[131] == .uncertain {values[131] = .white}
            recorder.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19),now:t)
        }
        let recovered=recorder.game.moves.dropFirst(77).compactMap{$0.1.map{$0.1*19+$0.0}}
        print("REPLAY",recorder.moveCount,recovered,recorder.status)
        check(recovered==[131,170,130],"Rapid play lost or reordered the corrected G18 / J19 capture / G17 sequence")
        check(!recorder.hasDeferredMoves && recorder.pendingMoveCount==0,"Corrected input still tangled the rapid sequence")
        recorder.pause()
        print("PASS: \(checks) photographed G18 boundary and rapid-capture checks")
    }
}
