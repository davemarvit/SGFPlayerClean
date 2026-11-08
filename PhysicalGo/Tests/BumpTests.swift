import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct BumpTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ condition:Bool,_ message:String) { checks += 1; if !condition { fatalError(message) } }
        struct Metadata:Decodable { let calibration:BoardCalibration; let referenceCalibration:BoardCalibration?; let threshold:Double }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CameraBump")
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func photo(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let image=photo("frame.png"),frame=GrayFrame(image:image)!,reference=GrayFrame(image:photo("empty-reference.png"))!
        let anchor=AutoGridDetector.trackingAnchor(frame:reference,calibration:meta.calibration)!
        let start=Date()
        guard let tracked=AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor) else { fatalError("Could not recover saved bump") }
        let elapsed=Date().timeIntervalSince(start)
        let original=BoardDetector.detect(frame:frame,reference:reference,calibration:meta.calibration,threshold:meta.threshold)!
        let result=BoardDetector.detect(frame:frame,reference:reference,calibration:tracked,threshold:meta.threshold,referenceCalibration:meta.calibration)!
        check(original.signature.filter{$0 == .uncertain}.count>200,"Fixture must reproduce the camera bump failure")
        check(result.signature.filter{$0 == .uncertain}.count<=5,"Alignment should remove widespread false uncertainty")
        let black=[(12,16),(13,16),(14,16),(15,15),(16,5),(16,13),(16,15),(17,14)]
        let white=[(13,17),(14,17),(15,3),(15,16),(16,7),(16,16),(17,15),(17,16)]
        for (r,c) in black { check(result.readings[r*19+c].occupancy == .black,"Lost black stone at \(r),\(c)") }
        for (r,c) in white { check(result.readings[r*19+c].occupancy == .white,"Lost white stone at \(r),\(c)") }
        check(result.snapshot.stones.count==16,"Recovery invented stones")
        check(result.readings[17*19+15].occupancy == .white,"Crowded white stone is now resolved with displaced ink coverage")
        check((result.positionSGF()==nil)==result.signature.contains(.uncertain),"Only a fully resolved sample may be exported as a certain position")
        let landmarks=[(502.0,63.0),(1481,48),(1616,1007),(404,1007)]
        for (p,expected) in zip(tracked.corners,landmarks) {
            check(hypot(p.x*1919-expected.0,p.y*1079-expected.1)<5,"Recovered grid missed independently estimated corner")
        }
        var repeated=tracked
        for _ in 0..<12 {
            guard let next=AutoGridDetector.track(frame:frame,from:repeated,anchor:anchor) else { fatalError("Tracking lost the unchanged board") }
            for (a,b) in zip(tracked.corners,next.corners) {
                check(hypot((a.x-b.x)*1919,(a.y-b.y)*1079)<2,"Repeated tracking drifted")
            }
            repeated=next
        }
        check(AutoGridDetector.track(frame:frame,from:repeated,anchor:anchor)==repeated,"Stationary frame should settle rather than keep jittering")

        for name in ["EdgeStones","WhiteEdgeOffset","CenterFlicker","AdjacentOffset"] {
            let path=folder.deletingLastPathComponent().appendingPathComponent(name)
            let m=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:path.appendingPathComponent("sample.json")))
            func load(_ name:String)->GrayFrame {
                let src=CGImageSourceCreateWithURL(path.appendingPathComponent(name) as CFURL,nil)!
                return GrayFrame(image:CGImageSourceCreateImageAtIndex(src,0,nil)!)!
            }
            let base=load("empty-reference.png"),now=load("frame.png")
            let a=AutoGridDetector.trackingAnchor(frame:base,calibration:m.calibration)!
            guard let c=AutoGridDetector.track(frame:now,from:m.calibration,anchor:a) else { fatalError("Tracker rejected previous successful sample: \(name)") }
            let original=BoardDetector.detect(frame:now,reference:base,calibration:m.calibration,threshold:m.threshold)!
            let current=BoardDetector.detect(frame:now,reference:base,calibration:c,threshold:m.threshold,referenceCalibration:m.calibration)!
            check(current.snapshot.stones==original.snapshot.stones,"Tracking changed accepted stones in \(name)")
            check(current.signature.filter{$0 == .uncertain}.count<=original.signature.filter{$0 == .uncertain}.count,"Tracking increased uncertainty in \(name)")
        }
                let context=CIContext(),input=CIImage(cgImage:image)
        // Small translations and rolls, with independently transformed landmarks.
        for (dx,dy,degrees) in [(8.0,-6.0,0.0),(-10,4,0),(0,0,0.3),(0,0,-0.3),(4,-3,0.25)] {
            let transform=CGAffineTransform(translationX:960+dx,y:540-dy)
                .rotated(by:degrees * .pi/180).translatedBy(x:-960,y:-540)
            let moved=context.createCGImage(input.transformed(by:transform),from:input.extent)!
            guard let found=AutoGridDetector.track(frame:GrayFrame(image:moved)!,from:tracked,anchor:anchor) else { fatalError("Lost small camera change \(dx),\(dy),\(degrees)") }
            for (old,new) in zip(tracked.corners,found.corners) {
                let expected=CGPoint(x:old.x*1919,y:(1-old.y)*1079).applying(transform)
                check(hypot(new.x*1919-expected.x,(1-new.y)*1079-expected.y)<4,"Small motion mapped to wrong grid location")
            }
        }
        // Regression for the occupied-board "Reacquiring grid" loop. The saved
        // current grid is already aligned, despite many covered projection peaks.
        let occupiedFolder=folder.deletingLastPathComponent().appendingPathComponent("OccupiedTracking")
        let occupiedMeta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:occupiedFolder.appendingPathComponent("sample.json")))
        func occupiedPhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(occupiedFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let occupied=occupiedPhoto("frame.png"),occupiedInput=CIImage(cgImage:occupied)
        let occupiedAnchor=AutoGridDetector.trackingAnchor(frame:GrayFrame(image:occupiedPhoto("empty-reference.png"))!,calibration:occupiedMeta.referenceCalibration!)!
        var current=occupiedMeta.calibration
        for (dx,dy,brightness) in [(0.0,0.0,0.0),(1,0,0),(-1,1,0),(0,-1,0),(0,0,0.01),(0,0,-0.01),(0,0,0)] {
            let changed=occupiedInput.transformed(by:CGAffineTransform(translationX:dx,y:dy))
                .applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness])
            let photo=context.createCGImage(changed,from:occupiedInput.extent)!
            guard let aligned=AutoGridDetector.track(frame:GrayFrame(image:photo)!,from:current,anchor:occupiedAnchor) else { fatalError("Occupied board fell back into reacquisition: \(dx),\(dy),\(brightness)") }
            for (a,b) in zip(aligned.corners,occupiedMeta.calibration.corners) {
                check(hypot((a.x-b.x)*1919,(a.y-b.y)*1079)<4,"Occupied tracking moved off the established grid")
            }
            current=aligned
        }
        let withoutReferenceAnchor=AutoGridDetector.trackingAnchor(frame:GrayFrame(image:occupied)!,calibration:occupiedMeta.calibration)!
        check(AutoGridDetector.track(frame:GrayFrame(image:occupied)!,from:occupiedMeta.calibration,anchor:withoutReferenceAnchor)==occupiedMeta.calibration,"Tracking an occupied start should not require an empty reference")
                let large=context.createCGImage(input.transformed(by:CGAffineTransform(translationX:60,y:0)),from:input.extent)!
        check(AutoGridDetector.track(frame:GrayFrame(image:large)!,from:tracked,anchor:anchor)==nil,"Large move must not slip by one grid column")
        let blurred=context.createCGImage(input.applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:8]),from:input.extent)!
        check(AutoGridDetector.track(frame:GrayFrame(image:blurred)!,from:tracked,anchor:anchor)==nil,"Blurred motion must pause detection")
        let blank=GrayFrame(width:1920,height:1080,pixels:Array(repeating:180,count:1920*1080))
        var report=[String:Any]()
        check(AutoGridDetector.track(frame:blank,from:tracked,anchor:anchor,report:{report=$0})==nil,"Obscured grid must not be trusted")
        check(report["rejectionReason"] as? String != nil,"Rejected tracking lost its reason")
        let support=report["initialSupport"] as! [String:Any]
        check(!(support["failedChecks"] as! [String]).isEmpty,"Line support failure lost its specific checks")
        check(support["borderMatches"] as? [Int] != nil && support["quadrantMatches"] as? [Int] != nil,"Distributed alignment evidence missing")
        _=try JSONSerialization.data(withJSONObject:report) // Includes nonfinite profile-error handling.
        var voice=BoardRecoveryPrompt()
        check(voice.update(recovering:true,needsHelp:false,enabled:true,now:0)==nil,"Short recovery unnecessarily interrupted players")
        check(voice.update(recovering:true,needsHelp:true,enabled:true,now:1) != nil,"Reframing did not produce voice prompt")
        check(voice.update(recovering:true,needsHelp:true,enabled:true,now:60)==nil,"Ongoing failure repeated voice prompt")
        _=voice.update(recovering:false,needsHelp:false,enabled:true,now:61)
        check(voice.update(recovering:true,needsHelp:true,enabled:true,now:62) != nil,"New recovery episode did not announce")
        _=voice.update(recovering:false,needsHelp:false,enabled:true,now:63)
        check(voice.update(recovering:true,needsHelp:true,enabled:true,now:64)==nil,"Recovery flicker spammed speech")
        check(voice.update(recovering:true,needsHelp:true,enabled:false,now:100)==nil,"Disabled recovery speech was ignored")
        check(voice.update(recovering:true,needsHelp:true,enabled:true,now:101) != nil,"Speech did not resume when enabled")
        var expected=[Occupancy](repeating:.empty,count:361)
        for (r,c) in black {expected[r*19+c] = .black}
        for (r,c) in white {expected[r*19+c] = .white}
        let landmarksEvidence=AutoGridDetector.landmarkEvidence(frame:frame,size:19,expected:expected) {tracked.point(col:$0,row:$1)}
        print("Stone landmark baseline: \(landmarksEvidence.matched)/16, distributed \(landmarksEvidence.distributed)")
        check(landmarksEvidence.supported,"Known stones did not support the saved board")
        let recovered=try AutoGridDetector.recover(image:large,size:19,previous:tracked,expected:expected)
        check(recovered.result != nil && recovered.usedStones,"Stone-guided recovery failed beyond the local tracker's movement limit: \(recovered.reason)")
        if let recovered=recovered.result {
            for (old,new) in zip(tracked.corners,recovered.calibration.corners) {
                check(hypot(new.x*1919-(old.x*1919+60),(new.y-old.y)*1079)<6,"Recovery assigned the wrong grid intersection")
            }
        }
        // A physical quarter-turn must preserve the old stone identities, not rotate the game.
        let rotatedCalibration=BoardCalibration(size:19,corners:Array(tracked.corners[1...])+[tracked.corners[0]])!
        var rotatedExpected=[Occupancy](repeating:.empty,count:361)
        for row in 0..<19 {for col in 0..<19 {rotatedExpected[row*19+col]=expected[col*19+(18-row)]}}
        let rotatedRecovery=try AutoGridDetector.recover(image:image,size:19,previous:nil,expected:rotatedExpected)
        check(rotatedRecovery.usedStones,"Recorded layout did not resolve quarter-turn orientation: \(rotatedRecovery.reason)")
        if let found=rotatedRecovery.result {
            for (a,b) in zip(found.calibration.corners,rotatedCalibration.corners) {check(hypot((a.x-b.x)*1919,(a.y-b.y)*1079)<6,"Quarter-turn recovery changed stone identities")}
        }
        // One stale captured stone and one extra move are tolerated; they cannot dictate alignment.
        var stale=expected;stale[0] = .black;stale[12*19+16] = .empty
        let tolerant=try AutoGridDetector.recover(image:large,size:19,previous:tracked,expected:stale)
        check(tolerant.usedStones,"One missing/new stone prevented recovery")
        let inverted=expected.map {$0 == .black ? Occupancy.white:$0 == .white ? .black:.empty}
        let wrong=try AutoGridDetector.recover(image:image,size:19,previous:tracked,expected:inverted)
        check(wrong.result==nil,"Wrong colors were accepted as known landmarks")
        let cropped=context.createCGImage(input.transformed(by:CGAffineTransform(translationX:500,y:0)),from:input.extent)!
        let cropRecovery=try AutoGridDetector.recover(image:cropped,size:19,previous:tracked,expected:expected)
        check(cropRecovery.result==nil && cropRecovery.needsFullBoard,"Cut-off board was accepted or failed to request reframing")
        let blankImage=context.createCGImage(CIImage(color:CIColor(red:0.7,green:0.7,blue:0.7)).cropped(to:input.extent),from:input.extent)!
        let absent=try AutoGridDetector.recover(image:blankImage,size:19,previous:tracked,expected:expected)
        check(absent.result==nil && absent.needsFullBoard,"Missing board did not request full-board view")
        print("PASS: \(checks) bump checks. Saved sample: 221 → \(result.signature.filter{$0 == .uncertain}.count) uncertain, 8 black + 8 white recognized, including the formerly uncertain crowded white stone. Local fit: \(elapsed) seconds.")
    }
}
