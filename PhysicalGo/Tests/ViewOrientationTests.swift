import Foundation
import CoreGraphics
import ImageIO

@main struct ViewOrientationTests {
    @MainActor static func main() throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        for rows in [false,true] {
            for current in -4...7 {
                let next=BoardViewOrientationPolicy.preferredTurns(current:current,longAxisRows:rows)
                check(rows != BoardOrientation(next).swapsDimensions,"Long axis must be vertical")
                check(BoardViewOrientationPolicy.preferredTurns(current:next,longAxisRows:rows)==next,"Automatic orientation must settle")
                let flipped=(next+2)%4
                check(BoardViewOrientationPolicy.preferredTurns(current:flipped,longAxisRows:rows)==flipped,"Player's seat choice must survive automatic checks")
            }
        }
        for automatic in [false,true] {for online in [false,true] {for recording in [false,true] {
            check(BoardViewOrientationPolicy.canAdjust(automatic:automatic,online:online,recording:recording)==(automatic && !online && !recording),"Session lock")
        }}}
        let suite="PhysicalGoViewOrientationTests-"+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let model=ExperimentModel(discoverCameras:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil,settings:settings)
        let width=1000,height=800
        let data=Data(repeating:170,count:width*height)
        model.image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:[],provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        func calibration(rows:Bool)->BoardCalibration {
            let w=rows ? 1.0:BoardRectifiedGeometry.longToShort,h=rows ? BoardRectifiedGeometry.longToShort:1.0
            let pitch=0.45,yaw=0.55
            let corners=[(-0.5,-0.5),(0.5,-0.5),(0.5,0.5),(-0.5,0.5)].map {u,v in
                let x=u*w,y=v*h
                let xx=cos(yaw)*x+sin(yaw)*sin(pitch)*y,yy=cos(pitch)*y,zz=3-sin(yaw)*x+cos(yaw)*sin(pitch)*y
                return ImagePoint(x:(499.5+1000*xx/zz)/999,y:(399.5+1000*yy/zz)/799)
            }
            return BoardCalibration(size:19,corners:corners)!
        }
        model.calibration=calibration(rows:false);model.estimateBoardAspect()
        check(model.aspectConfident && !model.rectifiedLongAxisRows,"Side-camera long axis detected")
        check(model.viewQuarterTurns==1,"Side view should turn 90 degrees clockwise automatically")
        model.flipView();check(model.viewQuarterTurns==3 && model.automaticViewOrientation,"Flip preserves automatic axis")
        model.estimateBoardAspect();check(model.viewQuarterTurns==3,"Seat selection must not snap back")
        model.rotateView();let manual=model.viewQuarterTurns
        check(!model.automaticViewOrientation,"Quarter-turn control gives user ownership")
        model.estimateBoardAspect();check(model.viewQuarterTurns==manual,"Manual rotation must not be overwritten")
        model.automaticViewOrientation=true
        check(model.viewQuarterTurns%2==1,"Explicitly re-enable automatic orientation")
        model.onlineBoard.enabled=true
        model.calibration=calibration(rows:true);let locked=model.viewQuarterTurns
        model.estimateBoardAspect();check(model.viewQuarterTurns==locked && model.orientationLocked,"Never auto-rotate a live online game")
        model.onlineBoard.enabled=false;model.orientBoardForPlayer()
        check(model.viewQuarterTurns%2==0,"End-camera view returns upright after unlock")
        model.recorder.start(size:19);let recorded=model.viewQuarterTurns
        model.calibration=calibration(rows:false);model.estimateBoardAspect()
        check(model.viewQuarterTurns==recorded && model.orientationLocked,"Never auto-rotate a recording")
        // Reproduce launch from the actual failing empty-board reference.
        let fixture=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/SideCameraEmpty")
        struct Metadata:Decodable {let calibration:BoardCalibration}
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:fixture.appendingPathComponent("sample.json")))
        let source=CGImageSourceCreateWithURL(fixture.appendingPathComponent("frame.png") as CFURL,nil)!
        let actualImage=CGImageSourceCreateImageAtIndex(source,0,nil)!
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:temp)}
        let archive=ReferenceArchive(url:temp.appendingPathComponent("reference.plist"))
        try archive.save(image:actualImage,referenceCalibration:meta.calibration,calibration:meta.calibration,cameraID:nil,cameraName:"Fixture")
        for turns in 0..<4 {
            settings.set(turns,forKey:"PhysicalGo.viewQuarterTurns")
            settings.set(true,forKey:"PhysicalGo.automaticViewOrientation")
            let launched=ExperimentModel(discoverCameras:false,restoreViewSettings:true,referenceArchive:archive,recordingStorage:nil,settings:settings,diagnosticRoot:temp)
            check(launched.aspectGridLineCount>=100 && !launched.rectifiedLongAxisRows,"Launch must resolve actual empty-board long side")
            check(launched.viewQuarterTurns%2==1,"Actual board must launch with physical long axis vertical")
        }
        print("PASS: \(checks) automatic viewing orientation checks: side/end cameras, clockwise correction, seat flip, manual override, online/recording locks")
    }
}
