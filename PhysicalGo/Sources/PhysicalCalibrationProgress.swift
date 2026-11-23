import Foundation

/// Display-only status; it cannot authorize light, accept a binding or start play.
struct PhysicalCalibrationProgress: Decodable, Equatable {
    let schemaVersion:Int
    let runID:String
    let sequence:Int
    let startedAtUnix:Double
    let startedAtUptime:Double
    let updatedAtUnix:Double
    let elapsedSeconds:Double
    let stageElapsedSeconds:Double
    let state:String
    let stage:String
    let mode:String
    let target:String?
    let fitCompleted:Int
    let fitTotal:Int
    let validationCompleted:Int
    let validationTotal:Int
    let bindingActivated:Bool

    var completed:Int {fitCompleted+validationCompleted}
    var total:Int {fitTotal+validationTotal}
    var running:Bool {state == "running"}
    var stageTitle:String {
        switch stage {
        case "starting":return "Preparing calibration"
        case "waiting_camera":return "Waiting for a clear board image"
        case "grid":return "Locating the board grid"
        case "locating":return "Locating the laser spot"
        case "fit":return "Calibrating \(target ?? "board points")"
        case "validation":return "Checking accuracy at \(target ?? "board points")"
        case "shutdown":return "Finishing and turning the pointer off"
        case "model_review":return "Checking the measured laser map"
        default:return "Calibration"
        }
    }
    func valid(now:Double)->Bool {
        let numbers=[startedAtUnix,startedAtUptime,updatedAtUnix,elapsedSeconds,stageElapsedSeconds]
        guard schemaVersion == 1,UUID(uuidString:runID) != nil,sequence>0,
              numbers.allSatisfy({$0.isFinite && $0>=0}),
              startedAtUnix<=updatedAtUnix,updatedAtUnix<=now+2,
              elapsedSeconds<=86_400,stageElapsedSeconds<=elapsedSeconds+0.1,!bindingActivated,
              ["running","stopped","off_unconfirmed","candidate_ready","spot_verified"].contains(state),
              ["starting","waiting_camera","grid","locating","fit","validation","shutdown","model_review"].contains(stage),
              fitCompleted>=0,validationCompleted>=0,
              fitCompleted<=fitTotal,validationCompleted<=validationTotal else {return false}
        if let target {
            let columns="ABCDEFGHJKLMNOPQRST"
            guard let first=target.first,columns.contains(first),let row=Int(target.dropFirst()),(1...19).contains(row),target == "\(first)\(row)" else {return false}
        }
        if mode == "full_calibration" {
            guard fitTotal == 5,validationTotal == 9,state != "spot_verified" else {return false}
            if state == "candidate_ready" && completed != total {return false}
        } else if mode == "spot_check" {
            guard total == 0,fitTotal == 0,validationTotal == 0,state != "candidate_ready" else {return false}
        } else {return false}
        return true
    }
}

struct PhysicalCalibrationProgressReader {
    private(set) var latest:PhysicalCalibrationProgress?
    private(set) var unavailable=false
    static let url=FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Physical Go/LaserBridge/calibration-progress.json")

    static func read(_ url:URL)->Data? {
        guard let handle=try? FileHandle(forReadingFrom:url) else {return nil}
        defer {try? handle.close()}
        guard let data=try? handle.read(upToCount:65_537),data.count<=65_536 else {return nil}
        return data
    }
    mutating func accept(_ data:Data?,now:Double) {
        guard let data,data.count<=65_536,
              let next=try? JSONDecoder().decode(PhysicalCalibrationProgress.self,from:data),next.valid(now:now) else {
            unavailable = latest != nil
            return
        }
        if let old=latest {
            if next.runID == old.runID {
                guard next.startedAtUnix == old.startedAtUnix,next.startedAtUptime == old.startedAtUptime,
                      (next.sequence>old.sequence || next == old),
                      next.fitCompleted>=old.fitCompleted,next.validationCompleted>=old.validationCompleted,
                      next.elapsedSeconds>=old.elapsedSeconds,
                      old.running || (!next.running && next.state == old.state) else {unavailable=true;return}
            } else {
                // A delayed writer cannot make a previous run current again.
                guard next.startedAtUnix>old.startedAtUnix else {unavailable=true;return}
            }
        }
        latest=next;unavailable=false
    }
    func interrupted(now:Double)->Bool {
        guard let latest else {return false}
        return unavailable || (latest.running && (now-latest.updatedAtUnix>3 || now<latest.updatedAtUnix-2))
    }
}
