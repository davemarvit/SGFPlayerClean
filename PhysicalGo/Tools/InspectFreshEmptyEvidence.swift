@testable import PhysicalGoTestRuntime
import Foundation
import CoreGraphics
import ImageIO

@main struct PixelReceiptTests {
    struct Meta:Decodable {
        struct Frame:Decodable {let capturedAtUptime:Double;let frameID:Int;let streamEpoch:String}
        let currentCalibration:BoardCalibration;let referenceCalibration:BoardCalibration;let frame:Frame
    }
    static func main() throws {
        setbuf(stdout,nil)
        let args=CommandLine.arguments
        let m=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        func image(_ path:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!,0,nil)!}
        let original=image(args[2]),frame=GrayFrame(image:original)!,reference=GrayFrame(image:image(args[3]))!,cal=m.currentCalibration
        var checks=0,failures=[String]()
        func check(_ condition:Bool,_ message:String) {checks+=1;if !condition {failures.append(message);print("FAIL",message)}}
        func detect(_ f:GrayFrame)->BoardObservation {
            var o=BoardDetector.detect(frame:f,reference:reference,calibration:cal,threshold:0.13,referenceCalibration:m.referenceCalibration,capturedAt:m.frame.capturedAtUptime)!
            o.handObstructed=false;return o
        }
        // Spatial eligibility experiment only: no temporal clocks/driver and
        // no claim these repeated saved pixels are independent fresh frames.
        func eligible(_ o:BoardObservation,expected:[String],color:String,useReceipt:Bool)->Int? {
            guard o.handObstructed==false,!o.lightingBlocked else {return nil}
            let offsets=o.assignmentOffsets(confirmedBoard:expected.map{Occupancy(rawValue:$0)!})
            let ambiguous=Set(offsets.filter{$0.value>=0.30}.map(\.key))
            for r in o.readings where r.occupancy.stone != nil && r.confidence>=0.8 {
                let point=r.row*o.size+r.col
                guard r.occupancy.rawValue != expected[point] else {continue}
                if ambiguous.contains(point) {return nil}
                for row in max(0,r.row-1)...min(o.size-1,r.row+1) {for col in max(0,r.col-1)...min(o.size-1,r.col+1) {
                    let p=row*o.size+col,neighbor=o.readings[p]
                    if p != point && expected[p]=="empty" && (neighbor.occupancy == .uncertain || neighbor.confidence<0.8),
                       !(useReceipt && neighbor.occupancy == .empty && o.hasFreshEmptyCrossingEvidence(at:p)) {return nil}
                }}
            }
            let values=o.readings.enumerated().map { p,r in
                r.occupancy == .uncertain || r.confidence<0.8 || ambiguous.contains(p) ? expected[p]:r.occupancy.rawValue
            }
            return PhysicalMoveInference.candidate(board:expected,observed:values,size:o.size,color:color)
        }
        let baseline=detect(frame)
        // Explicitly synthesized prior position for this one-frame spatial
        // experiment; the original delayed controller checkpoint is unavailable.
        // This does not replay history, clocks, or independent temporal witnesses.
        var expected=baseline.readings.map {$0.occupancy.stone != nil && $0.confidence>=0.8 ? $0.occupancy.rawValue:"empty"}
        expected[41]="empty"
        check(eligible(baseline,expected:expected,color:"black",useReceipt:false)==nil,"Blanketgate must reproduce retained41 ineligibility")
        check(eligible(baseline,expected:expected,color:"black",useReceipt:true)==41,"Actualsameframe59 proof must restore41 spatialeligibility")
        check(eligible(baseline,expected:expected,color:"white",useReceipt:true)==nil,"Expectedturn must not acceptwrongcolor")
        check(baseline.hasFreshEmptyCrossingEvidence(at:59),"retained59 must have its actual positive referencewood receipt")
        print("SOURCE_FRAME",m.frame.streamEpoch,m.frame.frameID,m.frame.capturedAtUptime)
        print("BASE59",baseline.readings[59],String(describing:baseline.emptyCrossingEvidence[59]))
        let old=PhysicalGoTestRuntime.BoardDetector.detect(frame:frame,reference:reference,calibration:cal,threshold:0.13,referenceCalibration:m.referenceCalibration)!
        check(old.readings==baseline.readings,"receipt producer must preserve all361 classifier readings")
        let omitted=BoardDetector.detect(frame:frame,reference:reference,calibration:cal,threshold:0.13,referenceCalibration:m.referenceCalibration)!
        check(omitted.emptyCrossingEvidence.isEmpty,"missing original capturetime must emit no receipts")
        var rgba=[UInt8](repeating:0,count:frame.width*frame.height*4)
        rgba.withUnsafeMutableBytes {raw in
            let ctx=CGContext(data:raw.baseAddress,width:frame.width,height:frame.height,bitsPerComponent:8,bytesPerRow:frame.width*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(original,in:CGRect(x:0,y:0,width:frame.width,height:frame.height))
        }
        struct Cover {let name:String;let c,r,radius:Double;let color:[UInt8]}
        let covers=[
            Cover(name:"partial-black",c:2,r:3,radius:0.22,color:[20,20,20]),
            Cover(name:"black",c:2,r:3,radius:0.46,color:[20,20,20]),
            Cover(name:"neutral-gray",c:2,r:3,radius:0.46,color:[140,140,140]),
            Cover(name:"white-glare",c:2,r:3,radius:0.46,color:[235,235,235]),
            Cover(name:"wood-colored-cover",c:2,r:3,radius:0.46,color:[190,188,177]),
            Cover(name:"halfway-black",c:1.5,r:3,radius:0.43,color:[20,20,20]),
            Cover(name:"halfway-white",c:1.5,r:3,radius:0.43,color:[235,235,235]),
            Cover(name:"diagonal-black",c:1.5,r:3.5,radius:0.43,color:[20,20,20]),
            Cover(name:"diagonal-white",c:1.5,r:3.5,radius:0.43,color:[235,235,235])]
        for cover in covers {
            var pixels=frame.pixels,colors=rgba
            let center=cal.point(col:cover.c,row:cover.r),cx=Int(center.x*Double(frame.width-1)),cy=Int(center.y*Double(frame.height-1))
            for y in max(0,cy-35)...min(frame.height-1,cy+35) {for x in max(0,cx-35)...min(frame.width-1,cx+35) {
                let g=cal.gridPoint(for:.init(x:Double(x)/Double(frame.width-1),y:Double(y)/Double(frame.height-1)))!
                if hypot(g.x-cover.c,g.y-cover.r)<=cover.radius {
                    let p=y*frame.width+x;pixels[p]=UInt8(cover.color.map(Int.init).reduce(0,+)/3)
                    for k in 0..<3 {colors[p*4+k]=cover.color[k]}
                }
            }}
            let altered=GrayFrame(width:frame.width,height:frame.height,pixels:pixels,colorBytes:colors)
            let o=detect(altered),receipt=o.hasFreshEmptyCrossingEvidence(at:59)
            print("CONTROL",cover.name,"59",o.readings[59],"receipt",receipt,"rawReceipt",o.emptyCrossingEvidence[59] != nil,"nearby",o.readings.filter{abs($0.col-2)<=1 && abs($0.row-3)<=1 && $0.occupancy != .empty})
            check(eligible(o,expected:expected,color:"black",useReceipt:true)==nil,"\(cover.name) must not authorize target41 while competing/extra object is present")
            // The opaque center/axial-halfway cases cover or compete for59.
            // A diagonal disk may leave59 physically clear; inspect all its
            // competing readings separately instead of calling that a failure.
            if !cover.name.hasPrefix("diagonal") {check(!receipt,"\(cover.name) must not certify59 empty")}
        }
        struct Archived:Decodable {
            struct Sample:Decodable {let capturedAt:Double;let readings:[IntersectionReading];let footprints:[StoneFootprint];let placementFits:[StoneFootprint]}
            let validMovesBefore:[Int];let ambiguousMovesBefore:[Int]
            let validFrames:[Sample];let ambiguousFrames:[Sample]
        }
        let archived=try JSONDecoder().decode(Archived.self,from:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIAmbiguousPlacement/observations.json")))
        func board(_ moves:[Int])->[String] {
            var result=Array(repeating:"empty",count:361)
            for (i,p) in moves.enumerated() {result=PhysicalMoveInference.position(after:p,board:result,size:19,color:i%2==0 ? "black":"white")!}
            return result
        }
        for sample in archived.ambiguousFrames {
            let o=BoardObservation(readings:sample.readings,size:19,footprints:sample.footprints,placementFits:sample.placementFits,capturedAt:sample.capturedAt,handObstructed:false)
            check(eligible(o,expected:board(archived.ambiguousMovesBefore),color:"white",useReceipt:true)==nil,"Recordedhalfway275/294 must remain unresolved; metadata cannot invent a receipt")
        }
        for sample in archived.validFrames {
            let o=BoardObservation(readings:sample.readings,size:19,footprints:sample.footprints,placementFits:sample.placementFits,capturedAt:sample.capturedAt,handObstructed:false)
            check(eligible(o,expected:board(archived.validMovesBefore),color:"white",useReceipt:true)==180,"RecordedlegitimateWhite180 must remain eligible")
        }
        print("RESULT",checks,"checks",failures.count,"failures")
        if !failures.isEmpty {throw NSError(domain:"PixelReceiptTests",code:1,userInfo:[NSLocalizedDescriptionKey:failures.joined(separator:"; ")])}
    }
}
