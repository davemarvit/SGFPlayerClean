import Foundation

@MainActor enum RecordingWarningTests {
    static func run() throws ->Int {
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        let empty=[Occupancy](repeating:.empty,count:81)
        var first=empty;first[10] = .black
        var monitor=RecordingWarningMonitor(),time=0.0
        var signals=[(Double,RecordingWarningMonitor.Signal)]()
        func feed(_ readings:[Occupancy],accepted:[Occupancy],frames:Int,blocked:Bool) {
            for _ in 0..<frames {
                time += 0.21
                if let signal=monitor.update(readings:readings,accepted:accepted,now:time,blocked:blocked) {signals.append((time,signal))}
            }
        }
        feed(first,accepted:empty,frames:4,blocked:false)
        feed(first,accepted:first,frames:1,blocked:false)
        check(signals.isEmpty && monitor.outstandingCount==0,"Normally confirmed move produced a failure sound")
        monitor.reset();time=0
        feed(first,accepted:empty,frames:2,blocked:false)
        feed(empty,accepted:empty,frames:5,blocked:false)
        check(signals.isEmpty && monitor.outstandingCount==0,"Brief detector flicker produced a warning")
        monitor.reset();time=0
        feed(first,accepted:empty,frames:26,blocked:false)
        check(signals.count==1 && signals[0].1 == .unsavedStone && monitor.outstandingCount==1,"Overdue detected move was silent")
        let firstWarning=signals[0].0
        feed(first,accepted:empty,frames:30,blocked:true)
        check(signals.count==1,"Same unsaved stone warned on every frame")
        feed(first,accepted:empty,frames:9,blocked:true)
        check(signals.count==2 && signals[1].1 == .reminder && signals[1].0-firstWarning>=8,"Persistent blockage did not produce a bounded reminder")
        var second=first;second[20] = .white
        feed(second,accepted:empty,frames:26,blocked:true)
        check(signals.count==3 && signals.last!.1 == .unsavedStone,"New unsaved stone did not produce its own warning")
        let beforeFlicker=signals.count
        for i in 0..<12 {
            var flicker=second;flicker[20] = i%2==0 ? .uncertain : .white
            feed(flicker,accepted:empty,frames:1,blocked:true)
        }
        check(signals.count==beforeFlicker,"Uncertain/visible flicker repeated the same stone warning")
        feed(second,accepted:first,frames:1,blocked:true)
        check(monitor.outstandingCount==1 && monitor.hasWarnedOutstanding,"Saving one move erased the warning for another unsaved move")
        feed(second,accepted:second,frames:1,blocked:false)
        check(monitor.outstandingCount==0 && !monitor.hasWarnedOutstanding,"Saved moves retained stale failure warnings")
        let previous=signals.count
        feed(second,accepted:second,frames:80,blocked:false)
        check(signals.count==previous,"Successful recovery continued reminder sounds")
        monitor.reset();signals=[];time=0
        feed(first,accepted:empty,frames:26,blocked:false)
        feed(empty,accepted:empty,frames:5,blocked:false)
        feed(first,accepted:empty,frames:26,blocked:false)
        check(signals.count==2,"A genuinely new appearance after removal could never warn again")
        monitor.reset();signals=[];time=0
        feed(first,accepted:empty,frames:2,blocked:false)
        for _ in 0..<30 {check(monitor.update(readings:first,accepted:empty,now:time,blocked:false)==nil,"Duplicate camera time produced a warning")}
        check(monitor.outstandingCount==0,"Duplicate timestamps established a stable stone")

        monitor.reset();signals=[];time=0
        feed(first,accepted:empty,frames:26,blocked:false)
        monitor.recorded([10]) // Saved in a sequence that also captured this stone.
        feed(empty,accepted:empty,frames:1,blocked:false)
        check(!monitor.hasWarnedOutstanding && monitor.outstandingCount==0,"A recorded-and-captured stone retained a stale warning")

        let r=GameRecorder(storage:nil);r.start(size:9)
        var stamp=0.0,warnings=0
        r.onAttention={warnings += 1}
        func observed(_ values:[Occupancy])->BoardObservation {
            BoardObservation(readings:values.enumerated().map{i,v in IntersectionReading(row:i/9,col:i%9,occupancy:v,confidence:1,delta:0)},size:9)
        }
        func send(_ values:[Occupancy],_ frames:Int) {for _ in 0..<frames {stamp += 0.21;r.consume(observed(values),now:stamp)}}
        send(empty,5)
        var covered=first;for i in 30..<50 {covered[i] = .uncertain}
        send(covered,26)
        check(r.moveCount==0 && r.needsAttention && warnings==1,"Global uncertainty suppressed an unsaved-move warning or appended a move")
        r.acknowledgeAttention();send(covered,40)
        check(warnings==1 && r.needsAttention,"A single blockage produced repeated alarms within 30 seconds")
        send(covered,120)
        check(warnings>=2 && r.needsAttention,"Acknowledging a warning permanently silenced the continuing blockage")
        r.pause();let pausedWarnings=warnings;send(covered,80)
        check(warnings==pausedWarnings,"Paused recording kept beeping")
        r.resume();send(empty,5);send(first,5)
        check(r.moveCount==1 && !r.needsAttention && r.unsavedStoneCount==0,"A verified recorded move did not clear the warning")
        r.finish();send(second,80);check(warnings==pausedWarnings,"Finished recording kept beeping")

        // Ordinary recognition delay must not play failure then success.
        for duration in [1.2,2.2,3.2,4.5,8.5] {
            var tracking=RecordingWarningMonitor();var alerts=0
            for step in 0...Int(duration/0.2) {
                if tracking.update(readings:first,accepted:empty,now:Double(step)*0.2,blocked:false,trackedMoves:[10]) != nil {alerts+=1}
            }
            _=tracking.update(readings:first,accepted:first,now:duration+0.2,blocked:false)
            check(alerts==0 && tracking.outstandingCount==0,"Normal tracked confirmation sounded a failure")
        }
        var stalled=RecordingWarningMonitor(),stallAlerts=0
        for step in 0...55 {
            if stalled.update(readings:first,accepted:empty,now:Double(step)*0.2,blocked:false,trackedMoves:[10]) != nil {stallAlerts+=1}
        }
        check(stallAlerts==1,"A genuinely stalled tracked move did not warn")

        var retainedWarning=RecordingWarningMonitor()
        var retainedSignals=[RecordingWarningMonitor.Signal]()
        for i in 1...90 {
            if let signal=retainedWarning.update(readings:first,accepted:empty,now:Double(i)*0.21,blocked:true,knownPlacementWarnings:[10]) {
                retainedSignals.append(signal)
            }
        }
        check(retainedSignals == [.unsavedStone],"Same retained placement produced repeated warnings")
        for i in 91...120 {
            if let signal=retainedWarning.update(readings:second,accepted:empty,now:Double(i)*0.21,blocked:true,knownPlacementWarnings:[10]) {
                retainedSignals.append(signal)
            }
        }
        check(retainedSignals.filter{$0 == .unsavedStone}.count==2,"A known placement silenced a new missed stone")

        let quiet=GameRecorder(storage:nil)
        var tick=0.0, chimes=[[PlacementChimeMonitor.Issue]]()
        quiet.onPlacementChime={chimes.append($0)}
        func sight(_ colors:[Occupancy], offset:Double?, count:Int) {
            for _ in 0..<count {
                tick+=0.21
                var v=observed(colors)
                if let offset {v.footprints=[.init(row:1,col:1,center:.init(x:1+offset,y:1),radiusCol:0.46,radiusRow:0.46,quality:1)]}
                quiet.consume(v,now:tick)
            }
        }
        quiet.start(size:9);sight(empty,offset:nil,count:5)
        sight(first,offset:0.4,count:2)
        sight(first,offset:nil,count:60)
        check(chimes.isEmpty,"Missing outlines sounded a placement alert")
        sight(first,offset:0.4,count:30)
        check(chimes == [[.init(move:1,point:10)]],"Persistent displacement must sound once for its own move")
        quiet.pause();sight(first,offset:0.4,count:15);quiet.resume()
        sight(first,offset:0.4,count:50)
        check(chimes.count==1,"Pause or resume repeated the same placement chime")
        sight(first,offset:0.05,count:12)
        check(quiet.moveCount==1 && chimes.count==1,"Confirming the adjusted move added a chime")
        quiet.start(size:9);sight(empty,offset:nil,count:5)
        sight(first,offset:0.4,count:30)
        check(chimes.count==2,"A new game inherited an earlier game's chime history")

        let dark=GameRecorder(storage:nil)
        dark.start(size:9,now:0)
        for i in 1...5 { dark.consume(observed(empty),now:Double(i)*0.21) }
        var obscured=observed(first)
        obscured.lightingBlocked=true
        obscured.notice="Waiting for more light."
        for i in 6...22 { dark.consume(obscured,now:Double(i)*0.21) }
        check(dark.moveCount==0 && dark.pendingMoveCount==0 && !dark.synchronized,"Unusable lighting contributed a phantom stone")
        for i in 23...32 { dark.consume(observed(first),now:Double(i)*0.21) }
        check(dark.moveCount==1,"A readable board did not resume move recognition after a lighting change")

        // User's actual first-move stall: uncertainty stayed high while more
        // recognizable stones appeared. Replay must warn without inventing moves.
        let fixture=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/RecordingWarnings/observations.jsonl")
        let actual=GameRecorder(storage:nil);actual.start(size:19)
        var actualWarnings=[Double](),currentTime=0.0,startTime:Double?
        actual.onAttention={actualWarnings.append(currentTime)}
        for line in try String(contentsOf:fixture,encoding:.utf8).split(separator:"\n") {
            let row=try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
            if let event=row["event"] as? String,event.hasPrefix("vision interrupted: ") {
                actual.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"));continue
            }
            guard let values=row["position"] as? String,let now=row["uptime"] as? Double else {continue}
            currentTime=now;if startTime==nil {startTime=now}
            let readings=values.enumerated().map{i,c in IntersectionReading(row:i/19,col:i%19,occupancy:c == "B" ? .black : c == "W" ? .white : c == "?" ? .uncertain : .empty,confidence:1,delta:0)}
            actual.consume(BoardObservation(readings:readings,size:19),now:now)
        }
        check(actual.moveCount==1,"Warning replay changed the stalled game's accepted history")
        // The later deferred-review workflow replaces the old stop-playing alert:
        // preserve the gap and keep observing later moves without repeated alarms.
        check(actual.hasDeferredMoves && actual.reviewHistory.unresolved==1 && !actual.needsAttention,
              "Historical gap did not transition to deferred review")
        check(actual.reviewHistory.retainedMoveCount==4 && actual.state == .recording,
              "Deferred review lost later ordered moves or stopped recording")
        check(actualWarnings.count==2,"Historical blockage was not coalesced into bounded reminders")
        check(actualWarnings[1]-actualWarnings[0]>=30,"Same historical blockage warned too frequently")
        check(actualWarnings.contains{$0-startTime!>=55 && $0-startTime!<67},"Actual second-move stall was not warned promptly")
        print("Actual stall warning offsets:",actualWarnings.map{Int(($0-startTime!).rounded())})
        print("PASS: \(checks) warning checks: confirmation grace, repeated unsaved moves, reminders, flicker, duplicates, recovery, pause/finish, and real stalled-session replay.")
        return checks
    }
}
