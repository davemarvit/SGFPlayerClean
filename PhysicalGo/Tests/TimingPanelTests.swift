import AppKit
import SwiftUI

@main struct TimingPanelTests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        try runLocalClockTests()
        try await runPhysicalScoringTests()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("timing-panel-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let online=root.appendingPathComponent("online"),local=root.appendingPathComponent("local")
        for folder in [online,local] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
        func write(_ rows:[[String:Any]],to url:URL,append:Bool=false)throws {
            let data=try rows.reduce(into:Data()) {$0.append(try JSONSerialization.data(withJSONObject:$1));$0.append(10)}
            if append {let h=try FileHandle(forWritingTo:url);try h.seekToEnd();try h.write(contentsOf:data);try h.close()}
            else {try data.write(to:url)}
        }
        let file=online.appendingPathComponent("game.jsonl")
        let sends:[[String:Any]]=[0.5,1.0,2.0,3.0,5.0].enumerated().map {i,value in
            ["event":"move_request_written","game":42,"run":"test","attempt":"\(i)","point":i,"size":19,"color":"black","time":100.0+Double(i),"recognitionToRequestSeconds":value]
        }
        try write(sends,to:file)
        let reader=MoveTimingReportReader(onlineRoot:online,localRoot:local)
        var reports=try reader.refresh();precondition(reports.count==1 && reports[0].bins==[1,1,1,1,1])
        precondition(abs(reports[0].average!-2.3)<0.0001 && reports[0].percentile(0.5)==2)
        precondition(tryReport(reader).samples.count==5,"Refresh duplicated moves")
        try write([["event":"server_acknowledged","game":42,"run":"test","attempt":"0","time":105.0,"requestToObservationSeconds":0.25]],to:file,append:true)
        precondition(tryReport(reader).samples[0].serverSeconds==0.25)
        let restarted=MoveTimingReportReader(onlineRoot:online,localRoot:local)
        precondition(tryReport(restarted).bins==[1,1,1,1,1],"Restart lost history")
        try write(sends,to:online.appendingPathComponent("duplicate.jsonl"))
        precondition(tryReport(reader).samples.count==5,"Duplicate journals doubled counts")
        // Partial writes wait for the newline, then become visible once.
        let partial=online.appendingPathComponent("partial.jsonl")
        let bytes=try JSONSerialization.data(withJSONObject:["event":"move_request_written","game":43,"run":"r","attempt":"a","time":200.0,"recognitionToRequestSeconds":1.5])
        try bytes.prefix(bytes.count/2).write(to:partial)
        precondition(tryReports(reader).count==1)
        let h=try FileHandle(forWritingTo:partial);try h.seekToEnd();try h.write(contentsOf:bytes.suffix(bytes.count-bytes.count/2)+Data([10]));try h.close()
        precondition(tryReports(reader).count==2)
        let legacy=local.appendingPathComponent("old.observations.jsonl")
        try write([
            ["event":"observation","time":1.0,"uptime":1.0,"state":"recording","size":9,"moveCount":0,"tentativeConfidence":[["point":10,"orderSupported":true]]],
            ["event":"accepted move","time":2.5,"moveCount":1],
            ["event":"manual move","time":3.0,"moveCount":2]
        ],to:legacy)
        let legacyReport=tryReports(reader).first {$0.mode=="local"}!
        precondition(legacyReport.values==[1.5] && legacyReport.samples.count==2)
        try write([["event":"undo","time":4.0,"moveCount":1]],to:legacy,append:true)
        precondition(tryReports(reader).first {$0.mode=="local"}!.samples.count==1)
        print("PASS: persisted online stats, bins/percentiles, ack separation, incremental refresh, duplicate journals, partial writes, legacy local estimates, manual exclusion and undo")

        var now=0.0,events=[[String:Any]](),captures=[[String:Any]]()
        let recorder=GameRecorder(storage:local)
        recorder.onDiagnosticEvent={events.append($0)}
        recorder.onEvidenceCapture={captures.append($0);return root.appendingPathComponent("test-clip").path}
        var info=SGFGame.Info(event:"Friendly [test] \\ event",playerBlack:"Dave",playerWhite:"相手",blackRank:"1d",whiteRank:"2k",date:"2026-11-06",komi:"6.5",rules:"Japanese")
        recorder.start(size:9,now:now,info:info)
        func observe(_ board:BoardSnapshot,ambiguous:Bool=false) {
            now += 0.21
            var view=BoardObservation(readings:(0..<81).map {p in
                IntersectionReading(row:p/9,col:p%9,occupancy:board.grid[p/9][p%9] == .black ? .black:board.grid[p/9][p%9] == .white ? .white:.empty,confidence:1,delta:0)
            },size:9)
            if ambiguous {view.placementFits=[.init(row:4,col:4,center:.init(x:4.49,y:4),radiusCol:0.46,radiusRow:0.46,quality:1)]}
            recorder.consume(view,now:now)
        }
        for _ in 0..<8 {observe(recorder.positions[0])}
        let engine=SGFPlayer();engine.load(game:recorder.game)
        precondition(engine.tryPlayMove(color:.black,x:4,y:4)==nil)
        for _ in 0..<8 {observe(engine.board)}
        precondition(recorder.moveCount==1)
        let measured=events.compactMap {$0["moveTimings"] as? [[String:Any]]}.flatMap {$0}
        precondition(measured.count==1 && (measured[0]["seconds"] as? Double ?? -1)>0)
        precondition(captures.isEmpty,"Ordinary moves created exception clips")
        info.komi="7.5";info.result="B+R";recorder.updateInfo(info)
        let saved=SGFGame.from(tree:try SGFParser.parse(text:recorder.sgf()))
        precondition(saved.info.playerBlack=="Dave" && saved.info.playerWhite=="相手" && saved.info.komi=="7.5" && saved.info.event==info.event && saved.info.date=="2026-11-06" && saved.info.result=="B+R")
        let count=recorder.moveCount,url=recorder.autosaveURL!
        recorder.finish();precondition(recorder.state == .finished && recorder.moveCount==count && recorder.autosaveURL==url)
        try recorder.flushStorage();recorder.flushDiagnostics()
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:url)
        precondition(restored.game.info.playerWhite=="相手" && restored.moveCount==1)
        reports=try reader.refresh()
        let newReport=reports.first {$0.id==url.deletingPathExtension().appendingPathExtension("observations.jsonl").resolvingSymlinksInPath().path}!
        precondition(newReport.samples.count==1 && newReport.values.count==1)
        // Prolonged placement ambiguity retains the candidate and saves an exception once per threshold.
        let uncertain=GameRecorder(storage:local);uncertain.start(size:9,now:now)
        uncertain.onEvidenceCapture={captures.append($0);return root.appendingPathComponent("test-clip").path}
        for _ in 0..<8 {now += 0.21;uncertain.consume(BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)},size:9),now:now)}
        for _ in 0..<35 {
            now += 0.21
            var view=BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/9,col:$0%9,occupancy:$0==40 ? .black:.empty,confidence:1,delta:0)},size:9)
            view.placementFits=[.init(row:4,col:4,center:.init(x:4.49,y:4),radiusCol:0.46,radiusRow:0.46,quality:1)];uncertain.consume(view,now:now)
        }
        precondition(!captures.isEmpty,"Uncertain local move did not request a clip")
        let countBefore=uncertain.moveCount,pendingBefore=uncertain.pendingMoveCount
        uncertain.updateInfo(info)
        precondition(uncertain.pendingMoveCount==pendingBefore && pendingBefore>0,"Info edits changed pending history")
        uncertain.finish();precondition(uncertain.state != .finished && uncertain.moveCount==countBefore,"End game discarded pending moves")
        print("PASS: local explicit timings, no normal-move clips, uncertain-move trigger, SGF metadata and escaping round trip, End game preservation and pending-move protection")
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        precondition(model.newGameInfo.date==SGFGame.Info.formattedGameDate(Date()))
        let host=NSHostingView(rootView:GameInfoView(model:model,recorder:model.recorder).frame(width:550,height:600))
        host.frame=NSRect(x:0,y:0,width:550,height:600);host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("work/physical-timing-info/info.png")
        try bitmap.representation(using:.png,properties:[:])!.write(to:output)
        print("PASS: pre-populated date and native Info layout")
    }
    static func tryReports(_ reader:MoveTimingReportReader)->[MoveTimingReport] {try! reader.refresh()}
    static func tryReport(_ reader:MoveTimingReportReader)->MoveTimingReport {tryReports(reader)[0]}
}
