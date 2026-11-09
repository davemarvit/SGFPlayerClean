import Foundation
import CoreGraphics
import ImageIO

@main struct RecoveryGlareTests {
    struct Sample:Decodable {
        struct Label:Decodable {let point:Int;let choice:String}
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration,threshold:Double
        let rawReadings:[IntersectionReading],labels:[Label]
    }
    struct LiveCase:Decodable {let image:String,expected:Occupancy,point:Int,calibration:BoardCalibration,referenceCalibration:BoardCalibration,threshold:Double}
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RecoveryGlare")
        let sample=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:root.appendingPathComponent("sample.json")))
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let photo=image("camera.png"),reference=GrayFrame(image:image("reference.png"))!,frame=GrayFrame(image:photo)!
        let result=BoardDetector.detect(frame:frame,reference:reference,calibration:sample.calibration,threshold:sample.threshold,referenceCalibration:sample.referenceCalibration)!
        for label in sample.labels {
            print("Glare",label.point,result.signature[label.point])
            precondition(result.signature[label.point].stone == nil,"Glare manufactured a stone at a user-confirmed empty point")
        }
        // Place a photographed real stone on the glare patch. This synthetic
        // transfer includes the photographed rim/shadow and checks that a glare
        // safeguard does not hard-code emptiness. It is not a real placement capture.
        for (source,color) in [(2*19+13,Occupancy.white),(3*19+15,.black)] {
            let origin=sample.calibration.point(col:Double(source%19),row:Double(source/19))
            let crop=photo.cropping(to:CGRect(x:origin.x*Double(photo.width)-32,y:origin.y*Double(photo.height)-32,width:64,height:64))!
            for label in sample.labels {
                let center=sample.calibration.point(col:Double(label.point%19),row:Double(label.point/19))
                let context=CGContext(data:nil,width:photo.width,height:photo.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(photo,in:CGRect(x:0,y:0,width:photo.width,height:photo.height))
                let rect=CGRect(x:center.x*Double(photo.width)-32,y:(1-center.y)*Double(photo.height)-32,width:64,height:64)
                context.addEllipse(in:rect);context.clip();context.draw(crop,in:rect)
                let inserted=BoardDetector.detect(frame:GrayFrame(image:context.makeImage()!)!,reference:reference,calibration:sample.calibration,threshold:sample.threshold,referenceCalibration:sample.referenceCalibration)!
                print("Inserted",color,label.point,inserted.signature[label.point])
                precondition(inserted.signature[label.point]==color,"A real \(color) stone on the glare patch was not recognized at \(label.point)")
            }
        }
        let live=root.appendingPathComponent("LivePlacement")
        let liveReference=GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(live.appendingPathComponent("reference.png") as CFURL,nil)!,0,nil)!)!
        let cases=try JSONDecoder().decode([LiveCase].self,from:Data(contentsOf:live.appendingPathComponent("cases.json")))
        precondition(cases.map(\.expected)==[.empty,.white,.empty],"Live placement sequence is incomplete")
        for item in cases {
            let frame=GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(live.appendingPathComponent(item.image) as CFURL,nil)!,0,nil)!)!
            let seen=BoardDetector.detect(frame:frame,reference:liveReference,calibration:item.calibration,threshold:item.threshold,referenceCalibration:item.referenceCalibration)!
            print("Live L15",item.expected,seen.signature[item.point])
            precondition(seen.signature[item.point]==item.expected,"Actual live L15 placement regression")
        }
        print("PASS: recorded glare creates no stones; six photographed-stone transfers remain detectable; actual live L15 Empty → White → Empty")
    }
}
