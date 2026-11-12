import AppKit
import SwiftUI

@main struct PlayModeTests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("play-modes-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="PhysicalGo.PlayModeTests."+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,
            recordingStorage:root.appendingPathComponent("recordings"),settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"))
        precondition(model.playMode == .local && !model.onlineBoard.enabled && !model.showDiagnostics)
        model.recorder.start(size:19,now:0)
        model.recorder.pause()
        model.recorder.manualMove(at:BoardPosition(3,3))
        try model.recorder.flushStorage()
        let localSGF=model.recorder.sgf(),url=model.recorder.autosaveURL!
        precondition(model.recorder.moveCount==1 && FileManager.default.fileExists(atPath:url.path))
        let game=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:url,encoding:.utf8)))
        precondition(game.boardSize==19 && game.moves.count==1)
        model.recorder.resume()
        let recording=model.recorder.state
        model.showDiagnostics=true
        precondition(model.recorder.state==recording && !model.onlineBoard.enabled && !model.diagnostics.isCapturing)
        model.playMode = .online
        precondition(model.recorder.state == .paused && model.onlineBoard.enabled && model.showDiagnostics)
        model.showDiagnostics=false
        precondition(model.onlineBoard.enabled && model.recorder.sgf()==localSGF)
        model.playMode = .local
        precondition(!model.onlineBoard.enabled && model.recorder.state == .paused && model.recorder.sgf()==localSGF)
        try model.recorder.flushStorage()
        let storedSGF=try String(contentsOf:url,encoding:.utf8)
        precondition(storedSGF==localSGF)
        // Deliver a local observation without touching the online bridge or needing OGS.
        let empty=BoardObservation(readings:(0..<361).map {IntersectionReading(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},size:19)
        model.deliverLiveObservation(empty,now:10)
        precondition(model.onlineBoard.cells.isEmpty)
        model.playMode = .online;model.showDiagnostics=true
        let restored=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,recordingStorage:nil,settings:settings,diagnosticRoot:root)
        precondition(restored.playMode == .online && restored.onlineBoard.enabled && restored.showDiagnostics)
        // Render all four UI combinations, including the shared Save SGF file button.
        let snapshots=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("work/physical-play-modes")
        try FileManager.default.createDirectory(at:snapshots,withIntermediateDirectories:true)
        for mode in PhysicalPlayMode.allCases {
            model.playMode=mode
            for visible in [false,true] {
                model.showDiagnostics=visible
                let host=NSHostingView(rootView:ExperimentView(model:model).frame(width:1400,height:1000))
                host.frame=NSRect(x:0,y:0,width:1400,height:1000);host.layoutSubtreeIfNeeded()
                let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:snapshots.appendingPathComponent("\(mode.rawValue)-\(visible ? "diagnostics":"play").png"))
            }
        }
        print("PASS: local autosave and SGF round trip, pause/preserve on mode switch, independent diagnostics, restored preferences, four native UI renders")
        let bridge=root.appendingPathComponent("bridge")
        try FileManager.default.createDirectory(at:bridge,withIntermediateDirectories:true)
        func state(time:Double=Date().timeIntervalSince1970,supported:Bool=true)throws {
            try JSONSerialization.data(withJSONObject:["game":42,"token":"TEST-ONLY","time":time,"sgfExport":supported,"ready":false])
                .write(to:bridge.appendingPathComponent("state.json"),options:.atomic)
        }
        func expectFailure(_ phrase:String,timeout:Double=0.3) async throws {
            do { _=try await PhysicalSGFExport.download(directory:bridge,timeout:timeout);fatalError("Expected \(phrase)") }
            catch {precondition(error.localizedDescription.contains(phrase),error.localizedDescription)}
        }
        try await expectFailure("Open your game")
        try state(time:0);try await expectFailure("Open your game")
        try state(supported:false);try await expectFailure("needs the physical-board export update")
        try state();try await expectFailure("did not respond")
        precondition(!FileManager.default.fileExists(atPath:bridge.appendingPathComponent("sgf-request.json").path))
        let valid=PhysicalSGFExportRequest(id:UUID(),token:"TEST-ONLY",game:42,time:Date().timeIntervalSince1970)
        precondition(valid.matches(token:"TEST-ONLY",game:42))
        precondition(!valid.matches(token:"wrong",game:42) && !valid.matches(token:"TEST-ONLY",game:43))
        precondition(!valid.matches(token:"TEST-ONLY",game:42,now:valid.time+31))
        for scenario in ["success","error","invalid","wrong-id","wrong-game"] {
            try state()
            let responder=Task {
                let requestURL=bridge.appendingPathComponent("sgf-request.json")
                for _ in 0..<100 {
                    if let data=try? Data(contentsOf:requestURL),let request=try? JSONDecoder().decode(PhysicalSGFExportRequest.self,from:data) {
                        let sgf=scenario == "invalid" ? "<html>failure</html>" : "(;FF[4]GM[1]SZ[19]PB[Black]PW[White];B[dd];W[qq])"
                        let reply=PhysicalSGFExportReply(id:scenario == "wrong-id" ? UUID():request.id,
                            game:scenario == "wrong-game" ? 99:request.game,data:Data(sgf.utf8),filename:"../Game 日本.sgf",
                            error:scenario == "error" ? "Download failed":nil)
                        try JSONEncoder().encode(reply).write(to:bridge.appendingPathComponent("sgf-result.json"),options:.atomic)
                        return
                    }
                    try await Task.sleep(nanoseconds:10_000_000)
                }
                fatalError("Request was never written")
            }
            if scenario == "success" {
                let result=try await PhysicalSGFExport.download(directory:bridge,timeout:2)
                let game=SGFGame.from(tree:try SGFParser.parse(text:String(decoding:result.data,as:UTF8.self)))
                precondition(result.filename=="Game 日本.sgf" && game.moves.count==2)
            } else {
                try await expectFailure(scenario == "error" ? "Download failed" : scenario == "invalid" ? "valid SGF" : "did not respond")
            }
            try await responder.value
        }
        print("PASS: finished-game export, full SGF round trip, Unicode filename sanitization, stale/unsupported client, timeout cleanup, error and invalid content, wrong request/game correlation")
    }
}
