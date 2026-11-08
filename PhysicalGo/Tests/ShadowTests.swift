import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct ShadowTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable { let calibration:BoardCalibration; let threshold:Double; let readings:[IntersectionReading] }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/FalseBlack")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL,nil)!
        let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
        let falseIndex=14*19+15
        guard meta.readings[falseIndex].occupancy == .black else { fatalError("Fixture did not catch the false candidate") }
        // Checked against the photograph: the extra candidate is an empty point
        // above/left of the black cluster; all other saved stones are real.
        let expected=meta.readings.filter { $0.occupancy.stone != nil && $0.row*19+$0.col != falseIndex }
        guard expected.count == 21 else { fatalError("Incorrect expected fixture position") }
        let context=CIContext(),input=CIImage(cgImage:image)
        var cases=0
        for brightness in [-0.005,0,0.005] {
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let frame=GrayFrame(image:adjusted)!
            for dy in [-0.5,0,0.5] { for dx in [-0.5,0,0.5] {
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                let result=BoardAppearanceDetector.detect(frame:frame,calibration:cal,threshold:meta.threshold)
                guard result.readings[falseIndex].occupancy.stone == nil else {
                    fatalError("Shadow became a stone at brightness \(brightness), shift \(dx),\(dy)")
                }
                for reading in expected {
                    guard result.readings[reading.row*19+reading.col].occupancy == reading.occupancy else {
                        fatalError("Lost real stone \(reading.row),\(reading.col) at brightness \(brightness), shift \(dx),\(dy)")
                    }
                }
                guard result.snapshot.stones.count == expected.count else { fatalError("Invented a different stone") }
                cases += 1
            } }
        }
        print("PASS: false black candidate rejected and all 21 real stones retained across \(cases) brightness/calibration cases")
    }
}
