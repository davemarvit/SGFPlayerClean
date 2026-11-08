import Foundation

/// Reads compact timing events without inferring when a hand physically placed a stone.
struct MoveTimingSample: Identifiable {
    var id:String, point:Int?, size:Int, color:String, number:Int?, time:Double
    var seconds:Double?, serverSeconds:Double?, unavailable:String?
}
struct MoveTimingReview: Identifiable {
    var id:String, time:Double, reason:String, folder:String?, point:Int?, size:Int
}
struct MoveTimingReport: Identifiable {
    var id:String, mode:String, title:String, time:Double, files:[URL]
    var samples:[MoveTimingSample], reviews:[MoveTimingReview]
    var values:[Double] {samples.compactMap(\.seconds).sorted()}
    var average:Double? {values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)}
    func percentile(_ fraction:Double)->Double? {
        let v=values
        guard !v.isEmpty else {return nil}
        let position=Double(v.count-1)*fraction,lower=Int(position),upper=min(lower+1,v.count-1)
        return v[lower]+(v[upper]-v[lower])*(position-Double(lower))
    }
    var bins:[Int] {
        var counts=Array(repeating:0,count:5)
        for value in values {counts[value<1 ? 0 : value<2 ? 1 : value<3 ? 2 : value<5 ? 3 : 4] += 1}
        return counts
    }
}

/// Incremental per-file parser. No frame images or full observation history are retained.
struct MoveTimingFile {
    var mode:String, url:URL
    var reportID:String = "",title:String = "",time:Double=0
    var samples=[String:MoveTimingSample](),reviews=[String:MoveTimingReview]()
    private var acknowledgments=[String:Double]()
    private var localCount=0
    private struct LegacyCandidate {let point:Int,size:Int,first:Double;let color:String}
    private var legacyCandidates=[Int:LegacyCandidate]()
    private var wallOffset:Double?
    init(mode:String,url:URL) {self.mode=mode;self.url=url}
    static func finite(_ value:Any?)->Double? {
        guard let number=value as? Double,number.isFinite,number>=0 else {return nil};return number
    }
    mutating func consume(_ row:[String:Any]) {
        let event=row["event"] as? String ?? "",stamp=Self.finite(row["time"]) ?? 0
        time=max(time,stamp)
        if mode == "online" {
            guard let game=row["game"] as? Int,game>0 else {return}
            reportID="online-\(game)";title="OGS game \(game)"
            let key="\(row["run"] as? String ?? url.lastPathComponent)/\(row["attempt"] as? String ?? "")"
            if event == "server_acknowledged",let seconds=Self.finite(row["requestToObservationSeconds"]) {
                acknowledgments[key]=seconds;samples[key]?.serverSeconds=seconds
            }
            if event == "move_request_written" {
                samples[key]=MoveTimingSample(id:key,point:row["point"] as? Int,size:row["size"] as? Int ?? 19,
                    color:row["color"] as? String ?? "",number:nil,time:stamp,
                    seconds:Self.finite(row["recognitionToRequestSeconds"]),serverSeconds:acknowledgments[key])
            }
            if event == "slow_move" || event == "uncertain_move" || row["evidenceCaptureFolder"] != nil {
                let reviewKey=key+"/"+event
                reviews[reviewKey]=MoveTimingReview(id:reviewKey,time:stamp,
                    reason:event == "slow_move" ? "Slow confirmation (5 seconds or more)" : event == "uncertain_move" ? "Uncertain candidate" : "Move evidence",
                    folder:row["evidenceCaptureFolder"] as? String,point:row["point"] as? Int,size:row["size"] as? Int ?? 19)
            }
        } else {
            reportID=url.resolvingSymlinksInPath().path;title="Local game"
            let count=row["moveCount"] as? Int ?? localCount
            if event == "undo" {
                samples=samples.filter {($0.value.number ?? 0)<=count};localCount=count
            }
            if event == "paused" || event == "resumed" || event == "restored saved game" || event.hasPrefix("vision interrupted") || event == "undo" {legacyCandidates=[:]}
            if let uptime=Self.finite(row["uptime"]) {
                let offset=stamp-uptime
                if let previous=wallOffset,abs(offset-previous)>1 {legacyCandidates=[:]}
                wallOffset=offset
            }
            if event == "observation",row["state"] as? String == "recording" {
                let size=row["size"] as? Int ?? 19,position=Array((row["position"] as? String ?? "").utf8)
                var visible=Set<Int>()
                for (offset,value) in (row["tentativeConfidence"] as? [[String:Any]] ?? []).enumerated() {
                    let number=count+offset+1
                    guard value["orderSupported"] as? Bool == true,let point=value["point"] as? Int else {legacyCandidates[number]=nil;continue}
                    visible.insert(number)
                    if legacyCandidates[number]?.point != point {
                        let color=position.indices.contains(point) ? position[point]==66 ? "black" : position[point]==87 ? "white" : "" : ""
                        legacyCandidates[number]=LegacyCandidate(point:point,size:size,first:stamp,color:color)
                    }
                }
                legacyCandidates=legacyCandidates.filter {visible.contains($0.key)}
            }
            let timings=row["moveTimings"] as? [[String:Any]] ?? []
            for value in timings {
                guard let number=value["moveNumber"] as? Int else {continue}
                let key="\(number)"
                samples[key]=MoveTimingSample(id:key,point:value["point"] as? Int,size:value["size"] as? Int ?? 19,
                    color:value["color"] as? String ?? "",number:number,time:stamp,seconds:Self.finite(value["seconds"]),
                    unavailable:value["unavailableReason"] as? String)
            }
            if event.hasPrefix("accepted") || event == "manual move" {
                if count>localCount {
                    for number in (localCount+1)...count where samples[String(number)] == nil {
                        if event != "manual move",let candidate=legacyCandidates[number],stamp>=candidate.first {
                            samples[String(number)]=MoveTimingSample(id:String(number),point:candidate.point,size:candidate.size,color:candidate.color,
                                number:number,time:stamp,seconds:stamp-candidate.first,unavailable:"Estimate from logged candidate observations")
                        } else {
                            samples[String(number)]=MoveTimingSample(id:String(number),point:nil,size:19,color:"",number:number,time:stamp,
                                unavailable:event == "manual move" ? "Manual move or pass; excluded" : "No comparable candidate timing; excluded")
                        }
                    }
                }
                localCount=count;legacyCandidates=legacyCandidates.filter {$0.key>count}
            }
            for value in row["moveReviews"] as? [[String:Any]] ?? [] {
                let reason=value["reason"] as? String ?? "Unresolved candidate"
                let key="\(stamp)/\(value["moveNumber"] as? Int ?? 0)/\(reason)"
                reviews[key]=MoveTimingReview(id:key,time:stamp,reason:reason,folder:value["evidenceCaptureFolder"] as? String,
                    point:value["point"] as? Int,size:value["size"] as? Int ?? 19)
            }
        }
    }
    var report:MoveTimingReport? {
        guard !reportID.isEmpty else {return nil}
        return MoveTimingReport(id:reportID,mode:mode,title:title,time:time,files:[url],
            samples:samples.values.sorted {$0.time == $1.time ? ($0.number ?? 0)<($1.number ?? 0) : $0.time<$1.time},
            reviews:reviews.values.sorted {$0.time>$1.time})
    }
}

