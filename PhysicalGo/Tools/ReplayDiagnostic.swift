import Foundation
import CoreGraphics
import ImageIO

/// Re-run one archived analysis or grid-search input using its exact saved pixels,
/// reference and tracking anchor. Never writes into the diagnostic session.
@main struct ReplayDiagnostic {
    static func main() throws {
        let args=CommandLine.arguments
        guard args.count==3,let frameID=Int(args[2]) else {fatalError("Usage: ReplayDiagnostic session-folder frame-number")}
        let folder=URL(fileURLWithPath:args[1]).standardizedFileURL
        func path(_ relative:String)throws->URL {
            let url=folder.appendingPathComponent(relative).standardizedFileURL
            guard url.path.hasPrefix(folder.path+"/") else {throw error("Asset path escapes session")}
            return url
        }
        func image(_ relative:String)throws->CGImage {
            let url=try path(relative)
            guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw error("Cannot load \(relative)")}
            return image
        }
        func decode<T:Decodable>(_ value:Any?,_ type:T.Type)throws->T {
            guard let value else {throw error("Missing \(type)")}
            return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
        }
        let lines=try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n")
        var entries=[[String:Any]]()
        for (index,line) in lines.enumerated() {
            do {entries.append(try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any])}
            catch {if index != lines.count-1 {throw error}} // Permit the last in-progress write only.
        }
        guard let saved=entries.first(where:{$0["event"] as? String == "frame" && $0["frameID"] as? Int == frameID}),
              let filename=saved["image"] as? String else {throw error("Frame \(frameID) not saved")}
        let input=try image(filename)
        let operations=entries.filter{$0["event"] as? String == "operation started" && $0["frameID"] as? Int == frameID}
        if operations.isEmpty {
            let skip=entries.first{$0["event"] as? String == "frame skipped" && $0["frameID"] as? Int == frameID}
            print("Frame \(frameID) was saved but not analyzed:",skip?["reason"] ?? "No completed operation logged")
            return
        }
        for operation in operations {
            let id=operation["operationID"] as! Int,kind=operation["kind"] as! String
            let outcome=entries.first{$0["event"] as? String == "operation finished" && $0["operationID"] as? Int == id}
            var report:[String:Any]=["frameID":frameID,"operationID":id,"kind":kind,"savedOutcome":outcome?["outcome"] ?? "incomplete"]
            if kind=="grid search" {
                let result=try AutoGridDetector.detect(image:input,size:operation["boardSize"] as! Int)
                report["foundGrid"]=result != nil;report["calibration"]=value(result?.calibration)
            } else {
                let original=try decode(operation["calibration"],BoardCalibration.self)
                let frame=GrayFrame(image:input)!
                var aligned:BoardCalibration?=original
                if outcome?["checkAlignment"] as? Bool == true {
                    if let anchor=saved["trackingAnchor"] as? [String:Any],let file=anchor["pixels"] as? String,
                       let width=anchor["width"] as? Int,let height=anchor["height"] as? Int,width>0,height>0,width<=8192,height<=8192 {
                        let bytes=try Data(contentsOf:path(file))
                        guard bytes.count==width*height else {throw error("Malformed tracking anchor")}
                        let restored=AutoGridDetector.TrackingAnchor(calibration:try decode(anchor["calibration"],BoardCalibration.self),
                            fittedGrid:try decode(anchor["fittedGrid"],BoardCalibration.self),frame:GrayFrame(width:width,height:height,pixels:Array(bytes)))
                        aligned=AutoGridDetector.track(frame:frame,from:original,anchor:restored)
                    } else {aligned=nil}
                }
                let result:BoardObservation?
                if let aligned {
                    if let referenceFile=saved["referenceImage"] as? String {
                        result=BoardDetector.detect(frame:frame,reference:GrayFrame(image:try image(referenceFile))!,calibration:aligned,
                            threshold:operation["threshold"] as! Double,referenceCalibration:try decode(operation["referenceCalibration"],BoardCalibration.self))
                    } else {result=BoardAppearanceDetector.detect(frame:frame,calibration:aligned,threshold:operation["threshold"] as! Double)}
                } else {result=nil}
                report["alignmentAccepted"]=aligned != nil
                report["calibration"]=value(aligned)
                if let result {
                    report["counts"]=Dictionary(uniqueKeysWithValues:Occupancy.allCases.map{state in (state.rawValue,result.signature.filter{$0==state}.count)})
                    if let savedReadings=outcome?["readings"] as? [[String:Any]] {
                        let previous=try decode(savedReadings,[IntersectionReading].self)
                        let changed=zip(previous,result.readings).filter{$0.occupancy != $1.occupancy}
                        report["classificationMatches"]=changed.isEmpty && previous.count==result.readings.count
                        report["changedIntersections"]=changed.map{["row":$0.row,"col":$0.col,"saved":$0.occupancy.rawValue,"replayed":$1.occupancy.rawValue] as [String:Any]}
                    }
                }
                report["recorderDecision"]=outcome?["recorder"] ?? NSNull()
            }
            let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            print(String(decoding:data,as:UTF8.self))
        }
    }
    static func error(_ text:String)->NSError {NSError(domain:"PhysicalGo.ReplayDiagnostic",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    static func value<T:Encodable>(_ item:T?)->Any {
        guard let item,let data=try? JSONEncoder().encode(item),let result=try? JSONSerialization.jsonObject(with:data) else {return NSNull()}
        return result
    }
}
