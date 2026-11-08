import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct GrainTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable { let calibration:BoardCalibration; let threshold:Double; let readings:[IntersectionReading] }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/GrainedWhite")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL,nil)!
        let image=CGImageSourceCreateImageAtIndex(source,0,nil)!,frame=GrayFrame(image:image)!
        let evidence=BoardAppearanceDetector.gridEvidence(frame:frame,calibration:meta.calibration,col:7,row:16)
        print("H3 directional evidence:",evidence)
        let result=BoardAppearanceDetector.detect(frame:frame,calibration:meta.calibration,threshold:meta.threshold)
        print("H3:",result.readings[16*19+7],"stones",result.snapshot.stones.count,"uncertain",result.signature.filter{$0 == .uncertain}.count)
        guard meta.readings[16*19+7].occupancy == .uncertain else { fatalError("Fixture did not catch the flicker") }
        guard result.readings[16*19+7].occupancy == .white else { fatalError("H3 grain still prevents white recognition") }
        var expected=meta.readings.map(\.occupancy)
        expected[16*19+7] = .white
        for reading in result.readings where reading.occupancy.stone != nil {
            guard expected[reading.row*19+reading.col]==reading.occupancy else { fatalError("Introduced a false stone at \(reading.row),\(reading.col)") }
        }
        guard result.snapshot.stones.count==21 else { fatalError("Lost an existing stone") }
        let context=CIContext(),input=CIImage(cgImage:image)
        for brightness in [-0.005,0,0.005] {
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            for dx in [-0.5,0,0.5] {
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y)})!
                let result=BoardAppearanceDetector.detect(frame:GrayFrame(image:adjusted)!,calibration:cal,threshold:meta.threshold)
                guard result.readings[16*19+7].occupancy == .white else { fatalError("H3 unstable at brightness \(brightness), dx \(dx)") }
                if result.snapshot.stones.count != 21 { print("Perturbation",brightness,dx,result.readings.filter{$0.occupancy.stone != nil}.map{"\($0.row),\($0.col):\($0.occupancy)"}) }
                guard result.snapshot.stones.count==21 else { fatalError("Perturbation changed the stone count") }
                for reading in result.readings where reading.occupancy.stone != nil {
                    guard expected[reading.row*19+reading.col]==reading.occupancy else { fatalError("Perturbation assigned a stone to an empty point") }
                }
            }
        }
        // Parallel grain in either direction is not a surviving grid cross.
        let syntheticCal=BoardCalibration(size:9,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        for (col,row) in [(4,4),(0,4),(0,0)] {
            for grain in 0...3 {
                let side=720
                var pixels=[UInt8](repeating:176,count:side*side)
                for rail in 0..<9 {
                    let p=Int((0.1+0.1*Double(rail))*719)
                    for along in 72...647 { for offset in -1...1 { pixels[along*side+p+offset]=35; pixels[(p+offset)*side+along]=35 } }
                }
                let center=syntheticCal.point(col:Double(col),row:Double(row))
                let cx=Int(center.x*719),cy=Int(center.y*719)
                for y in cy-30...cy+30 { for x in cx-30...cx+30 where hypot(Double(x-cx),Double(y-cy))<30 {
                    let onGrain=(grain & 1 != 0 && abs(x-cx)<=1) || (grain & 2 != 0 && abs(y-cy)<=1)
                    pixels[y*side+x]=onGrain ? 180 : 240
                } }
                let result=BoardAppearanceDetector.detect(frame:GrayFrame(width:side,height:side,pixels:pixels),calibration:syntheticCal,threshold:0.13)
                let expected:Occupancy=grain==3 ? .uncertain : .white
                guard result.readings[row*9+col].occupancy==expected else { fatalError("Synthetic grain \(grain) at \(col),\(row) was confused with grid ink") }
                guard result.snapshot.stones.count==(grain==3 ? 0 : 1) else { fatalError("Grain generated a neighboring false stone") }
            }
        }
        print("PASS: saved grain flicker, correct 21-stone position, small brightness and calibration changes")
    }
}