/// Owned by one serial background queue; refresh reads only newly appended bytes.
final class MoveTimingReportReader: @unchecked Sendable {
    private let lock=NSLock()
    private struct Cursor {
        var offset:UInt64=0,pending=Data(),file:MoveTimingFile
        var modified:Date?
    }
    private var cursors=[URL:Cursor]()
    let onlineRoot:URL,localRoot:URL
    init(onlineRoot:URL,localRoot:URL) {self.onlineRoot=onlineRoot;self.localRoot=localRoot}
    func refresh() throws -> [MoveTimingReport] {
        lock.lock();defer {lock.unlock()}
        var present=Set<URL>()
        for (root,mode) in [(onlineRoot,"online"),(localRoot,"local")] {
            guard FileManager.default.fileExists(atPath:root.path) else {continue}
            let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey])
            for url in files where mode == "online" ? url.pathExtension == "jsonl" : url.lastPathComponent.hasSuffix(".observations.jsonl") {
                present.insert(url)
                let info=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
                let size=UInt64(info.fileSize ?? 0)
                var cursor=cursors[url] ?? Cursor(file:MoveTimingFile(mode:mode,url:url))
                if size<cursor.offset || (size==cursor.offset && cursor.modified != nil && cursor.modified != info.contentModificationDate) {
                    cursor=Cursor(file:MoveTimingFile(mode:mode,url:url))
                }
                if size>cursor.offset {
                    let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
                    try handle.seek(toOffset:cursor.offset)
                    while cursor.offset<size {
                        let data=try handle.read(upToCount:Int(min(65536,size-cursor.offset))) ?? Data()
                        if data.isEmpty {break}
                        cursor.offset += UInt64(data.count);cursor.pending.append(data)
                        while let end=cursor.pending.firstIndex(of:10) {
                            let line=cursor.pending.prefix(upTo:end)
                            if let row=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] {cursor.file.consume(row)}
                            cursor.pending.removeSubrange(...end)
                        }
                    }
                }
                cursor.modified=info.contentModificationDate;cursors[url]=cursor
            }
        }
        cursors=cursors.filter {present.contains($0.key)}
        let grouped=Dictionary(grouping:cursors.values.compactMap {$0.file.report},by: { $0.id })
        return grouped.values.map {parts in
            var report=parts[0]
            report.time=parts.map(\.time).max() ?? 0
            report.files=parts.flatMap(\.files)
            report.samples=Dictionary(parts.flatMap(\.samples).map {($0.id,$0)},uniquingKeysWith:{a,b in b.serverSeconds == nil ? a:b}).values.sorted {
                $0.time == $1.time ? ($0.number ?? 0)<($1.number ?? 0) : $0.time<$1.time
            }
            report.reviews=Dictionary(parts.flatMap(\.reviews).map {($0.id,$0)},uniquingKeysWith:{_,b in b}).values.sorted {$0.time>$1.time}
            return report
        }.sorted {$0.time>$1.time}
    }
}
