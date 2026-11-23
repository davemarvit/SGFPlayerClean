import Foundation
import CoreGraphics

@main struct OccupiedGridTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;if !value {fatalError(message)}}
        let n=19,side=800
        let cal=BoardCalibration(size:n,corners:[ImagePoint(x:0.14,y:0.14),ImagePoint(x:0.86,y:0.14),ImagePoint(x:0.86,y:0.86),ImagePoint(x:0.14,y:0.86)])!
        func photo(_ cells:[Occupancy],maskQuadrant:Int?=nil)->GrayFrame {
            var pixels=[UInt8](repeating:210,count:side*side)
            for y in 0..<side {for x in 0..<side {
                let g=cal.gridPoint(for:.init(x:Double(x)/Double(side-1),y:Double(y)/Double(side-1)))!
                let c=Int(g.x.rounded()),r=Int(g.y.rounded())
                guard (0..<n).contains(c),(0..<n).contains(r) else {continue}
                let q=(r<10 ? 0:2)+(c<10 ? 0:1)
                if q==maskQuadrant {pixels[y*side+x]=128;continue}
                if hypot(g.x-Double(c),g.y-Double(r))<=0.46 {
                    pixels[y*side+x]=cells[r*n+c] == .black ? 30:cells[r*n+c] == .white ? 252:210
                }
            }}
            return GrayFrame(width:side,height:side,pixels:pixels)
        }
        func image(_ frame:GrayFrame)->CGImage {
            CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:side,
                    space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),
                    provider:CGDataProvider(data:Data(frame.pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        }
        let patterns:[[Occupancy]]=[
            (0..<n*n).map {($0/n+$0%n)%2==0 ? .black:.white},
            (0..<n*n).map {($0*17+$0/n*7)%11<6 ? .black:.white},
            Array(repeating:.black,count:n*n),Array(repeating:.white,count:n*n)]
        for (index,expected) in patterns.enumerated() {
            let frame=photo(expected)
            // No grid lines are drawn, and every intersection is occupied.
            check(AutoGridDetector.knownGridSupport(frame:frame,calibration:cal,expected:expected)==nil,"Fixture unexpectedly supplied empty grid segments")
            check(AutoGridDetector.occupiedPatternSupport(frame:frame,calibration:cal,expected:expected) != nil,"Fully occupied pattern \(index) rejected")
            let anchor=AutoGridDetector.TrackingAnchor(calibration:cal,fittedGrid:cal,frame:frame)
            var report=[String:Any]()
            check(AutoGridDetector.track(frame:frame,from:cal,anchor:anchor,expected:expected,report:{report=$0})==cal,"Full-board tracking requires empties")
            let recovered=try AutoGridDetector.recover(image:image(frame),size:n,previous:cal,expected:expected)
            check(recovered.result?.calibration==cal && recovered.usedStones,"Full-board resume requires empties")
            let wrong=expected.map {$0 == .black ? Occupancy.white:.black}
            check(AutoGridDetector.occupiedPatternSupport(frame:frame,calibration:cal,expected:wrong)==nil,"Wrong colors supplied geometry")
            for (dx,dy) in [(-1.0,0.0),(1,0),(0,-1),(0,1),(-0.5,0),(0.5,0),(0,-0.5),(0,0.5),(0.5,0.5)] {
                let shifted=BoardCalibration(size:n,corners:[(0.0,0.0),(18,0),(18,18),(0,18)].map {cal.point(col:$0.0+dx,row:$0.1+dy)})!
                check(AutoGridDetector.occupiedPatternSupport(frame:frame,calibration:shifted,expected:expected)==nil,"Shifted full board \(index) accepted: \(dx),\(dy)")
            }
            for q in 0..<4 {
                check(AutoGridDetector.occupiedPatternSupport(frame:photo(expected,maskQuadrant:q),calibration:cal,expected:expected)==nil,"Obscured quarter accepted from history")
            }
        }
        let blank=photo(Array(repeating:.empty,count:n*n))
        check(AutoGridDetector.occupiedPatternSupport(frame:blank,calibration:cal,expected:patterns[0])==nil,"Blank image accepted from history")
        // A sparse or clustered early game still needs other visible geometry.
        var sparse=Array(repeating:Occupancy.empty,count:n*n)
        for r in 0..<5 {for c in 0..<5 {sparse[r*n+c] = .black}}
        check(AutoGridDetector.occupiedPatternSupport(frame:photo(sparse),calibration:cal,expected:sparse)==nil,"One dense corner authorized the whole board")
        print("PASS: \(checks) occupied-board checks; no empty intersections or printed grid lines in full-board fixtures")
    }
}
