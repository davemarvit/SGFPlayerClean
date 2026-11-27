import Foundation
import CoreGraphics

/// Offline synthetic pipeline only. No app, camera, audio or controller startup.
@main struct CameraStageTimingPipelineTests {
    static func main()throws {
        let enabled = !CommandLine.arguments.contains("--disabled")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("CameraStages-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        setenv("PHYSICAL_GO_CAMERA_STAGE_TRACE",enabled ? "1":"0",1)
        setenv("PHYSICAL_GO_LATENCY_TRACE_DIRECTORY",folder.path,1)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        let context=CGContext(data:nil,width:160,height:160,bitsPerComponent:8,bytesPerRow:640,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red:0.6,green:0.5,blue:0.35,alpha:1));context.fill(CGRect(x:0,y:0,width:160,height:160))
        let calibration=BoardCalibration(size:19,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        let capture=ProcessInfo.processInfo.systemUptime
        let input=CameraAnalysisPipeline.Input(target:context.makeImage()!,calibration:calibration,threshold:0.2,
            reference:nil,referenceCalibration:calibration,straighten:true,longAxisRows:false,checkStoneAspect:false,
            previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:[],checkAlignment:false,
            trackingState:EstablishedStoneTracker(),trackingExpected:[],trackingContext:"test",trackingManualPoints:[],
            trackingFresh:true,trackingTime:capture,checkHands:false,originalCaptureUptime:capture,
            traceFields:["frameID":"fixture","streamEpoch":"offline"])
        var early:CameraAnalysisPipeline.CameraSafety?,completed=false
        let pipeline=CameraAnalysisPipeline()
        pipeline.submit(input,safety:{early=$0}) {output in
            check(early != nil,"Completion overtook same-frame safety")
            check(early?.handObstructed==output.handObstructed && early?.lightingBlocked==output.result?.lightingBlocked,
                "Instrumentation changed safety/full-result agreement")
            check(early?.exposureFailure==output.exposureFailure && (early?.aligned != nil)==(output.aligned != nil),
                "Instrumentation changed exposure/alignment agreement")
            check(output.corrected != nil,"Post-safety presentation was skipped")
            completed=true
        }
        let deadline=Date().addingTimeInterval(10)
        while !completed && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
        check(completed,"Pipeline completion timed out")
        check(PhysicalLatencyTrace.shared!.waitForTesting(),"Stage trace did not drain")
        let lines=try String(contentsOf:folder.appendingPathComponent("native-latency.jsonl"),encoding:.utf8).split(separator:"\n")
        let rows=try lines.map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let stages=rows.filter {($0["event"] as? String)?.hasSuffix("stages") == true}
        check(stages.count == (enabled ? 2:0),"Opt-in stage count incorrect")
        if enabled {
            for row in stages {
                let metrics=row["metrics"] as! [String:Double],fields=row["fields"] as! [String:String]
                check(fields["frameID"]=="fixture" && fields["streamEpoch"]=="offline","Stage provenance lost")
                check(metrics["captureUptime"]==capture,"Original capture timestamp changed")
                check(metrics.count<=24 && metrics.values.allSatisfy {$0.isFinite && $0>=0},"Stage event invalid or unbounded")
                check(metrics["totalThreadCPUSeconds"] != nil,"Stage CPU clock omitted")
            }
            let worker=stages.first {$0["event"] as? String == "camera_analysis_stages"}!["metrics"] as! [String:Double]
            for stage in ["gray","exposure","alignment","detect","pose","outline","lighting","safetyDispatch"] {
                check(worker[stage+"WallSeconds"] != nil && worker[stage+"ThreadCPUSeconds"] != nil,"Worker stage missing: "+stage)
            }
            check(rows.contains {$0["event"] as? String == "camera_completion_delivery"},"Completion dispatch gap missing")
            check(rows.contains {$0["event"] as? String == "camera_completion_apply"},"Completion application duration missing")
        }
        print("PASS \(checks) pipeline stage timing checks; enabled=\(enabled)")
    }
}
