import Foundation
import CoreGraphics
import CoreImage
import ImageIO
@main struct CoveredGridStoneTests {
    struct Corpus:Decodable {
        struct Sample:Decodable {
            let session:String,frame:Int,image:String,reference:String
            let calibration:BoardCalibration,reference_calibration:BoardCalibration
            let threshold:Double
        }
        let cases:[Sample]
    }
    static func main() throws {
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ShadowRegression/v1")
        let corpus=try JSONDecoder().decode(Corpus.self,from:Data(contentsOf:root.appendingPathComponent("manifest.json")))
        let targets:[String:[Int]]=["6631BCB8/269":[39,78],"A7ACE3FA/1114":[93],"A7ACE3FA/1270":[51]]
        let context=CIContext();var checked=0,white=0,uncertain=0
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        for sample in corpus.cases {
            guard let points=targets["\(sample.session)/\(sample.frame)"] else {continue}
            let original=image(sample.image),reference=GrayFrame(image:image(sample.reference))!
            let input=CIImage(cgImage:original)
            for brightness in [-0.003,0,0.003] {
                let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
                for dy in [-0.5,0,0.5] {for dx in [-0.5,0,0.5] {
                    let grid=BoardCalibration(size:19,corners:sample.calibration.corners.map{.init(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                    let result=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:grid,threshold:sample.threshold,referenceCalibration:sample.reference_calibration)!
                    for p in points {
                        let value=result.readings[p].occupancy
                        precondition(value == .white || value == .uncertain,"Missed white stone \(sample.session)/\(sample.frame)/\(p): \(value), brightness \(brightness), offset \(dx),\(dy)")
                        if value == .white {white += 1} else {uncertain += 1}
                        checked += 1
                    }
                    if sample.session=="6631BCB8" {
                        for p in [304,323] {precondition(result.readings[p].occupancy.stone==nil,"Reintroduced false black")}
                    }
                }}
            }
        }
        precondition(checked==108 && white>0)
        print("PASS: \(checked) missed-white perturbations: \(white) white, \(uncertain) uncertain, none empty or wrong color; false-black guards retained.")
    }
}
