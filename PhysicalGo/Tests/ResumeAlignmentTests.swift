import Foundation
import ImageIO

@main struct ResumeAlignmentTests {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ResumeAlignment")
        struct Sample:Decodable {let calibration:BoardCalibration}
        let prior=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:root.appendingPathComponent("sample.json"))).calibration
        let expected=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:root.appendingPathComponent("expected.json")))
        let corners=try JSONDecoder().decode([[Double]].self,from:Data(contentsOf:root.appendingPathComponent("corners.json")))
        let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent("frame.png") as CFURL,nil)!,0,nil)!
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        for previous in [prior,nil] {
            let recovery=try AutoGridDetector.recover(image:image,size:19,previous:previous,expected:expected)
            guard let result=recovery.result else {fatalError(recovery.reason)}
            check(recovery.usedStones,"Occupied recovery bypassed saved-stone verification")
            for (i,p) in result.calibration.corners.enumerated() {
                check(hypot(p.x*Double(image.width-1)-corners[i][0],p.y*Double(image.height-1)-corners[i][1])<8,"Recovered the wrong printed corner")
            }
            let frame=GrayFrame(image:image)!
            let evidence=AutoGridDetector.landmarkEvidence(frame:frame,size:19,expected:expected) {result.calibration.point(col:$0,row:$1)}
            check(evidence.matched>=60,"Recovery did not match the saved game")
            check(AutoGridDetector.knownGridSupport(frame:frame,calibration:result.calibration,expected:expected) != nil,"Recovered grid lacks independent exposed-line support")
        }
        let wrong=expected.map {$0 == .black ? Occupancy.white:$0 == .white ? .black:$0}
        check(try AutoGridDetector.recover(image:image,size:19,previous:prior,expected:wrong).result == nil,"Wrong stone colors authorized alignment")
        let cropped=image.cropping(to:CGRect(x:0,y:180,width:image.width,height:image.height-180))!
        check(try AutoGridDetector.recover(image:cropped,size:19,previous:prior,expected:expected).result == nil,"Missing outer grid was accepted")
        for size in [9,13] {
            let subset=(0..<(size*size)).map {expected[($0/size)*19+$0%size]}
            check(try AutoGridDetector.recover(image:image,size:size,previous:nil,expected:subset).result == nil,"Wrong board size accepted")
        }
        print("PASS: \(checks) occupied-board recovery checks, with/without prior alignment, wrong colors, cropping and wrong sizes")
    }
}
