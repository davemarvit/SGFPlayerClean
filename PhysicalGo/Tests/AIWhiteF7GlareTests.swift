import Foundation
import ImageIO

@main struct AIWhiteF7GlareTests {
    struct Meta:Decodable {let currentCalibration:BoardCalibration;let referenceCalibration:BoardCalibration}
    static func main() throws {
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIWhiteF7Glare")
        func data(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
        func photo(_ name:String)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!}
        let meta=try JSONDecoder().decode(Meta.self,from:data("frame.json"))
        let stored=try JSONDecoder().decode(OccupiedReference.self,from:data("reference.json"))
        let empty=photo("empty.png")
        for name in ["before-f7.png","board.png"] {
            let frame=photo(name)
            let raw=BoardDetector.detect(frame:frame,reference:empty,calibration:meta.currentCalibration,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
            var reference=stored,result=raw
            for i in 0..<8 {
                result=reference.observe(raw,independent:raw,frame:frame,calibration:meta.currentCalibration,expected:stored.position,identity:stored.identity,now:100+Double(i)*0.2,valid:true,allowRefresh:false)
                for p in result.readings.indices where stored.position[p] == .empty && (p != 259 || name=="before-f7.png") {precondition(result.readings[p].occupancy != .white,"Invented White on a known empty intersection: \(p)")}
                if name=="before-f7.png" {precondition(result.readings[259].occupancy != .white,"Empty glare became F7 White")}
                if name=="board.png" && i==0 {precondition(result.readings[259].occupancy != .white,"Single uncertain frame accepted White")}
            }
            if name=="board.png" {
                precondition(raw.coveredGridPoints.contains(259),"Reference ink disappearance was lost")
                precondition(result.readings[259].occupancy == .white && result.readings[259].confidence>=0.9,"Visible F7 not recovered")
                // Same weak photometric evidence without the independent
                // before/after grid proof must not acquire the new label.
                var noGrid=raw;noGrid.coveredGridPoints=[];reference=stored
                for i in 0..<8 {
                    let rejected=reference.observe(noGrid,independent:noGrid,frame:frame,calibration:meta.currentCalibration,expected:stored.position,identity:stored.identity,now:100+Double(i)*0.2,valid:true,allowRefresh:false)
                    precondition(rejected.readings[259].occupancy != .white,"Missing grid-change proof was bypassed")
                }
            }
        }
        print("PASS: photographed F7, empty glare, temporal evidence and missing-grid-proof rejection")
    }
}
