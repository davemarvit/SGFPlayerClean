import AppKit
import SwiftUI
@main struct CorrectionPhotoOrientationTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let context=CGContext(data:nil,width:400,height:200,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray:0,alpha:1));context.fill(CGRect(x:0,y:0,width:400,height:200))
        let col=4,row=6,cx=Double(col)/18*400,cy=Double(row)/18*200
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:cx-8,y:200-cy-8,width:16,height:16))
        context.setFillColor(CGColor(gray:0.7,alpha:1));context.fill(CGRect(x:cx+25-5,y:200-cy-5,width:10,height:10))
        let image=context.makeImage()!
        let cal=BoardCalibration(size:19,corners:[.init(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)])!
        let observation=BoardObservation(readings:(0..<361).map{IntersectionReading(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},size:19)
        for turns in 0..<4 {
            let snapshot=BoardCorrectionSnapshot(id:UUID(),capturedAt:Date(),image:image,reference:nil,calibration:cal,referenceCalibration:nil,observation:observation,threshold:0.13,quarterTurns:turns,source:"fixture")
            let orientation=BoardOrientation(turns)
            for selected in [false,true] {
                let renderer=ImageRenderer(content:CorrectionPhoto(snapshot:snapshot,selection:selected ? row*19+col:nil).frame(width:200,height:200))
                renderer.scale=1
                let rendered=GrayFrame(image:renderer.cgImage!)!
                if selected {
                    precondition(rendered.patchMean(.init(x:0.5,y:0.5))!>0.85,"Selected cross lost center")
                    let offset=orientation.display(.init(x:0.5+25.0/180,y:0.5))
                    precondition(rendered.patchMean(offset)!>0.55,"Close-up rotated opposite the board")
                    precondition(rendered.patchMean(.init(x:1-offset.x,y:1-offset.y))!<0.3,"Close-up mirrored the marker")
                } else {
                    let p=orientation.display(.init(x:cx/400,y:cy/200))
                    let fitted=orientation.swapsDimensions ? ImagePoint(x:0.25+p.x*0.5,y:p.y):ImagePoint(x:p.x,y:0.25+p.y*0.5)
                    precondition(rendered.patchMean(fitted)!>0.85,"Full photo uses incorrect rotation or aspect fit")
                }
            }
        }
        print("PASS: actual correction photo renders all four game orientations, centered zoom, correctly rotated neighboring pixels, and non-square full-photo fit.")
    }
}
