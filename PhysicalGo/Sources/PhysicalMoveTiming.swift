import Foundation

/// Small, persistent events, separate from the rotating frame-decision log.
/// Times mean when this client observed a phase, never the unknowable instant a
/// hand placed a stone or an OGS server received a packet. Durations use uptime.
final class PhysicalMoveTiming {
    /// Scores are heuristic evidence, never probabilities of correctness.
    /// A missing offset means no qualifying geometric fit, not perfect centering.
    struct Evidence {
        let confidence:Double
        let assignmentOffset:Double?
        let placementOffset:Double?
        let manual:Bool
        var json:[String:Any] {
            ["confidence":confidence.isFinite ? confidence as Any:NSNull(),
             "assignmentOffset":assignmentOffset.flatMap{$0.isFinite ? $0:nil}.map{$0 as Any} ?? NSNull(),
             "placementOffset":placementOffset.flatMap{$0.isFinite ? $0:nil}.map{$0 as Any} ?? NSNull(),
             "assignmentAmbiguous":assignmentOffset.map{$0>=0.30} as Any? ?? NSNull(),
             "manualCorrection":manual]
        }
    }
    struct Position {
        let game:Int, revision:Int, size:Int
        let board:[String], color:String
        let myTurn:Bool
        let lastPoint:Int?
    }
    private struct Attempt {
        let id=UUID().uuidString
        let point:Int, began:Double
        var firstClear:Double?, sent:Double?, request:String?
        var slow=false, issue:String?
        var observations=0
        var unknown=[Int:Int]()
        var reasons=[String:Int]()
        var absentSince:Double?
        var firstEvidence:Evidence?, firstClearEvidence:Evidence?, latestEvidence:Evidence?, sentEvidence:Evidence?
        var confirmation=[(time:Double,evidence:Evidence)]()
        var confirmationSummary:[String:Any]?
        var lastObservation:Double?, maxObservationGap=0.0
        var uncertainAtSend:Int?
        var uncertain=false
        var alignmentFailures=[String:Int]()
        var latestAlignmentFailure:[String:Any]?
    }
    let directory:URL
    private let run=UUID().uuidString
    private let queue=DispatchQueue(label:"PhysicalGo.move-timing",qos:.utility)
    private var position:Position?
    private var attempt:Attempt?
    private var serverSeen:Double?
    private var physicalMatched=false
    private(set) var notice:String?
    private(set) var statisticsText:String?
    private var submittedTimes=[Int:[Double]](),acknowledgedTimes=[Int:[Double]]()
    var onWriteError:((String)->Void)?
    var onEvidenceCapture:(([String:Any])->String?)?
    init(directory:URL) {self.directory=directory}

    private func recordStatistics(_ event:String,game:Int,attempt a:Attempt,now:Double) {
        guard let sent=a.sent else {return}
        if event=="move_request_written" {submittedTimes[game,default:[]].append(max(0,sent-a.began))}
        else if event=="server_acknowledged" {acknowledgedTimes[game,default:[]].append(max(0,now-sent))}
        else {return}
        let values=(submittedTimes[game] ?? []).sorted()
        guard !values.isEmpty else {return}
        func percentile(_ p:Double)->Double {
            let i=Double(values.count-1)*p,lo=Int(i),hi=min(lo+1,values.count-1)
            return values[lo]+(values[hi]-values[lo])*(i-Double(lo))
        }
        var bins=Array(repeating:0,count:5)
        for value in values {
            let index:Int
            if value<1 {index=0} else if value<2 {index=1}
            else if value<3 {index=2} else if value<5 {index=3} else {index=4}
            bins[index] += 1
        }
        let ack=acknowledgedTimes[game] ?? []
        statisticsText="This app session · game \(game) · \(values.count) moves sent\n" +
            String(format:"First detection → send: average %.2fs · median %.2fs · 95th percentile %.2fs · longest %.2fs\n",
                   values.reduce(0,+)/Double(values.count),percentile(0.5),percentile(0.95),values.last!) +
            "Move counts: <1s: \(bins[0]) · 1–2s: \(bins[1]) · 2–3s: \(bins[2]) · 3–5s: \(bins[3]) · ≥5s: \(bins[4])" +
            (ack.isEmpty ? "":String(format:"\nSend → server observed: average %.2fs (%d confirmed)",ack.reduce(0,+)/Double(ack.count),ack.count))
    }

