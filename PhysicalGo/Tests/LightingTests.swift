import Foundation
import CoreGraphics
import ImageIO
import CoreImage

@main struct LightingTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        struct Meta:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration?;let threshold:Double}
        for name in ["EdgeStones","ReferenceOffset","CameraBump"] {
            let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/"+name)
            let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            func load(_ file:String)->GrayFrame {
                let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(file) as CFURL,nil)!
                return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
            }
            let frame=load("frame.png"),reference=load("empty-reference.png"),base=meta.referenceCalibration ?? meta.calibration
            let anchor=AutoGridDetector.trackingAnchor(frame:reference,calibration:base)!
            let cal=AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor)!
            let original=BoardDetector.detect(frame:frame,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:base)!
            let expected=original.snapshot.stones
            check(expected.count == (name=="EdgeStones" ? 2:name=="ReferenceOffset" ? 20:16),"Baseline lost a known stone")
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL,nil)!
            let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
            var colors=[UInt8](repeating:0,count:frame.width*frame.height*4)
            colors.withUnsafeMutableBytes {bytes in
                let context=CGContext(data:bytes.baseAddress,width:frame.width,height:frame.height,bitsPerComponent:8,
                    bytesPerRow:frame.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                    bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:frame.width,height:frame.height))
            }
            for (label,start,slope) in [("uniform dim",0.60,0.0),("gradient dim",0.45,0.35),("reverse gradient",0.80,-0.30),("brighter",1.18,0.0)] {
                var pixels=frame.pixels,shiftedColors=colors
                for i in pixels.indices {
                    let gain=start+slope*Double(i%frame.width)/Double(frame.width-1)
                    pixels[i]=UInt8(min(255,(Double(pixels[i])*gain).rounded()))
                    for channel in 0..<3 {shiftedColors[i*4+channel]=UInt8(min(255,(Double(colors[i*4+channel])*gain).rounded()))}
                }
                let changed=GrayFrame(width:frame.width,height:frame.height,pixels:pixels,colorBytes:shiftedColors)
                let result=BoardDetector.detect(frame:changed,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:base)!
                let missing=expected.filter {result.snapshot.stones[$0.key] != $0.value}.count
                let falseStones=result.snapshot.stones.filter {expected[$0.key] != $0.value}.count
                print("\(name) / \(label): \(missing) missing, \(falseStones) added, \(result.signature.filter{$0 == .uncertain}.count) uncertain; \(result.notice ?? "normal")")
                check(!result.lightingBlocked,"Readable altered photo blocked: \(name) / \(label)")
                check(falseStones==0,"Lighting invented stones: \(name) / \(label)")
                check(missing==0,"Lighting lost a stone: \(name) / \(label)")
                check(AutoGridDetector.track(frame:changed,from:cal,anchor:anchor)==cal,"Exposure change became a camera nudge: \(name) / \(label)")
            }
            for value:UInt8 in [0,255] {
                let unreadable=GrayFrame(width:frame.width,height:frame.height,pixels:Array(repeating:value,count:frame.pixels.count))
                check(LightingCompensation.exposureFailure(frame:unreadable,calibration:cal),"Dark or clipped frame not blocked")
                check(AutoGridDetector.track(frame:unreadable,from:cal,anchor:anchor)==nil,"Blank frame verified as a grid")
            }
            check(!LightingCompensation.exposureFailure(frame:frame,calibration:cal),"Ordinary photo marked unreadable")
            if name=="CameraBump" {
                let input=CIImage(cgImage:image),context=CIContext()
                let moved=context.createCGImage(input.transformed(by:CGAffineTransform(translationX:8,y:6)),from:input.extent)!
                let dimmed=GrayFrame(image:moved)!.scaledLuminance(by:0.6)
                let found=AutoGridDetector.track(frame:dimmed,from:cal,anchor:anchor)
                check(found != nil,"Combined dimming and camera movement failed to recover")
                for (old,new) in zip(cal.corners,found!.corners) {
                    check(hypot((new.x-old.x)*Double(frame.width-1)-8,(new.y-old.y)*Double(frame.height-1)+6)<4,
                          "Lighting compensation hid a real camera shift")
                }
            }
        }
        let square=BoardCalibration(size:19,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        var clean=[LightingCompensation.Sample](),irregular=[LightingCompensation.Sample]()
        for y in 0..<9 {for x in 0..<9 {
            let point=ImagePoint(x:0.12+Double(x)*0.09,y:0.12+Double(y)*0.09)
            clean.append(.init(point:point,current:0.6/(1.1+0.3*point.x),reference:0.6))
            irregular.append(.init(point:point,current:(x+y)%2==0 ? 0.2:0.8,reference:0.6))
        }}
        let fitted=LightingCompensation.fit(clean,calibration:square)
        check(fitted != nil && abs(fitted!.gain(at:.init(x:0.5,y:0.5))-1.25)<0.001,"Known exposure plane not recovered")
        check(LightingCompensation.fit(irregular,calibration:square)==nil,"Irregular obstruction was treated as smooth exposure")
        var recovery=LightingRecovery()
        check(recovery.update(blocked:true,fresh:true,now:0,speech:true)==nil && recovery.active,"Immediate silent interruption missing")
        check(recovery.update(blocked:true,fresh:true,now:2,speech:true)==nil,"Brief exposure change spoke")
        check(recovery.update(blocked:true,fresh:true,now:3,speech:true) == nil && !recovery.needsHelp,"Brief obstruction triggered lighting advice")
        check(recovery.update(blocked:true,fresh:true,now:8,speech:true) != nil && recovery.needsHelp,"Persistent failure did not speak")
        check(recovery.update(blocked:true,fresh:true,now:9,speech:true)==nil,"Repeated speech in same episode")
        _=recovery.update(blocked:false,fresh:false,now:10,speech:true)
        check(recovery.active,"Redraw cleared recovery")
        for now in [10.0,10.3] {_=recovery.update(blocked:false,fresh:true,now:now,speech:true)}
        check(recovery.active,"Recovered before enough clear frames")
        _=recovery.update(blocked:false,fresh:true,now:10.7,speech:true)
        check(!recovery.active && !recovery.needsHelp,"Clear frames failed to recover")
        _=recovery.update(blocked:true,fresh:true,now:12,speech:true)
        check(recovery.update(blocked:true,fresh:true,now:15,speech:true)==nil,"Flicker bypassed cooldown")
        check(recovery.update(blocked:true,fresh:true,now:37,speech:false)==nil,"Disabled voice spoke")
        check(recovery.update(blocked:true,fresh:true,now:38,speech:true) != nil,"Re-enabled voice stayed silent")
        for now in [39.0,39.3,41.0,41.3] {_=recovery.update(blocked:false,fresh:true,now:now,speech:true)}
        check(recovery.active,"Camera gap counted as stable recovery")
        _=recovery.update(blocked:false,fresh:true,now:41.7,speech:true)
        check(!recovery.active,"Fresh stable frames failed to recover after gap")
        print("PASS: \(checks) lighting checks")
    }
}
