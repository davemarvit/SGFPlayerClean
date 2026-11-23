import Foundation
import ImageIO
import CoreImage

@main struct CrowdedAlignmentTests {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedAlignment")
        func image(_ name:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!
        }
        let photo=image("board.png"),frame=GrayFrame(image:photo)!,empty=GrayFrame(image:image("empty.png"))!
        let calibration=try JSONDecoder().decode(BoardCalibration.self,from:Data(contentsOf:root.appendingPathComponent("calibration.json")))
        let expected=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:root.appendingPathComponent("expected.json")))
        var checks=0
        func check(_ value:Bool,_ message:String) {
            checks += 1
            if !value {print("FAIL: \(message)");fatalError(message)}
        }
        check(AutoGridDetector.knownGridSupport(frame:frame,calibration:calibration,expected:expected) != nil,
              "Crowded quarter with seven of eight segments rejected despite matching stones")
        let recovery=try AutoGridDetector.recover(image:photo,size:19,previous:calibration,expected:expected)
        check(recovery.result != nil && recovery.usedStones,"Occupied recovery failed on crowded board")
        let anchor=AutoGridDetector.trackingAnchor(frame:empty,calibration:calibration)!
        var report=[String:Any]()
        let start=ProcessInfo.processInfo.systemUptime
        let aligned=AutoGridDetector.track(frame:frame,from:calibration,anchor:anchor,expected:expected,report:{report=$0})
        let elapsed=ProcessInfo.processInfo.systemUptime-start
        check(aligned != nil,"Crowded board tracking failed")
        check(report["outcome"] as? String == "existing grid supported by known stones and exposed lines",
              "Crowded board still fell through to the full-grid search")
        // A second real frame loses just one low-contrast disk (54 -> 53
        // matches among 63 local stones). This must not restart acquisition.
        let context=CIContext()
        for filename in ["marginal-stone.png","faint-segment.png"] {
        let noisyPhoto=image(filename)
        for brightness in [-0.01,0,0.01] {
            let input=CIImage(cgImage:noisyPhoto)
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let noisy=GrayFrame(image:adjusted)!
            check(AutoGridDetector.knownGridSupport(frame:noisy,calibration:calibration,expected:expected) != nil,
                  "One marginal disk or small brightness change invalidated the crowded grid")
            var detail=[String:Any]()
            check(AutoGridDetector.track(frame:noisy,from:calibration,anchor:anchor,expected:expected,report:{detail=$0}) != nil,
                  "Crowded-grid tracking flickered on a second photographed frame")
            check(detail["outcome"] as? String == "existing grid supported by known stones and exposed lines",
                  "Marginal stone triggered full-grid reacquisition")
        }
        }
        // Move197 exposed a second faint segment in a quarter with only eight
        // testable segments, while 220/222 lines and 168 stones still matched.
        let k16Photo=image("K16/rejected.png")
        let k16Cal=try JSONDecoder().decode(BoardCalibration.self,from:Data(contentsOf:root.appendingPathComponent("K16/calibration.json")))
        let k16Expected=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:root.appendingPathComponent("K16/expected.json")))
        for brightness in [-0.01,0,0.01] {
            let input=CIImage(cgImage:k16Photo)
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let current=GrayFrame(image:adjusted)!
            check(AutoGridDetector.occupiedPatternSupport(frame:current,calibration:k16Cal,expected:k16Expected) != nil,
                  "Two faint segments overruled distributed current stone/grid evidence at K16")
            check(AutoGridDetector.track(frame:current,from:k16Cal,anchor:anchor,expected:k16Expected) != nil,
                  "K16 camera frame still cancels laser guidance")
        }
        let k16Frame=GrayFrame(image:k16Photo)!
        for dx in [-1.0,-0.5,0.5,1.0] {
            let moved=BoardCalibration(size:19,corners:[(0.0,0.0),(18,0),(18,18),(0,18)].map {
                k16Cal.point(col:$0.0+dx,row:$0.1)
            })!
            check(AutoGridDetector.knownGridSupport(frame:k16Frame,calibration:moved,expected:k16Expected)==nil,
                  "K16 moved grid accepted at offset \(dx)")
            check(AutoGridDetector.occupiedPatternSupport(frame:k16Frame,calibration:moved,expected:k16Expected)==nil,
                  "K16 occupied pattern accepted a shifted grid at \(dx)")
        }
        let k16Wrong=k16Expected.enumerated().map {i,value -> Occupancy in
            guard i/19>=10 && i%19>=10 else {return value}
            return value == .black ? .white:value == .white ? .black:value
        }
        check(AutoGridDetector.knownGridSupport(frame:k16Frame,calibration:k16Cal,expected:k16Wrong)==nil,
              "K16 crowded quadrant accepted with contradictory current stone colors")
        check(AutoGridDetector.occupiedPatternSupport(frame:k16Frame,calibration:k16Cal,expected:k16Wrong)==nil,
              "K16 occupied pattern accepted contradictory local colors")
        var pending=k16Expected;pending[174] = .black
        check(AutoGridDetector.occupiedPatternSupport(frame:k16Frame,calibration:k16Cal,expected:pending) != nil,
              "Pending AI stone absent from the physical board invalidates all geometry")
        let wrongLocal=expected.enumerated().map { i,value -> Occupancy in
            guard i/19>=10 && i%19>=10 else {return value}
            return value == .black ? .white:value == .white ? .black:value
        }
        check(AutoGridDetector.knownGridSupport(frame:frame,calibration:calibration,expected:wrongLocal)==nil,
              "Matching stones elsewhere authorized contradictory stones in the crowded quarter")
        for dx in [-1.0,-0.5,0.5,1.0] {
            let moved=BoardCalibration(size:19,corners:[(0.0,0.0),(18,0),(18,18),(0,18)].map {
                calibration.point(col:$0.0+dx,row:$0.1)
            })!
            check(AutoGridDetector.knownGridSupport(frame:frame,calibration:moved,expected:expected)==nil,
                  "Misregistered grid accepted at offset \(dx)")
        }
        check(AutoGridDetector.knownGridSupport(frame:empty,calibration:calibration,expected:expected)==nil,
              "Expected history supplied stone evidence absent from the image")
        var pixels=frame.pixels
        // Erase the crowded quarter: matching evidence elsewhere must not
        // compensate for an obstruction covering this region.
        for y in 0..<frame.height {for x in 0..<frame.width {
            let p=ImagePoint(x:Double(x)/Double(frame.width-1),y:Double(y)/Double(frame.height-1))
            if let grid=calibration.gridPoint(for:p),grid.x>=9.5,grid.y>=9.5 {
                pixels[y*frame.width+x]=128
            }
        }}
        let masked=GrayFrame(width:frame.width,height:frame.height,pixels:pixels)
        check(AutoGridDetector.knownGridSupport(frame:masked,calibration:calibration,expected:expected)==nil,
              "Covered quadrant accepted from evidence elsewhere")
        check(AutoGridDetector.occupiedPatternSupport(frame:masked,calibration:calibration,expected:expected)==nil,
              "Occupied pattern accepted a covered quadrant")
        check(AutoGridDetector.occupiedPatternSupport(frame:empty,calibration:calibration,expected:expected)==nil,
              "Occupied pattern borrowed absent stones from history")
        print("PASS: \(checks) photographed crowded-grid checks; track \(elapsed)s")
    }
}
