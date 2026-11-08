import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct TouchingEdgeTests {
    struct Metadata:Decodable {
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
        let readings:[IntersectionReading]
    }
    static func main()throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/TouchingEdge")
        let context=CIContext();var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;if !value {fatalError(message)}}
        func image(_ url:URL)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!}
        for name in ["210","243","350","653"] {
            let folder=root.appendingPathComponent(name)
            let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            let input=CIImage(cgImage:image(folder.appendingPathComponent("frame.png")))
            let reference=GrayFrame(image:image(folder.appendingPathComponent("empty-reference.png")))!
            for brightness in [-0.003,0,0.003] {
                let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
                let result=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                if name=="210" {check(result.signature[10].stone==nil,"Invented A11 before it was played")}
                if name=="350" || name=="653" {
                    check(result.signature[10] == .black,"Lost A11 in clear frame \(name), brightness \(brightness)")
                    check(result.signature[11] == .empty && result.signature[29] == .empty,"Removed whites still visible")
                    check(result.footprints.contains{$0.row==0 && $0.col==10},"A11 lacks independent shape evidence")
                }
                for (i,reading) in meta.readings.enumerated() where reading.occupancy.stone != nil {
                    check(result.signature[i]==reading.occupancy,"Lost another stone \(i) in \(name), brightness \(brightness)")
                }
                let added=result.readings.indices.filter {result.signature[$0].stone != nil && result.signature[$0] != meta.readings[$0].occupancy}
                check(Set(added).isSubset(of:[10]),"Invented other stones: \(added)")
                print("Frame \(name), brightness \(brightness): A11 \(result.signature[10]), new occupied points \(added)")
            }
        }
        print("PASS: \(checks) touching-edge checks; clear A11 recognized, earlier absence preserved, removed whites empty, other stones retained.")
    }
}
