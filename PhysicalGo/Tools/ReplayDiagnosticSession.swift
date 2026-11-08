import Foundation
import CoreGraphics
import ImageIO

/// Sequential, offline replay. Keeps recorded grid decisions and control events,
/// reruns pixels through detection, and sends observations to the real recorder.
/// Writes only into a NEW output folder; never changes the diagnostic archive.
@main struct ReplayDiagnosticSession {
    @MainActor static func main() throws {
        let args=CommandLine.arguments
        guard args.count==3 || args.count==4 && ["--saved-observations","--allow-missing-frames"].contains(args[3]) else {
            throw error("Usage: ReplayDiagnosticSession archive new-output-folder [--saved-observations | --allow-missing-frames]")
        }
        let savedOnly=args.last=="--saved-observations"
        let allowMissing=args.last=="--allow-missing-frames"
        let folder=URL(fileURLWithPath:args[1]).standardizedFileURL.resolvingSymlinksInPath()
        let output=URL(fileURLWithPath:args[2]).standardizedFileURL.resolvingSymlinksInPath()
        guard !output.path.hasPrefix(folder.path+"/"),output != folder,!FileManager.default.fileExists(atPath:output.path) else {
            throw error("Output must be a new folder outside the original archive")
        }
        func decode<T:Decodable>(_ value:Any?,_ type:T.Type)throws->T {
            guard let value else {throw error("Missing \(type)")}
            return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
        }
        func load(_ relative:String)throws->GrayFrame {
            let path=folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            guard path.path.hasPrefix(folder.path+"/"),let source=CGImageSourceCreateWithURL(path as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),let frame=GrayFrame(image:image) else {throw error("Cannot load \(relative)")}
            return frame
        }
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("session.json"))) as! [String:Any]
        let entries=try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        guard let initial=manifest["recorder"] as? [String:Any],let initialState=initial["state"] as? String,["idle","verifying","recording","paused"].contains(initialState),
              let initialMoves=initial["moveCount"] as? Int,initial["pendingMoves"] as? Int == 0,
              let size=manifest["boardSize"] as? Int,[9,13,19].contains(size),
              let first=entries.first(where:{$0["event"] as? String == "frame"}),let firstTime=first["captureUptime"] as? Double else {
            throw error("This replay requires a supported initial game state and no pending moves")
        }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let recorder=GameRecorder(storage:output)
        let empty=BoardObservation(readings:(0..<size*size).map{.init(row:$0/size,col:$0%size,occupancy:.empty,confidence:1,delta:0)},size:size)
        // Reconstruct the already-verified initial empty board, not a move.
        if initialMoves>0 {
            guard let sgf=manifest["initialSGF"] as? String,["paused","recording"].contains(initialState) else {throw error("Missing initial SGF for the existing game")}
            let seed=output.appendingPathComponent("Replayed game.sgf")
            try sgf.write(to:seed,atomically:true,encoding:.utf8)
            try recorder.restoreSavedGame(from:seed)
            guard recorder.moveCount==initialMoves,recorder.game.boardSize==size else {throw error("Initial SGF does not match diagnostic metadata")}
            if initialState=="recording" {recorder.resume()}
        } else if initialState == "recording" {
            for i in 0..<6 {recorder.consume(empty,now:firstTime-2+Double(i)*0.21)}
            recorder.start(size:size,now:firstTime-0.9)
            guard recorder.state == .recording else {throw error("Could not restore initial recording state")}
        } else if initialState == "verifying" {recorder.start(size:size,now:firstTime-0.01)}
        var frames=[Int:[String:Any]](),operations=[Int:[String:Any]](),references=[String:GrayFrame]()
        var reports=[[String:Any]](),accepted=[[String:Any]](),processed=0,rejected=0
        var missingFrames=[Int]()
        var currentFrame=0
        var placementChimes=[[String:Any]]()
        recorder.onPlacementChime={ issues in
            placementChimes.append(["frameID":currentFrame,"moves":issues.map(\.move),"points":issues.map(\.point)])
        }
        recorder.onDiagnosticEvent={ decision in
            if let event=decision["event"] as? String,event.hasPrefix("accepted") {
                var row=decision;row["frameID"]=currentFrame;accepted.append(row)
            }
        }
        let start=Date()
        for entry in entries {
            switch entry["event"] as? String {
            case "frame": frames[entry["frameID"] as! Int]=entry
            case "operation started":
                operations[entry["operationID"] as! Int]=entry
            case "recorder":
                guard let decision=entry["decision"] as? [String:Any],let event=decision["event"] as? String else {continue}
                if event=="paused" {recorder.pause()}
                else if event=="resumed" {recorder.resume()}
                else if event=="finished" {recorder.finish()}
                else if event.hasPrefix("vision interrupted:") {
                    if !event.contains("Checking that the physical board matches") {
                        recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid") || event.contains("after a camera interruption"))
                    }
                } else if event=="start", !recorder.hasGame,let time=entry["uptime"] as? Double {
                    recorder.start(size:size,now:time)
                } else if event=="manual move" || event=="start" || event=="restored saved game" {
                    throw error("Unsupported mid-session game edit: \(event)")
                }
            case "operation finished":
                guard let operation=operations[entry["operationID"] as! Int],operation["kind"] as? String == "analysis",
                      let id=entry["frameID"] as? Int,let frame=frames[id] else {continue}
                currentFrame=id
                guard entry["outcome"] as? String == "delivered to recorder" else {rejected += 1;continue}
                guard let time=entry["recorderUptime"] as? Double else {throw error("Missing recorder timestamp")}
                var observation:BoardObservation
                let began=Date()
                if savedOnly {
                    observation=BoardObservation(readings:try decode(entry["readings"],[IntersectionReading].self),size:size,footprints:try decode(entry["footprints"] as? [Any] ?? [],[StoneFootprint].self),placementFits:try decode(entry["placementFits"] as? [Any] ?? [],[StoneFootprint].self))
                    observation.lightingBlocked=entry["lightingBlocked"] as? Bool ?? false
                    observation.notice=entry["notice"] as? String
                } else {
                    if allowMissing,!FileManager.default.fileExists(atPath:folder.appendingPathComponent(frame["image"] as! String).path) {
                        missingFrames.append(id)
                        // A pruned archive is not continuous footage. Never fill
                        // the gap with old classifications or invented frames.
                        recorder.suspendVision("Missing archived camera frame",preserveObservations:true)
                        continue
                    }
                    let pixels=try load(frame["image"] as! String)
                    let calibration=try decode(entry["calibration"],BoardCalibration.self)
                    if let file=frame["referenceImage"] as? String {
                        if references[file]==nil {references[file]=try load(file)}
                        guard let detected=BoardDetector.detect(frame:pixels,reference:references[file]!,calibration:calibration,
                            threshold:operation["threshold"] as! Double,referenceCalibration:try decode(operation["referenceCalibration"],BoardCalibration.self)) else {throw error("Invalid reference")}
                        observation=detected
                    } else {observation=BoardAppearanceDetector.detect(frame:pixels,calibration:calibration,threshold:operation["threshold"] as! Double)}
                }
                let milliseconds=Date().timeIntervalSince(began)*1000
                recorder.consume(observation,now:time);processed += 1
                reports.append(["frameID":id,"uptime":time,"position":observation.signature.map{$0 == .black ? "B" : $0 == .white ? "W" : $0 == .uncertain ? "?" : "."}.joined(),
                    "moveCount":recorder.moveCount,"pending":recorder.pendingMoveCount,"status":recorder.status,"detectionMilliseconds":milliseconds,
                    "placementOffsets":Dictionary(uniqueKeysWithValues:observation.placementOffsets.map{(String($0.key),$0.value)}),
                    "placementWarnings":observation.ambiguousPlacements.sorted(),
                    "savedMoveCount":(entry["recorder"] as? [String:Any])?["moveCount"] ?? NSNull()])
                if processed%50==0 {print("Replayed \(processed) observations; \(recorder.moveCount) moves saved");fflush(stdout)}
            default: break
            }
        }
        func write(_ value:Any,_ name:String)throws {
            try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent(name),options:.atomic)
        }
        try recorder.savePendingCheckpoint()
        try write(placementChimes,"placement-chimes.json")
        try write(reports,"frames.json");try write(accepted,"accepted.json")
        try write(["archive":folder.path,"mode":savedOnly ? "saved observations" : "pixels with recorded alignment and control events",
            "processed":processed,"rejectedOrSkipped":rejected,"missingFrames":missingFrames,
            "initialMoves":initialMoves,"moves":recorder.moveCount,"status":recorder.status,
            "savedPoints":recorder.game.moves.map { move -> Any in move.1.map{$0.1*size+$0.0} ?? NSNull() },
            "pendingPoints":recorder.pendingConfidence.compactMap(\.point),
            "pendingPlacementPoints":recorder.pendingConfidence.filter(\.placementUncertain).compactMap(\.point),
            "elapsedSeconds":Date().timeIntervalSince(start),"sgf":recorder.autosaveURL?.lastPathComponent ?? ""],"summary.json")
        print("Replayed \(processed) observations; \(rejected) rejected/skipped operations; \(recorder.moveCount) moves saved.\n\(recorder.status)\nOutput: \(output.path)")
    }
    static func error(_ text:String)->NSError {NSError(domain:"PhysicalGo.ReplaySession",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
