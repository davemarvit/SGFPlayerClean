import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct VisibleGridStoneTests {
    struct Corpus:Decodable {
        struct Case:Decodable {
            let session:String,frame:Int,image:String,reference:String
            let calibration:BoardCalibration,reference_calibration:BoardCalibration
            let threshold:Double
        }
        let cases:[Case]
    }
    static func main() throws {
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ShadowRegression/v1")
        let corpus=try JSONDecoder().decode(Corpus.self,from:Data(contentsOf:root.appendingPathComponent("manifest.json")))
        let sample=corpus.cases.first{$0.session=="6631BCB8" && $0.frame==269}!
        func image(_ file:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(file) as CFURL,nil)!,0,nil)!}
        let original=image(sample.image),reference=GrayFrame(image:image(sample.reference))!,context=CIContext()
        var cases=0
        for brightness in [-0.003,0,0.003] {
            let input=CIImage(cgImage:original)
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            for dy in [-0.5,0,0.5] {for dx in [-0.5,0,0.5] {
                let grid=BoardCalibration(size:19,corners:sample.calibration.corners.map{.init(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                let result=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:grid,threshold:sample.threshold,referenceCalibration:sample.reference_calibration)!
                for p in [304,323] {precondition(result.readings[p].occupancy.stone==nil,"Visible grid still called a stone at \(p), brightness \(brightness), offset \(dx),\(dy)")}
                for (p,color) in [(5,Occupancy.white),(59,.black),(79,.black)] {
                    precondition(result.readings[p].occupancy==color,"Lost labeled real stone at \(p)")
                }
                cases += 1
            }}
        }
        print("PASS: both historical false positives suppressed across \(cases) brightness/alignment variants; labeled black and white stones retained.")
    }
}
