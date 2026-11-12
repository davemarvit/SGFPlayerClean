import Foundation
import ImageIO
import CoreGraphics

enum ResidualGlareTests {
    struct Frame:Decodable {let image:String;let time:Double;let calibration:BoardCalibration;let readings:[IntersectionReading]}
    static func run() throws ->Int {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["PHYSICAL_GO_RESIDUAL_GLARE_FIXTURE"] ?? "PhysicalGo/Tests/Fixtures/ResidualGlare")
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("sequence.json")))
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        var position=[Occupancy](repeating:.empty,count:361)
        position[60] = .black;position[180] = .black;position[300] = .white
        var tracker=KnownEmptyLighting(),checks=0,outputs=[BoardObservation]()
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        for (index,item) in frames.enumerated() {
            let raw=BoardObservation(readings:item.readings,size:19),frame=GrayFrame(image:image(item.image))!
            let result=tracker.observe(raw,frame:frame,calibration:item.calibration,expected:position,
                context:"real residual glare",now:item.time,valid:true,appearanceThreshold:0.13)
            outputs.append(result)
            check(result.signature.enumerated().allSatisfy {$0.element.stone==nil || $0.element==position[$0.offset]},"Glare created an extra stone")
            if index<7 {check(result.signature[260] == .uncertain,"Current-image baseline skipped its temporal confirmation")}
        }
        for point in [260,279,54] {
            let before=frames.suffix(6).filter {$0.readings[point].occupancy == .uncertain}.count
            let after=outputs.suffix(6).filter {$0.signature[point] == .uncertain}.count
            print("Residual glare",point,"uncertain tail",before,"→",after)
            check(after==0,"Recorded O14/P14/C17 glare did not settle after independent current-image confirmation")
        }
        check(!tracker.report.appearanceConfirmed.isEmpty,"Current-image evidence provenance missing")
        // Synthetic transfers of photographed stone bodies challenge the learned
        // empties at all three reported points. These are not physical placements.
        let last=frames.last!,photo=image(last.image),cal=last.calibration
        for source in [60,300] {for point in [260,279,54] {
            let origin=cal.point(col:Double(source%19),row:Double(source/19))
            let crop=photo.cropping(to:CGRect(x:origin.x*Double(photo.width-1)-28,y:origin.y*Double(photo.height-1)-28,width:56,height:56))!
            let canvas=CGContext(data:nil,width:photo.width,height:photo.height,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            canvas.draw(photo,in:CGRect(x:0,y:0,width:photo.width,height:photo.height))
            let p=cal.point(col:Double(point%19),row:Double(point/19))
            let rect=CGRect(x:p.x*Double(photo.width-1)-28,y:(1-p.y)*Double(photo.height-1)-28,width:56,height:56)
            canvas.addEllipse(in:rect);canvas.clip();canvas.draw(crop,in:rect)
            let changed=GrayFrame(image:canvas.makeImage()!)!
            var readings=last.readings
            readings[point] = .init(row:point/19,col:point%19,occupancy:.uncertain,confidence:0,delta:0)
            let raw=BoardObservation(readings:readings,size:19)
            for coldStart in [false,true] {
                var candidateTracker=coldStart ? KnownEmptyLighting():tracker
                for step in 1...12 {
                    let result=candidateTracker.observe(raw,frame:changed,calibration:cal,expected:position,
                        context:"real residual glare",now:last.time+Double(step)*0.21,valid:true,appearanceThreshold:0.13)
                    check(result.signature[point] == .uncertain,"Local appearance learned a new photographed stone as empty")
                }
            }
        }}
        print("PASS: \(checks) residual-glare checks with distinct recorded frames and explicit synthetic new-stone challenges")
        return checks
    }
}
