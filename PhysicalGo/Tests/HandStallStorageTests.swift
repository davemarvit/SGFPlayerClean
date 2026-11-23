import Foundation
@main struct HandStallStorageTests {
    static func main() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("hand-stall-test-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let trace=AIRecognitionTrace(url:directory.appendingPathComponent("trace.json"))
        let frame=HandOutlineFrame(width:1,cells:1,pixels:[.init(red:0.1,green:0.02,light:0.6)])
        let checkpoint=HandOutlineTracker.Checkpoint(background:frame,active:true,edge:1,center:[0,0],direction:nil,appearance:nil)
        let evidence=HandOutlineTracker.StallEvidence(checkpoint:checkpoint,frame:frame,pose:.init(hands:[]),
            result:.init(obstructed:true,poseLost:true,reason:"Tracking the visible hand outline",clearanceDelayed:true),
            time:10,source:"cameraPresentation",disagreementSeconds:5)
        let calibration=BoardCalibration(size:19,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        let session=UUID()
        for n in 1...3 {trace.recordHandStall(evidence,calibration:calibration,session:session,moveNumber:265,atUnix:Double(n))}
        func object(_ name:String)->[String:Any]? {
            guard let data=try? Data(contentsOf:directory.appendingPathComponent(name)) else {return nil}
            return try? JSONSerialization.jsonObject(with:data) as? [String:Any]
        }
        let deadline=Date().addingTimeInterval(5)
        while object("hand-clearance-stall.json")?["atUnix"] as? Double != 3,Date()<deadline {Thread.sleep(forTimeInterval:0.02)}
        let current=object("hand-clearance-stall.json")!,previous=object("hand-clearance-stall-previous.json")!
        precondition(current["atUnix"] as? Double==3 && previous["atUnix"] as? Double==2,"Snapshots were reordered or not rotated")
        precondition(current["moveNumber"] as? Int==265 && current["session"] as? String==session.uuidString,"Incident lost its game context")
        let stored=try JSONSerialization.data(withJSONObject:current["evidence"]!)
        let replay=try JSONDecoder().decode(HandOutlineTracker.StallEvidence.self,from:stored)
        precondition(replay.checkpoint.active && replay.frame.pixels.count==1 && replay.result.obstructed==true && replay.result.clearanceDelayed,"Stored snapshot lost replay state")
        let files=try FileManager.default.contentsOfDirectory(atPath:directory.path)
        precondition(files.count==2,"Storage retained unbounded incident files")
        print("PASS: bounded hand-stall snapshots preserve replay evidence, game context and ordered rotation")
    }
}
