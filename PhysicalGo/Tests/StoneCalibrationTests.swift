import AppKit
import Foundation
import ImageIO
import SwiftUI

@main struct StoneCalibrationTests {
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("StoneCalibrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {print("FAIL: \(message)");exit(1)}}
        func wait(_ ready:()->Bool) {
            let deadline=Date().addingTimeInterval(15)
            while !ready() && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
            check(ready(),"Async calibration completion timed out")
        }
        for n in [9,13,19] {
            let first=StoneCalibrationPattern.stones(size:n,round:0),second=StoneCalibrationPattern.stones(size:n,round:1)
            check(first.count==6 && first.values.filter{$0 == .black}.count==3 && first.values.filter{$0 == .white}.count==3,"Three stones of each color")
            check(Set(first.keys)==Set(second.keys) && first.allSatisfy{second[$0.key] != $0.value},"Both colors must sample every location")
            check(first[n/2*n+n/2]?.stone != nil && first[n/2*n+n/2+1]?.stone != nil,"Touching pair")
            let labels=StoneCalibrationPattern.labels(size:n,round:0)
            check(labels.count>6 && labels.count<n*n && first.allSatisfy{labels[$0.key]==$0.value},"Explicit sample labels with adjacent empties")
            for p in labels.keys {check((0..<n*n).contains(p),"Label bounds")}
        }
        check(StoneCalibrationPattern.stones(size:7,round:0).isEmpty,"Reject unsupported board")
        let open=StoneNeighborContext(black:0,white:0,unknown:0)
        let shadow=StoneNeighborContext(black:2,white:0,unknown:0)
        var examples=[StoneAppearanceModel.Example]()
        let vectors:[Occupancy:[Double]]=[.empty:[0,0.02,0,0.08,0],.black:[-0.5,0.03,-0.04,0,-0.1],.white:[0.3,0.03,-0.04,0,0.1]]
        for label in [Occupancy.empty,.black,.white] {for i in 0..<6 {
            examples.append(.init(point:i,label:label,features:.init(values:vectors[label]!,woodLevel:0.6),context:open))
        }}
        let profile=StoneAppearanceModel(examples:examples)!
        for label in [Occupancy.empty,.black,.white] {
            check(profile.predict(.init(values:vectors[label]!,woodLevel:0.6)).label==label,"Separable known appearance")
        }
        check(profile.predict(.init(values:Array(repeating:2,count:5),woodLevel:0.6)).label == .uncertain,"Unseen appearance abstains")
        check(profile.predict(.init(values:[.nan],woodLevel:0.6)).label == .uncertain,"Malformed measurement abstains")
        check(StoneAppearanceModel(examples:Array(examples.prefix(2)))==nil,"Missing classes cannot form calibration")
        let ambiguous=StoneAppearanceModel(examples:examples.map{.init(point:$0.point,label:$0.label,features:.init(values:vectors[.empty]!,woodLevel:0.6))})!
        check(ambiguous.predict(.init(values:vectors[.empty]!,woodLevel:0.6)).label == .uncertain,"Overlapping classes abstain")
        for i in 0..<3 {examples.append(.init(point:i,label:.empty,features:.init(values:[-0.14,0.02,0,0.08,0],woodLevel:0.6),context:shadow))}
        let contextual=StoneAppearanceModel(examples:examples)!
        check(contextual.components.allSatisfy{$0.distribution.label == .empty},"Neighbor models apply only to empties")
        check(contextual.distribution(for:.empty,context:shadow)!.center[0] < -0.1,"Shaded empty range is separate")
        check(contextual.distribution(for:.black,context:shadow)!.center==contextual.distribution(for:.black,context:open)!.center,"Black is not context conditioned")
        check(contextual.distribution(for:.white,context:shadow)!.center==contextual.distribution(for:.white,context:open)!.center,"White is not context conditioned")
        check(contextual.distribution(for:.empty,context:.unknown)!.center==contextual.distributions[0].center,"Unknown neighborhood uses pooled empty range")
        let known=[0:Occupancy.black,1:.white,9:.empty]
        let corner=StoneNeighborContext.measure(point:0,size:9,known:known)
        check(corner.white==1 && corner.unknown==1 && corner.group=="unknown","Outside-board positions do not count; missing labels remain unknown")

        let n=9
        let cal=BoardCalibration(size:n,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        func picture(_ stones:[Int:Occupancy])->CGImage {
            let context=CGContext(data:nil,width:600,height:600,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red:0.78,green:0.65,blue:0.45,alpha:1));context.fill(CGRect(x:0,y:0,width:600,height:600))
            context.setStrokeColor(CGColor(gray:0.1,alpha:1));context.setLineWidth(2)
            for i in 0..<n {
                let p=60+Double(i)*60
                context.move(to:.init(x:60,y:p));context.addLine(to:.init(x:540,y:p))
                context.move(to:.init(x:p,y:60));context.addLine(to:.init(x:p,y:540))
            };context.strokePath()
            for (point,label) in stones {
                let p=cal.point(col:Double(point%n),row:Double(point/n))
                context.setFillColor(CGColor(gray:label == .black ? 0.08:0.96,alpha:1))
                context.fillEllipse(in:CGRect(x:p.x*600-25,y:600-p.y*600-25,width:50,height:50))
            }
            return context.makeImage()!
        }
        let empty=picture([:]),ref=GrayFrame(image:empty)!
        var session=StoneCalibrationSession(id:UUID(),size:n,quarterTurns:3,cameraID:"fixture",originalReference:empty)
        for stage in 0..<3 {
            let stones=stage==0 ? [:] : StoneCalibrationPattern.stones(size:n,round:stage-1)
            let image=picture(stones)
            let readings=(0..<n*n).map{IntersectionReading(row:$0/n,col:$0%n,occupancy:.uncertain,confidence:0,delta:0)}
            let photo=StoneCalibrationPhoto(id:UUID(),capturedAt:Date(),image:image,calibration:cal,readings:readings,labels:session.labels,stage:stage)
            session.photos.append(photo)
            let folder=try StoneCalibrationArchive.save(photo:photo,session:session,root:root)
            let again=try StoneCalibrationArchive.save(photo:photo,session:session,root:root)
            check(folder==again,"Idempotent retry")
            let saved=folder.appendingPathComponent(photo.id.uuidString)
            let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:saved.appendingPathComponent("capture.json"))) as! [String:Any]
            check((metadata["labels"] as! [[String:Any]]).count==photo.labels.count,"Archive only explicit labels")
            check((metadata["rawReadings"] as! [[String:Any]]).allSatisfy{$0["occupancy"] as? String=="uncertain"},"Preserve raw uncertain readings separately from labels")
            let source=CGImageSourceCreateWithURL(saved.appendingPathComponent("camera.png") as CFURL,nil)!
            check(GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!.pixels==GrayFrame(image:image)!.pixels,"Lossless photographic evidence")
        }
        let measured=session.examples()
        check(measured.filter{$0.label == .black}.count==6 && measured.filter{$0.label == .white}.count==6,"Both rounds yield six real photographic examples per stone color")
        check(measured.allSatisfy{$0.context.unknown==0},"User-confirmed full diagram gives known surroundings")
        let fitted=StoneAppearanceModel(examples:measured)!
        for row in measured {check(fitted.predict(row.features,context:row.context).label==row.label,"Synthetic photographic calibration separates every sample: \(row.label)")}
        try StoneCalibrationArchive.saveProfile(fitted,session:session,root:root)
        check(FileManager.default.fileExists(atPath:root.appendingPathComponent(session.id.uuidString).appendingPathComponent("profile.json").path),"Persist profile linked to source captures")
        let invalid=root.appendingPathComponent("not-a-directory");try Data([1]).write(to:invalid)
        do {_ = try StoneCalibrationArchive.save(photo:session.photos[0],session:session,root:invalid);fatalError("Expected archive failure")}catch{}
        check(StoneAppearanceFeatures.extract(frame:ref,reference:ref,calibration:cal,referenceCalibration:cal,point:n*n)==nil,"Reject invalid intersection")

        let defaults=UserDefaults(suiteName:"StoneCalibrationTests-\(UUID().uuidString)")!
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil,settings:defaults,diagnosticRoot:root)
        model.soundMode = .off;model.tracksCameraMotion=false
        model.size=n;model.calibration=cal;model.image=empty;model.cameraID="fixture"
        model.captureReference()
        wait {model.observation != nil}
        model.stoneCalibrationArchiveRoot=root.appendingPathComponent("workflow")
        check(!model.canBeginStoneCalibration,"No stale/offline frame can begin calibration")
        model.beginStoneCalibration();check(model.stoneCalibrationSession==nil,"Start guard")
        var workflow=StoneCalibrationSession(id:UUID(),size:n,quarterTurns:model.viewQuarterTurns,cameraID:"fixture",originalReference:model.referenceImage!)
        workflow.pending=session.photos[0];model.stoneCalibrationSession=workflow
        check(model.stoneCalibrationContextValid,"Matching context")
        model.confirmStoneCalibrationPhoto();wait {!model.savingStoneCalibration}
        check(model.stoneCalibrationSession?.stage==1 && model.stoneAppearanceProfile==nil,"Confirmed photo advances only after saving, no partial profile")
        model.stoneCalibrationSession?.pending=session.photos[1]
        model.stoneCalibrationArchiveRoot=invalid
        model.confirmStoneCalibrationPhoto();wait {!model.savingStoneCalibration}
        check(model.stoneCalibrationSession?.stage==1 && model.stoneCalibrationSession?.pending != nil && !model.stoneCalibrationError.isEmpty,"Failure preserves pending photo and stage")
        model.cameraID="changed";check(!model.stoneCalibrationContextValid,"Camera change invalidates calibration")
        model.confirmStoneCalibrationPhoto();check(!model.savingStoneCalibration,"Changed camera cannot confirm stale photo")
        model.closeStoneCalibration();check(model.stoneCalibrationSession==nil,"Cancel closes workflow")
        check(FileManager.default.fileExists(atPath:root.appendingPathComponent("workflow").appendingPathComponent(workflow.id.uuidString).path),"Cancel preserves confirmed training photo")
        // Render the actual preview: a non-square image exposes both wrong-sign
        // rotation and aspect-fit clipping. Every marker follows the game's transform.
        let markerContext=CGContext(data:nil,width:400,height:200,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        markerContext.setFillColor(CGColor(gray:0,alpha:1));markerContext.fill(CGRect(x:0,y:0,width:400,height:200))
        markerContext.setFillColor(CGColor(gray:1,alpha:1));markerContext.fill(CGRect(x:70,y:130,width:20,height:20))
        let markerImage=markerContext.makeImage()!
        for turns in 0..<4 {
            let renderer=ImageRenderer(content:CalibrationCameraPreview(image:markerImage,turns:turns).frame(width:200,height:200))
            renderer.scale=1
            let rendered=GrayFrame(image:renderer.cgImage!)!
            let orientation=BoardOrientation(turns),p=orientation.display(.init(x:0.2,y:0.3))
            let displayed=orientation.swapsDimensions ? ImagePoint(x:0.25+p.x*0.5,y:p.y):ImagePoint(x:p.x,y:0.25+p.y*0.5)
            check((rendered.patchMean(displayed) ?? 0)>0.85,"Camera preview must match game/target orientation at turn \(turns)")
        }
        let workflowFolder=root.appendingPathComponent("workflow").appendingPathComponent(workflow.id.uuidString)
        let restored=try StoneCalibrationArchive.load(folder:workflowFolder,reference:empty,cameraID:"fixture",calibration:cal,turns:workflow.quarterTurns)
        check(restored.stage==1 && restored.pending==nil && restored.photos[0].labels==session.photos[0].labels,"Resume only confirmed empty photo, preserving raw labels")
        check(restored.originalReference === empty,"Resume binds to verified current reference")
        check(StoneCalibrationArchive.latestIncomplete(root:root.appendingPathComponent("workflow"))?.resolvingSymlinksInPath().path==workflowFolder.resolvingSymlinksInPath().path,"Find saved unfinished session")
        do {_ = try StoneCalibrationArchive.load(folder:workflowFolder,reference:empty,cameraID:"other camera",calibration:cal,turns:workflow.quarterTurns);fatalError("Wrong camera accepted")}catch{}
        do {_ = try StoneCalibrationArchive.load(folder:workflowFolder,reference:empty,cameraID:"fixture",calibration:cal,turns:(workflow.quarterTurns+1)%4);fatalError("Wrong orientation accepted")}catch{}
        let occupied=picture(StoneCalibrationPattern.stones(size:n,round:0))
        let shifted=BoardCalibration(size:n,corners:cal.corners.map{ImagePoint(x:$0.x+0.02,y:$0.y)})!
        do {_ = try StoneCalibrationArchive.load(folder:workflowFolder,reference:occupied,cameraID:"fixture",calibration:shifted,turns:workflow.quarterTurns);fatalError("Changed grid accepted")}catch{}
        print("PASS: \(checks) stone-calibration checks: patterns, separate empty contexts, unknown neighbors, out-of-range/ambiguous abstention, real image features, explicit labels, lossless archive, retry/failure/cancel, context and freshness guards")
    }
}
