import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct ReferenceOffsetTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable { let calibration:BoardCalibration; let referenceCalibration:BoardCalibration; let threshold:Double; let readings:[IntersectionReading] }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ReferenceOffset")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func load(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let image=load("frame.png"),reference=GrayFrame(image:load("empty-reference.png"))!
        let missed=13*19+17
        guard meta.readings[missed].occupancy == .empty else { fatalError("Fixture did not catch the missed white stone") }
        var expected=meta.readings.map(\.occupancy)
        expected[missed] = .white
        let context=CIContext(),input=CIImage(cgImage:image)
        var cases=0
        for brightness in [-0.005,0,0.005] {
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let frame=GrayFrame(image:adjusted)!
            for dy in [-0.5,0,0.5] { for dx in [-0.5,0,0.5] {
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                let result=BoardDetector.detect(frame:frame,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                for i in expected.indices where expected[i].stone != nil {
                    guard result.readings[i].occupancy == expected[i] else {
                        fatalError("Lost stone \(i/19),\(i%19) at brightness \(brightness), shift \(dx),\(dy): \(result.readings[i])")
                    }
                }
                guard result.snapshot.stones.count == 20 else { fatalError("Invented a stone or duplicated a displaced stone") }
                cases += 1
            } }
        }
        let empty=BoardDetector.detect(frame:reference,reference:reference,calibration:meta.referenceCalibration,threshold:meta.threshold)!
        guard empty.signature.allSatisfy({$0 == .empty}) else { fatalError("The reference alone became occupied/uncertain") }
        print("PASS: off-center white stone, aligned grain stones and no false/duplicate stones across \(cases) brightness/alignment cases; empty reference stays empty")
    }
}
