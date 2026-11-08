import Foundation
@main struct HistoricalDecisionReplay {
    @MainActor static func main() throws {
        let input=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:input)) as! [[String:Any]]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let dirs=[root.appendingPathComponent("old"),root.appendingPathComponent("new")]
        for d in dirs {try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)}
        let old=LegacyOnlineBoard(directory:dirs[0],announceOpponent:{},announceCorrection:{})
        let new=PhysicalOnlineBoard(directory:dirs[1],announceOpponent:{},announceCorrection:{})
        old.enabled=true;new.enabled=true
        var board:[String]?,lastPoint:Int?,version=0,turn:Bool?,start:Double?,anchored=false
        var events=[[String:Any]](),firstSight=[String:Double]()
        func view(_ values:[String],size:Int,turns:Int)->BoardObservation {
            .init(readings:values.indices.map{.init(row:$0/size,col:$0%size,occupancy:Occupancy(rawValue:values[PhysicalMoveInference.displayedPoint(row:$0/size,col:$0%size,size:size,quarterTurns:turns)])!,confidence:1,delta:0)},size:size)
        }
        for (index,row) in rows.enumerated() {
            guard let next=(row["resolvedBoard"] as? [String]) ?? (row["board"] as? [String]),
                  let time=row["uptime"] as? Double,let n=row["size"] as? Int,let myTurn=row["myTurn"] as? Bool else {continue}
            let turns=row["quarterTurns"] as? Int ?? 0
            if start==nil {start=time}
            if let p=row["lastPoint"] as? Int {lastPoint=p}
            if next != board || turn != myTurn {version += 1;board=next;turn=myTurn;firstSight=[:]}
            let state:[String:Any]=["token":"OFFLINE-REPLAY","game":1,"version":version,"size":n,"cells":next,
                "ready":true,"myTurn":myTurn,"color":"black","lastX":lastPoint.map{$0%n} ?? -1,"lastY":lastPoint.map{$0/n} ?? -1,"time":Date().timeIntervalSince1970]
            for d in dirs {try JSONSerialization.data(withJSONObject:state).write(to:d.appendingPathComponent("state.json"))}
            if !anchored {
                // The source log says the session was already synchronized before
                // this excerpt. Seed that known prior state, not a new camera label.
                guard row["synchronized"] as? Bool==true else {continue}
                old.consume(view(next,size:n,turns:turns),now:time-0.01,quarterTurns:turns);new.consume(view(next,size:n,turns:turns),now:time-0.01,quarterTurns:turns);anchored=true
            }
            if (row["status"] as? String ?? "").contains("Moves paused") {
                old.pauseForCorrection();new.pauseForCorrection();continue
            }
            var camera=next
            for p in row["uncertain"] as? [Int] ?? [] {camera[p]="uncertain"}
            for difference in row["differences"] as? [[String:Any]] ?? [] {
                camera[difference["point"] as! Int]=difference["observed"] as! String
            }
            for p in camera.indices where next[p]=="empty" && camera[p]=="black" {
                if firstSight[String(p)]==nil {firstSight[String(p)]=time}
            }
            var observation=view(camera,size:n,turns:turns)
            if let native=row["nativeReadings"] {
                observation=BoardObservation(readings:try JSONDecoder().decode([IntersectionReading].self,from:JSONSerialization.data(withJSONObject:native)),size:n)
                if let shapes=row["footprints"] {observation.footprints=try JSONDecoder().decode([StoneFootprint].self,from:JSONSerialization.data(withJSONObject:shapes))}
                if let shapes=row["placementFits"] {observation.placementFits=try JSONDecoder().decode([StoneFootprint].self,from:JSONSerialization.data(withJSONObject:shapes))}
            }
            observation.lightingBlocked=row["lightingBlocked"] as? Bool ?? false
            old.consume(observation,now:time,quarterTurns:turns);new.consume(observation,now:time,quarterTurns:turns)
            for (implementation,d) in zip(["0.71 full-board","0.72 historical"],dirs) {
                let move=d.appendingPathComponent("move.json")
                if let data=try? Data(contentsOf:move) {
                    let request=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                    let point=(request["y"] as! Int)*n+(request["x"] as! Int)
                    let nextPosition=rows.dropFirst(index+1).first {r in
                        if let b=r["resolvedBoard"] as? [String] {return b != next};return false
                    }
                    let expected=nextPosition?["lastPoint"] as? Int
                    let after=nextPosition?["resolvedBoard"] as? [String]
                    let verified=expected.map{$0==point && after?[point]=="black"}
                    events.append(["implementation":implementation,"point":point,"version":version,"elapsed":time-start!,
                        "delayFromFirstSeen":time-(firstSight[String(point)] ?? time),"matchesNextRecordedServerMove":verified.map{$0 as Any} ?? NSNull(),
                        "uncertainCount":(row["uncertain"] as? [Int] ?? []).count])
                    try FileManager.default.removeItem(at:move)
                }
            }
        }
        let report:[String:Any]=["source":input.path,"observations":rows.count,"events":events,
            "limits":"Decision-log replay, not raw-image reclassification. Original confidence/geometry and ko maps were not recorded: classifications use confidence=1. Initial established synchronization is seeded from the log. Compare choices against the next recorded server position, not independent human labels. No live server or user files are written."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        for event in events {print(event)}
    }
}
