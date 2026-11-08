import Foundation
@main struct MoveTimingTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let timing=PhysicalMoveTiming(directory:root)
        var board=Array(repeating:"empty",count:81)
        func position(_ revision:Int=1,_ myTurn:Bool=true,_ point:Int?=nil,_ game:Int=42)->PhysicalMoveTiming.Position {
            .init(game:game,revision:revision,size:9,board:board,color:"black",myTurn:myTurn,lastPoint:point)
        }
        func observe(_ cells:[String],_ now:Double,_ revision:Int=1,_ myTurn:Bool=true,_ last:Int?=nil,_ candidate:Int?=nil,_ request:String?=nil,_ issue:String?=nil) {
            timing.observe(position(revision,myTurn,last),readings:cells,clearCandidate:candidate,requestID:request,issue:issue,
                           blocker:cells.contains("uncertain") ? "Uncertain intersection":"",now:now,wall:10000-now)
        }
        observe(board,0)
        var camera=board;camera[10]="black";camera[80]="uncertain"
        observe(camera,1)
        for i in 2...7 {observe(camera,Double(i))}
        camera[80]="empty"
        observe(camera,7.2,1,true,nil,10)
        observe(camera,7.5,1,true,nil,10,"request-a")
        // A revision-only update, even a split turn update, is not an ack.
        observe(camera,7.6,2,false,nil,nil,"request-a")
        board[10]="black"
        observe(board,8.1,3,false,10)
        observe(board,8.3,4,false,10)
        board[20]="white"
        observe(camera,10,5,true,20)
        observe(board,12,5,true,20)
        observe(board,13,6,false,nil) // Pass.
        observe(board,14,7,true,nil) // Consecutive pass.
        timing.close(reason:"Disabled",now:15,wall:10015);timing.flush()
        func rows()->[[String:Any]] {
            (try! FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)).flatMap {url in
                (try! String(contentsOf:url,encoding:.utf8)).split(separator:"\n").map {try! JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
            }
        }
        let first=rows()
        func events(_ name:String)->[[String:Any]] {first.filter{$0["event"] as? String==name}}
        precondition(events("camera_candidate_seen").count==1)
        precondition(events("slow_move").count==1)
        precondition(events("first_clear_candidate").count==1)
        precondition(events("move_request_written").count==1)
        precondition(events("server_acknowledged").count==1)
        let ack=events("server_acknowledged")[0]
        precondition(abs((ack["recognitionToRequestSeconds"] as! Double)-6.5)<0.001)
        precondition(abs((ack["requestToObservationSeconds"] as! Double)-0.6)<0.001)
        precondition(abs((ack["elapsedSeconds"] as! Double)-7.1)<0.001,"Wall-clock adjustment changed elapsed time")
        precondition(timing.statisticsText?.contains("average 6.50s") == true)
        precondition(timing.statisticsText?.contains("average 0.60s (1 confirmed)") == true)
        precondition((ack["uncertainPoints"] as! [[String:Int]]).contains{$0["point"]==80 && $0["frames"]==7})
        precondition(events("server_move_seen").count==4,"Duplicate revision or missing opponent/pass event")
        precondition(events("server_move_seen").filter{$0["isPass"] as? Bool==true}.count==2)
        precondition(events("physical_board_matched").contains{abs(($0["afterServerSeenSeconds"] as? Double ?? -1)-2)<0.001})
        // Restart writes another file, retaining all previous events.
        let restarted=PhysicalMoveTiming(directory:root)
        var next=board;next[11]="black"
        restarted.observe(position(),readings:next,clearCandidate:11,requestID:nil,issue:nil,blocker:"",now:20)
        restarted.observe(position(),readings:board,clearCandidate:nil,requestID:nil,issue:nil,blocker:"",now:21)
        restarted.observe(position(),readings:board,clearCandidate:nil,requestID:nil,issue:nil,blocker:"",now:22)
        restarted.flush()
        precondition(rows().count>first.count)
        precondition(rows().filter{$0["event"] as? String=="stone_removed"}.count==1)
        let files=try FileManager.default.contentsOfDirectory(atPath:root.path)
        precondition(files.count==2)
        let text=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).map{try String(contentsOf:$0,encoding:.utf8)}.joined()
        precondition(!text.contains("token") && !text.contains("board\":"),"Credentials/full frame leaked into compact timing log")
        let evidenceRoot=root.appendingPathComponent("evidence")
        let measured=PhysicalMoveTiming(directory:evidenceRoot)
        var captureEvents=[[String:Any]]()
        measured.onEvidenceCapture={event in captureEvents.append(event);return "fixture-archive"}
        board=Array(repeating:"empty",count:81)
        camera=board;camera[10]="black"
        func sample(_ now:Double,_ score:Double,_ witnesses:Int,_ span:Double=0,_ offset:Double?=nil,_ request:String?=nil,_ manual:Bool=false) {
            measured.observe(position(),readings:camera,clearCandidate:witnesses>0 ? 10:nil,requestID:request,
                issue:nil,blocker:"",now:now,wall:100-now,
                evidence:[10:.init(confidence:score,assignmentOffset:offset,placementOffset:offset,manual:manual)],
                clearWitnesses:witnesses,evidenceSpan:span)
        }
        sample(1,0.55,0)
        sample(2,0.81,1,0,0.29)
        sample(2.3,0.4,0) // Failed confirmation must not contaminate final-window minimum.
        sample(3,0.92,1)
        sample(3.4,0.88,2,0.4,0.12)
        sample(3.7,0.96,3,0.7)
        sample(4.1,0.94,4,1.1,0.20,"measured",true)
        sample(4.3,0.05,4,1.3,0.45,"measured") // After dispatch, evidence is frozen.
        board[10]="black"
        measured.observe(position(2,false,10),readings:board,clearCandidate:nil,requestID:nil,
                         issue:nil,blocker:"",now:4.7)
        measured.flush()
        precondition(captureEvents.map{$0["event"] as! String}==["uncertain_move","move_request_written"])
        precondition((captureEvents[0]["serverBoard"] as? [String])?[10]=="empty")
        precondition(captureEvents[0]["serverBoardIsCameraGroundTruth"] as? Bool==false)
        let evidenceFile=try FileManager.default.contentsOfDirectory(at:evidenceRoot,includingPropertiesForKeys:nil)[0]
        let measuredRows=try String(contentsOf:evidenceFile,encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        precondition(measuredRows.allSatisfy{$0["serverBoard"]==nil},"Incident replay context bloated the compact timing journal")
        for row in measuredRows.filter({["move_request_written","server_acknowledged"].contains($0["event"] as? String ?? "")}) {
            precondition(row["schema"] as? Int==3)
            let first=row["firstDetectionEvidence"] as! [String:Any]
            let sent=row["submissionEvidence"] as! [String:Any]
            let confirmation=row["confirmationEvidence"] as! [String:Any]
            precondition(first["confidence"] as? Double==0.55)
            precondition(first["assignmentOffset"] is NSNull,"Absent geometry must not become zero displacement")
            precondition(sent["confidence"] as? Double==0.94 && sent["manualCorrection"] as? Bool==true)
            precondition(confirmation["minimumConfidence"] as? Double==0.88)
            precondition(confirmation["scoredWitnesses"] as? Int==4)
            precondition(confirmation["geometryWitnesses"] as? Int==2)
            precondition(confirmation["manualWitnesses"] as? Int==1)
            precondition(confirmation["maximumAssignmentOffset"] as? Double==0.20)
            precondition(abs((confirmation["spanSeconds"] as! Double)-1.1)<0.001)
        }
        precondition(measured.statisticsText?.contains("1 moves sent") == true,"Repeated camera observations double-counted timing statistics")
        // Accepted-but-borderline evidence also triggers capture; this is not
        // restricted to scores below the dispatch threshold of 0.8.
        let borderline=PhysicalMoveTiming(directory:root.appendingPathComponent("borderline"))
        var reasons=[String]()
        borderline.onEvidenceCapture={event in reasons.append(event["event"] as! String);return "borderline-archive"}
        board=Array(repeating:"empty",count:81);camera=board;camera[10]="black"
        borderline.observe(position(),readings:camera,clearCandidate:10,requestID:nil,issue:nil,blocker:"",now:1,
            evidence:[10:.init(confidence:0.85,assignmentOffset:nil,placementOffset:nil,manual:false)],clearWitnesses:1)
        precondition(reasons==["uncertain_move"])
        borderline.wait("Grid alignment rejected",now:6.1,details:["rejectionReason":"outer rails unsupported","matched":12])
        borderline.flush()
        precondition(reasons==["uncertain_move","slow_move"])
        let failureFile=try FileManager.default.contentsOfDirectory(at:borderline.directory,includingPropertiesForKeys:nil)[0]
        let failureText=try String(contentsOf:failureFile,encoding:.utf8)
        precondition(failureText.contains("outer rails unsupported") && failureText.contains("borderline-archive"))
        let geometric=PhysicalMoveTiming(directory:root.appendingPathComponent("geometric"))
        var geometryTriggers=0
        geometric.onEvidenceCapture={_ in geometryTriggers += 1;return nil}
        func geometricSample(_ time:Double,_ confidence:Double,_ offset:Double,_ manual:Bool) {
            geometric.observe(position(),readings:camera,clearCandidate:10,requestID:nil,issue:nil,blocker:"",now:time,
                evidence:[10:.init(confidence:confidence,assignmentOffset:offset,placementOffset:offset,manual:manual)],clearWitnesses:1)
        }
        geometricSample(1,1,0.1,false)
        geometricSample(1.2,0.85,0.1,true)
        precondition(geometryTriggers==0,"Certain or manually supplied confidence triggered camera uncertainty capture")
        geometricSample(1.4,1,0.25,false)
        precondition(geometryTriggers==1,"Near-threshold geometry with strong color evidence was not captured")
        geometric.flush()
        print("PASS: persistent move phases, monotonic durations, single anomaly flag, uncertain points, split/revision updates, opponent moves, passes, physical matching, withdrawal and restart retention.")
        print("PASS: first and submitted confidence, final-window reset, missing geometry, manual evidence, and frozen dispatch evidence after acknowledgment.")
    }
}
