import Foundation
import ImageIO
import CoreImage

@main struct AIWhiteS4PlacementTests {
    struct Meta:Decodable {let currentCalibration:BoardCalibration;let referenceCalibration:BoardCalibration}
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIWhiteS4Placement")
        func data(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
        func image(_ name:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!
        }
        let meta=try JSONDecoder().decode(Meta.self,from:data("frame.json"))
        let expected=try JSONDecoder().decode([Occupancy].self,from:data("expected.json"))
        let empty=GrayFrame(image:image("empty.png"))!,input=CIImage(cgImage:image("board.png")),context=CIContext()
        var checks=0
        func check(_ value:Bool,_ text:String) {checks+=1;if !value {print("FAIL: "+text);exit(1)}}
        for brightness in [-0.005,0,0.005] {
            let photo=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let raw=BoardDetector.detect(frame:GrayFrame(image:photo)!,reference:empty,calibration:meta.currentCalibration,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
            check(raw.readings[34].occupancy == .white && raw.readings[34].confidence>=0.95,"Photo lost White S4")
            check((raw.placementOffsets[34] ?? 0)>=0.30,"Fixture no longer contains the displaced S4 stone")
            check(raw.assignmentOffsets(confirmedBoard:expected)[34]==0,"Strong photographed S4 outline still blocked")
            check(raw.readings[15].occupancy != .white,"One physical stone was duplicated at T4")
            var conflict=raw
            conflict.placementFits.append(.init(row:1,col:15,center:.init(x:15,y:0.5),radiusCol:0.5,radiusRow:0.5,quality:1))
            check((conflict.assignmentOffsets(confirmedBoard:expected)[34] ?? 0)>=0.30,"Conflicting equal-distance outline was ignored")
        }
        print("PASS: \(checks) photographed S4 assignment, brightness and conflicting-outline checks")
    }
}
