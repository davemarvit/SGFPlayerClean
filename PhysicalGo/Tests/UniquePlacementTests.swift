import Foundation
import CoreGraphics
import ImageIO

@main struct UniquePlacementTests {
    struct Meta:Decodable {let calibration,referenceCalibration:BoardCalibration;let threshold:Double}
    struct Frame:Decodable {let captureUptime:Double;let readings:[IntersectionReading];let footprints:[StoneFootprint];let placementFits:[StoneFootprint]}
    @MainActor static func main() throws {
        setbuf(stdout,nil);var count=0
        func check(_ value:Bool,_ message:String) {count += 1;if !value {print("FAIL: "+message);exit(1)}}
        func view(dx:Double,dy:Double=0,radius:Double=0.5,quality:Double=0.98,confidence:Double=0.98,color:Occupancy = .white)->BoardObservation {
            let readings=(0..<81).map {IntersectionReading(row:$0/9,col:$0%9,occupancy:$0==40 ? color:.empty,confidence:confidence,delta:0)}
            return .init(readings:readings,size:9,footprints:[.init(row:4,col:4,center:.init(x:4+dx,y:4+dy),radiusCol:radius,radiusRow:radius,quality:quality)])
        }
        for color in [Occupancy.black,.white] {
            for (dx,dy) in [(0.32,0.0),(-0.36,0),(0,0.32),(0,-0.36),(0.28,0.28)] {
                let observation=view(dx:dx,dy:dy,color:color)
                check(observation.assignmentOffsets[40]==0,"Unique off-center disk was blocked")
                check(abs(observation.placementOffsets[40]!-max(abs(dx),abs(dy)))<1e-8,"Raw displacement was hidden")
            }
        }
        for observation in [view(dx:0.49),view(dx:0.42,radius:0.46),view(dx:0.32,dy:0.32),view(dx:0.32,quality:0.91),view(dx:0.32,confidence:0.9),view(dx:0.32,radius:0.3)] {
            check((observation.assignmentOffsets[40] ?? 1)>=0.30,"Ambiguous or unsupported placement was cleared")
        }
        var conflict=view(dx:0.32);conflict.placementFits=view(dx:0.49).footprints
        check(conflict.ambiguousPlacements.contains(40),"Conflicting outline was ignored")
        print("Synthetic placement checks passed")
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/UniqueOffCenter")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func load(_ name:String)->GrayFrame {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        let actual=BoardDetector.detect(frame:load("frame.png"),reference:load("empty-reference.png"),calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
        check(actual.readings[52].occupancy == .white,"Actual photo lost the new white stone")
        check(actual.placementOffsets[52]!>=0.28-1e-8 && actual.assignmentOffsets[52]==0,"Actual off-center stone still blocked")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("unique-placement-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let tree=try SGFParser.parse(text:String(contentsOf:folder.appendingPathComponent("recording.sgf"),encoding:.utf8))
        let file=root.appendingPathComponent("game.sgf")
        try SGFWriter.serialize(SGFTree(branches:[.init(sequence:Array(tree.mainLineNodes.prefix(20)))])).write(to:file,atomically:true,encoding:.utf8)
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:file);check(recorder.moveCount==19,"Replay must begin at move 19")
        let prefix=recorder.game.moves.map {$0.1!.1*19+$0.1!.0}
        recorder.resume()
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:folder.appendingPathComponent("observations.json")))
        let board=recorder.positions.last!
        let baseline=BoardObservation(readings:(0..<361).map {i in
            .init(row:i/19,col:i%19,occupancy:board.grid[i/19][i%19] == .black ? .black:board.grid[i/19][i%19] == .white ? .white:.empty,confidence:1,delta:0)
        },size:19)
        for i in 0..<8 {recorder.consume(baseline,now:frames[0].captureUptime-2+Double(i)*0.21)}
        var firstWhite:Double?,accepted:Double?
        for frame in frames {
            if frame.readings[52].occupancy == .white,firstWhite==nil {firstWhite=frame.captureUptime}
            recorder.consume(.init(readings:frame.readings,size:19,footprints:frame.footprints,placementFits:frame.placementFits),now:frame.captureUptime)
            if recorder.moveCount==20,accepted==nil {accepted=frame.captureUptime}
        }
        check(recorder.moveCount==20,"Historical clip did not record exactly one new move: \(recorder.status)")
        check(recorder.game.moves.last!.0 == .white && recorder.game.moves.last!.1!.1*19+recorder.game.moves.last!.1!.0==52,"Replay chose a different move")
        check(Array(recorder.game.moves.prefix(19)).map {$0.1!.1*19+$0.1!.0}==prefix,"Replay changed earlier moves")
        check(accepted != nil && accepted!-firstWhite!>=0.8,"Placement bypassed temporal confirmation")
        print("Historical move 20 accepted \(String(format:"%.2f",accepted!-firstWhite!)) seconds after first white sighting; old live recording remained blocked.")
        // Reopen the user's already-flagged pending move, as an installed update
        // will do. Fresh unique outlines must clear that retained concern too.
        let retainedFile=root.appendingPathComponent("retained.sgf")
        try SGFWriter.serialize(SGFTree(branches:[.init(sequence:Array(tree.mainLineNodes.prefix(20)))])).write(to:retainedFile,atomically:true,encoding:.utf8)
        try FileManager.default.copyItem(at:folder.appendingPathComponent("pending.json"),to:retainedFile.deletingPathExtension().appendingPathExtension("pending.json"))
        let retained=GameRecorder(storage:root);retained.clock.audible=false
        try retained.restoreSavedGame(from:retainedFile)
        check(retained.moveCount==19 && retained.pendingMoveCount==1,"Existing pending move failed to restore")
        retained.resume()
        let epoch=ProcessInfo.processInfo.systemUptime
        for (i,frame) in frames.filter({$0.readings[52].occupancy == .white}).enumerated() {
            retained.consume(.init(readings:frame.readings,size:19,footprints:frame.footprints,placementFits:frame.placementFits),now:epoch+Double(i)*0.21)
        }
        check(retained.moveCount==20 && retained.pendingMoveCount==0,"Restored placement concern did not clear with unique outlines")
        check(retained.game.moves.last!.1!.1*19+retained.game.moves.last!.1!.0==52,"Restored pending move changed intersection")
        print("PASS: \(count) unique-placement checks")
    }
}
