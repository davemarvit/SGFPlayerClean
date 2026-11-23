import Foundation
import ImageIO
import CoreGraphics

@main struct CrowdedEmptyTargetTests {
    struct Meta:Decodable {let currentCalibration,referenceCalibration:BoardCalibration}
    static func main()throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedEmptyTarget")
        func photo(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let empty=GrayFrame(image:photo("empty.png"))!
        var checks=0
        func check(_ ok:Bool,_ text:String) {checks+=1;if !ok {fatalError(text)}}
        for suffix in ["","-1","-2","-3"] {
            let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:root.appendingPathComponent("frame\(suffix).json")))
            let original=photo("board\(suffix).png"),frame=GrayFrame(image:original)!,cal=meta.currentCalibration
            func detect(_ f:GrayFrame)->BoardObservation {
                BoardDetector.detect(frame:f,reference:empty,calibration:cal,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
            }
            for gain in [0.99,1,1.01] {
                let result=detect(frame.scaledLuminance(by:gain)),reading=result.readings[137]
                check(reading.occupancy == .empty && reading.confidence>=0.8,"Crowded M15 was not positively empty: \(suffix), gain \(gain), \(reading)")
                for (p,color) in [(118,Occupancy.white),(119,.black),(136,.black),(138,.white),(156,.black)] {
                    check(result.readings[p].occupancy == color,"Neighbor \(p) lost while resolving M15")
                }
            }
            let neighbors=detect(frame).footprints.filter{$0.row==8 && $0.col==4}
            check(neighbors.count==1,"Fixture lost its independently fitted overlapping neighbor")
            // Keep that neighbor and the surrounding photo unchanged. Cover
            // M15 with dark, neutral and pale bodies; neither its prior empty
            // state nor the neighboring outline may make a covered cross empty.
            var rgba=[UInt8](repeating:0,count:frame.width*frame.height*4)
            rgba.withUnsafeMutableBytes {raw in
                let ctx=CGContext(data:raw.baseAddress,width:frame.width,height:frame.height,bitsPerComponent:8,bytesPerRow:frame.width*4,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(original,in:CGRect(x:0,y:0,width:frame.width,height:frame.height))
            }
            let center=cal.point(col:4,row:7),cx=Int(center.x*Double(frame.width-1)),cy=Int(center.y*Double(frame.height-1))
            for (radius,level) in [(0.22,UInt8(20)),(0.46,20),(0.46,140),(0.46,235)] {
                var pixels=frame.pixels,colors=rgba
                for y in max(0,cy-45)...min(frame.height-1,cy+45) {for x in max(0,cx-45)...min(frame.width-1,cx+45) {
                    let g=cal.gridPoint(for:.init(x:Double(x)/Double(frame.width-1),y:Double(y)/Double(frame.height-1)))!
                    if hypot(g.x-4,g.y-7)<=radius {
                        let p=y*frame.width+x;pixels[p]=level
                        colors[p*4]=level;colors[p*4+1]=level;colors[p*4+2]=level
                    }
                }}
                let covered=GrayFrame(width:frame.width,height:frame.height,pixels:pixels,colorBytes:colors)
                check(BoardAppearanceDetector.exposedWoodConfidence(frame:covered,calibration:cal,col:4,row:7,shadowNeighbors:neighbors)==nil,"Neighbor mask authorized a covered inner body")
                check(detect(covered).readings[137].occupancy != .empty,"Covered M15 became empty: radius \(radius), level \(level)")
            }
        }
        print("PASS: \(checks) crowded empty-target checks across four photographed frames, lighting variation, surrounding stones and opaque covers")
    }
}