    private func write(_ event:String,now:Double,wall:Double,extra:[String:Any]=[:]) {
        guard let position else {return}
        var row:[String:Any]=["schema":3,"evidenceScope":"local candidate","event":event,"time":wall,"uptime":now,
            "game":position.game,"revision":position.revision,"size":position.size,"run":run,
            "appVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "test",
            "appBuild":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") ?? "test",
            "sourceHash":Bundle.main.object(forInfoDictionaryKey:"PhysicalGoSourceHash") ?? "unavailable"]
        row.merge(extra){_,new in new}
        if let a=attempt {
            recordStatistics(event,game:position.game,attempt:a,now:now)
            row["attempt"]=a.id;row["point"]=a.point;row["color"]=position.color
            row["elapsedSeconds"]=max(0,now-a.began)
            row["observations"]=a.observations
            row["uncertainPoints"]=a.unknown.sorted{$0.key<$1.key}.map{["point":$0.key,"frames":$0.value]}
            row["blockers"]=a.reasons
            row["firstDetectionEvidence"]=a.firstEvidence?.json
            row["firstClearEvidence"]=a.firstClearEvidence?.json
            row["latestPreSubmissionEvidence"]=a.latestEvidence?.json
            row["submissionEvidence"]=a.sentEvidence?.json
            row["confirmationEvidence"]=a.confirmationSummary
            row["maxObservationGapSeconds"]=a.maxObservationGap
            row["uncertainIntersectionsAtSubmission"]=a.uncertainAtSend
            row["alignmentFailureCounts"]=a.alignmentFailures
            row["latestAlignmentFailure"]=a.latestAlignmentFailure
            row["borderlineEvidenceObserved"]=a.uncertain
            if let t=a.firstClear {row["firstClearAfterSeconds"]=max(0,t-a.began)}
            if let t=a.sent {row["recognitionToRequestSeconds"]=max(0,t-a.began);row["requestToObservationSeconds"]=max(0,now-t)}
            if let id=a.request {row["requestID"]=id}
            if event=="uncertain_move" || event=="slow_move" || (event=="move_request_written" && (a.slow || a.uncertain)) {
                row["evidenceCaptureRequested"]=true
                row["captureConfidenceThreshold"]=0.90;row["captureAssignmentOffsetThreshold"]=0.24
                // Preserve the authoritative expected position for incident replay,
                // without treating it as a label for the photographed board or
                // expanding every compact timing event into a full-board record.
                var captureEvent=row
                captureEvent["serverBoard"]=position.board
                captureEvent["serverBoardIsCameraGroundTruth"]=false
                captureEvent["serverMyTurn"]=position.myTurn
                captureEvent["serverLastPoint"]=position.lastPoint.map{$0 as Any} ?? NSNull()
                if let path=onEvidenceCapture?(captureEvent) {row["evidenceCaptureFolder"]=path}
            }
        }
        let file=directory.appendingPathComponent("game-\(position.game)-\(run).jsonl")
        let errorHandler=onWriteError,payload=row
        queue.async {
            do {
                var data=try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys);data.append(10)
                try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                if !FileManager.default.fileExists(atPath:file.path) {try Data().write(to:file)}
                let handle=try FileHandle(forWritingTo:file);defer {try? handle.close()}
                try handle.seekToEnd();try handle.write(contentsOf:data)
            } catch {
                DispatchQueue.main.async {errorHandler?(error.localizedDescription)}
            }
        }
    }
    func wait(_ reason:String,now:Double,wall:Double=Date().timeIntervalSince1970,details:[String:Any]=[:]) {
        guard var a=attempt else {return}
        a.reasons[reason,default:0] += 1
        if let failure=details["rejectionReason"] as? String {
            a.alignmentFailures[failure,default:0] += 1;a.latestAlignmentFailure=details
        }
        attempt=a
        flagSlow(now:now,wall:wall)
    }
    private func flagSlow(now:Double,wall:Double) {
        guard var a=attempt,!a.slow,now-a.began>=5 else {return}
        a.slow=true;attempt=a
        notice="Long move delay recorded — timing details saved."
        write("slow_move",now:now,wall:wall,extra:["thresholdSeconds":5])
    }
    func close(reason:String,now:Double=ProcessInfo.processInfo.systemUptime,wall:Double=Date().timeIntervalSince1970) {
        if attempt != nil {write("interrupted",now:now,wall:wall,extra:["reason":reason])}
        attempt=nil;position=nil;serverSeen=nil;physicalMatched=false
    }
    func flush() {queue.sync {}}

    /// Only observes decisions. It cannot fill camera readings or dispatch moves.
    func observe(_ next:Position,readings:[String]?,clearCandidate:Int?,requestID:String?,
                 issue:String?,blocker:String,now:Double,wall:Double=Date().timeIntervalSince1970,
                 evidence:[Int:Evidence]=[:],clearWitnesses:Int=0,evidenceSpan:Double=0) {
        if let old=position,old.game != next.game || old.size != next.size || old.color != next.color {
            close(reason:"Game or camera-side context changed",now:now,wall:wall)
        }
        let old=position
        let changed=old.map{$0.board != next.board || $0.lastPoint != next.lastPoint ||
            (next.lastPoint == nil && $0.myTurn != next.myTurn && attempt?.sent == nil)} ?? false
        if changed,let a=attempt {
            if a.sent != nil,next.board.indices.contains(a.point),next.lastPoint==a.point,next.board[a.point]==next.color {
                write("server_acknowledged",now:now,wall:wall,extra:["serverRevision":next.revision])
                if a.slow {notice=String(format:"Last delayed move: %.1f seconds. Timing details saved.",now-a.began)}
            } else {write("position_changed",now:now,wall:wall)}
            attempt=nil
        }
        position=next
        if old == nil || changed {
            serverSeen=now;physicalMatched=false
            write(old == nil ? "connected_position" : "server_move_seen",now:now,wall:wall,
                  extra:["lastPoint":next.lastPoint.map{$0 as Any} ?? NSNull(),
                         "lastColor":next.lastPoint.map{next.board[$0] as Any} ?? NSNull(),
                         "isPass":next.lastPoint == nil,"myTurn":next.myTurn])
        }
        guard let readings,readings.count==next.board.count else {
            if attempt?.sent == nil {attempt?.confirmation=[]}
            wait(blocker,now:now,wall:wall);return
        }
        if readings==next.board,!physicalMatched {
            physicalMatched=true
            write("physical_board_matched",now:now,wall:wall,extra:["afterServerSeenSeconds":max(0,now-(serverSeen ?? now))])
        }
        let additions=readings.indices.filter{next.board[$0]=="empty" && readings[$0]==next.color}
        let unknown=readings.indices.filter{readings[$0]=="uncertain"}
        let point=next.myTurn && additions.count==1 ? additions[0] : nil
        if let a=attempt,a.sent==nil {
            if let point,point != a.point {
                write("candidate_replaced",now:now,wall:wall);attempt=nil
            } else if readings[a.point]=="empty" {
                if attempt?.absentSince==nil {attempt?.absentSince=now}
                if now-(attempt?.absentSince ?? now)>=0.8 {
                    write("stone_removed",now:now,wall:wall);attempt=nil
                }
            } else {attempt?.absentSince=nil}
        }
        if attempt==nil,let point {
            attempt=Attempt(point:point,began:now)
            attempt?.firstEvidence=evidence[point]
            write("camera_candidate_seen",now:now,wall:wall)
        }
        guard var a=attempt else {return}
        a.observations += 1
        for p in unknown {a.unknown[p,default:0] += 1}
        if !blocker.isEmpty {a.reasons[blocker,default:0] += 1}
        let newClear=a.firstClear==nil && clearCandidate==a.point
        if newClear {a.firstClear=now;a.firstClearEvidence=evidence[a.point]}
        let newSend=a.sent==nil && requestID != nil
        // Freeze dispatch evidence: later camera frames and server acknowledgments
        // must not overwrite the confidence of the actual submitted move.
        if a.sent == nil {
            a.latestEvidence=evidence[a.point]
            if let previous=a.lastObservation {a.maxObservationGap=max(a.maxObservationGap,now-previous)}
            a.lastObservation=now
            if clearCandidate==a.point,clearWitnesses>0 {
                a.confirmation.removeAll{$0.time<now-evidenceSpan-0.000001}
                if clearWitnesses==1 {a.confirmation=[]}
                if let sample=evidence[a.point] {a.confirmation.append((now,sample))}
            } else {a.confirmation=[]}
        }
        if newSend {
            a.sent=now;a.request=requestID;a.sentEvidence=evidence[a.point];a.uncertainAtSend=unknown.count
            let scores=a.confirmation.map{$0.evidence.confidence}.filter{$0.isFinite}
            let offsets=a.confirmation.compactMap{$0.evidence.assignmentOffset}.filter{$0.isFinite}
            a.confirmationSummary=["clearWitnesses":clearWitnesses,"spanSeconds":evidenceSpan,
                "scoredWitnesses":scores.count,"geometryWitnesses":offsets.count,
                "minimumConfidence":scores.min().map{$0 as Any} ?? NSNull(),
                "meanConfidence":scores.isEmpty ? NSNull():scores.reduce(0,+)/Double(scores.count) as Any,
                "maximumAssignmentOffset":offsets.max().map{$0 as Any} ?? NSNull(),
                "manualWitnesses":a.confirmation.filter{$0.evidence.manual}.count]
        }
        let newIssue=issue != nil && a.issue != issue
        if newIssue {a.issue=issue}
        let newUncertain:Bool
        if !a.uncertain,a.sent==nil || newSend,let sample=evidence[a.point],!sample.manual {
            newUncertain=(sample.confidence.isFinite && sample.confidence<0.90) ||
                (sample.assignmentOffset.map{$0.isFinite && $0>=0.24} ?? false)
        } else {newUncertain=false}
        if newUncertain {a.uncertain=true}
        attempt=a
        if newClear {write("first_clear_candidate",now:now,wall:wall)}
        if newUncertain {write("uncertain_move",now:now,wall:wall)}
        if newSend {write("move_request_written",now:now,wall:wall)}
        if newIssue {write("move_issue",now:now,wall:wall,extra:["message":issue!])}
        flagSlow(now:now,wall:wall)
    }
}
