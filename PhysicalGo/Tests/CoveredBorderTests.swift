import Foundation
import CoreGraphics
import ImageIO

@MainActor func runCoveredBorderTests() throws {
    setbuf(stdout,nil)
    var checks=0
    func check(_ ok:Bool,_ text:String) {checks += 1;precondition(ok,text)}
    struct Anchor:Decodable {let calibration:BoardCalibration;let fittedGrid:BoardCalibration;let width:Int;let height:Int}
    struct Metadata:Decodable {let calibration:BoardCalibration;let anchor:Anchor;let frames:[String]}
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/CoveredBorder")
    let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:root.appendingPathComponent("metadata.json")))
    let pixels=try Data(contentsOf:root.appendingPathComponent("anchor.gray"))
    let anchorFrame=GrayFrame(width:meta.anchor.width,height:meta.anchor.height,pixels:Array(pixels))
    let anchor=AutoGridDetector.TrackingAnchor(calibration:meta.anchor.calibration,fittedGrid:meta.anchor.fittedGrid,frame:anchorFrame)
    let tree=try SGFParser.parse(text:String(contentsOf:root.appendingPathComponent("game.sgf"),encoding:.utf8))
    let game=SGFGame.from(tree:tree);var setup=game;setup.moves=[];setup.sourceTree=nil
    let player=SGFPlayer();player.load(game:setup)
    for move in game.moves.prefix(26) {check(player.tryPlayMove(color:move.0,x:move.1?.0 ?? -1,y:move.1?.1 ?? -1)==nil,"Fixture replay invalid")}
    let expected=player.board.grid.flatMap {$0}.map {$0 == .black ? Occupancy.black:$0 == .white ? .white:.empty}
    var recovered=0
    for name in meta.frames {
        let source=CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!
        let image=CGImageSourceCreateImageAtIndex(source,0,nil)!,frame=GrayFrame(image:image)!
        let old=AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor)
        var report=[String:Any]()
        let start=ProcessInfo.processInfo.systemUptime
        let aligned=AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor,expected:expected,report:{report=$0})
        print("Covered edge \(name): old=\(old != nil) new=\(aligned != nil) landmarks=\(report["knownStoneFraction"] ?? "unused"), \(String(format:"%.1f",(ProcessInfo.processInfo.systemUptime-start)*1000)) ms")
        check(aligned==meta.calibration,"Stationary board with sleeve-covered edge was lost")
        if old==nil {
            recovered += 1
            let wrong=expected.map {$0 == .black ? Occupancy.white:$0 == .white ? .black:$0}
            check(AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor,expected:wrong)==nil,"Wrong-color history supplied fictional support")
            check(AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor,expected:Array(repeating:.empty,count:361))==nil,"No landmarks relaxed border requirement")
            for (dx,dy) in [(1.0,0.0),(-1,0),(0,1),(0,-1),(0.5,0.5)] {
                let corners=[(0.0,0.0),(18,0),(18,18),(0,18)].map {meta.calibration.point(col:$0.0+dx,row:$0.1+dy)}
                let shifted=BoardCalibration(size:19,corners:corners)!
                let evidence=AutoGridDetector.landmarkEvidence(frame:frame,size:19,expected:expected) {shifted.point(col:$0,row:$1)}
                check(evidence.fraction<0.85,"Shifted intersections passed landmark check")
            }
            // Hiding a second edge must not receive the single-edge exception.
            var masked=frame.pixels
            for row in 0..<frame.height {for col in 0..<frame.width where Double(col)>0.70*Double(frame.width) {masked[row*frame.width+col]=160}}
            let twoEdges=GrayFrame(width:frame.width,height:frame.height,pixels:masked)
            check(AutoGridDetector.knownGridSupport(frame:twoEdges,calibration:meta.calibration,expected:expected,allowSingleCoveredBorder:true)==nil,"Two covered borders passed single-edge gate")
        }
    }
    check(recovered>=1,"Fixture no longer reproduces the false grid loss")
    let blank=GrayFrame(width:anchorFrame.width,height:anchorFrame.height,pixels:Array(repeating:160,count:anchorFrame.pixels.count))
    check(AutoGridDetector.track(frame:blank,from:meta.calibration,anchor:anchor,expected:expected)==nil,"Blank image accepted from history alone")
    print("PASS: \(checks) covered-edge checks; \(recovered) saved frames recovered; wrong colors, wrong intersections, multiple hidden edges and blank view rejected")
}
