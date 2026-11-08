import Foundation

/// Offline recovery into a NEW file. Never modifies the source game or journal.
@main struct ReplayRecording {
    @MainActor static func main() throws {
        let args=CommandLine.arguments
        guard args.count==4 else {fatalError("Usage: ReplayRecording saved.sgf observations.jsonl recovered.sgf")}
        let source=URL(fileURLWithPath:args[1]),journal=URL(fileURLWithPath:args[2]),output=URL(fileURLWithPath:args[3])
        guard !FileManager.default.fileExists(atPath:output.path),!FileManager.default.fileExists(atPath:output.deletingPathExtension().appendingPathExtension("observations.jsonl").path) else {fatalError("Recovery output already exists")}
        try FileManager.default.copyItem(at:source,to:output)
        let recorder=GameRecorder(storage:nil);try recorder.restoreSavedGame(from:output)
        let starting=recorder.moveCount
        recorder.resume()
        var frames=0
        for line in try String(contentsOf:journal,encoding:.utf8).split(separator:"\n") {
            let entry=try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
            guard entry["event"] as? String == "observation",let signature=entry["position"] as? String,
                  let time=entry["uptime"] as? Double,let size=entry["size"] as? Int else {continue}
            let states=Array(signature)
            guard states.count==size*size else {fatalError("Malformed observation")}
            recorder.consume(BoardObservation(readings:states.enumerated().map { i,c in
                IntersectionReading(row:i/size,col:i%size,occupancy:c == "B" ? .black : c == "W" ? .white : c == "?" ? .uncertain : .empty,confidence:1,delta:0)
            },size:size,notice:entry["detectionNotice"] as? String,lightingBlocked:entry["lightingBlocked"] as? Bool ?? false),now:time)
            frames += 1
        }
        print("Replayed \(frames) frames: \(starting) → \(recorder.moveCount) saved moves; \(recorder.pendingMoveCount) pending.")
        print(recorder.status)
        print("Recovery copy: \(output.path)")
    }
}
