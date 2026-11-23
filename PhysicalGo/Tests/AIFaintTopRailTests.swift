import Foundation
import ImageIO

/// Recorded second-AI-move failure: stationary board, two stones, faint top rail.
@main struct AIFaintTopRailTests {
    static func main() throws {
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIFaintTopRail")
        func frame(_ name:String)->GrayFrame {
            GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!
        }
        let calibration=try JSONDecoder().decode(BoardCalibration.self,from:Data(contentsOf:root.appendingPathComponent("calibration.json")))
        let reference=frame("reference.png")
        let anchor=AutoGridDetector.trackingAnchor(frame:reference,calibration:calibration)!
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        for name in ["failure.png","later-2.png","later-7.png"] {
            let current=frame(name)
            let tracked=AutoGridDetector.track(frame:current,from:calibration,anchor:anchor)
            check(tracked != nil,"Clear physical board rejected: "+name)
            for (a,b) in zip(tracked!.corners,calibration.corners) {
                check(hypot((a.x-b.x)*1919,(a.y-b.y)*1079)<1,"Stationary board geometry drifted")
            }
            var covered=current.pixels
            for i in 0..<(current.width*180) {covered[i]=120}
            check(AutoGridDetector.track(frame:GrayFrame(width:current.width,height:current.height,pixels:covered),
                from:calibration,anchor:anchor)==nil,"Covered top rail accepted")
            let blank=GrayFrame(width:current.width,height:current.height,pixels:Array(repeating:120,count:current.pixels.count))
            check(AutoGridDetector.track(frame:blank,from:calibration,anchor:anchor)==nil,"Blank board accepted")
        }
        print("PASS: \(checks) AI faint-top-rail checks")
    }
}
