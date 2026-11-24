import Foundation
import ImageIO

enum StoneVoteTrace {
    static var folder:URL!
    static var calls=0
    static func wants(_ reading:IntersectionReading)->Bool {
        reading.occupancy == .white && reading.col==9 && [9,14].contains(reading.row)
    }
    static func save(reading:IntersectionReading,cells:[[Double]],correction:Double,colorShift:BoardChroma,
                     best:StoneFootprint?,searchSteps:Int,shadedWhite:Bool,masking:Int,occlusion:Int)throws {
        let encoder=JSONEncoder()
        var object:[String:Any] = ["point":reading.row*19+reading.col,"cells":cells,
            "columns":["col","row","currentGray","referenceGray","colorCriterion","brightnessCriterion","whiteVote","colorMagnitude","expectedColorMagnitude","red","green","blue","expectedRed","expectedGreen","expectedBlue"],
            "correction":correction,"colorShift":[colorShift.red,colorShift.green,colorShift.blue],
            "searchSteps":searchSteps,"shadedWhite":shadedWhite,"maskingCount":masking,"occlusionCount":occlusion,
            "step":0.04,"side":65,"origin":32,"call":calls]
        if let best {object["best"]=try JSONSerialization.jsonObject(with:encoder.encode(best))}
        let path=folder.appendingPathComponent(String(format:"point-%03d-call-%02d.json",reading.row*19+reading.col,calls));calls += 1
        try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:path)
    }
}

@main struct VoteReplay {
    static func main()throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1])
        let output=URL(fileURLWithPath:CommandLine.arguments[2]);StoneVoteTrace.folder=output
        let id=697
        let events=try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8)
        var frame:[String:Any]?,archived:[String:Any]?
        for line in events.split(separator:"\n") {
            guard let row=try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any],row["frameID"] as? Int==id else {continue}
            if row["event"] as? String=="frame" {frame=row}
            if row["event"] as? String=="operation finished" {archived=row}
        }
        guard let f=frame,let a=archived else {throw NSError(domain:"trace",code:1)}
        func decode<T:Decodable>(_ kind:T.Type,_ value:Any)throws->T {
            try JSONDecoder().decode(kind,from:JSONSerialization.data(withJSONObject:value))
        }
        func pixels(_ relative:String)throws->GrayFrame {
            guard let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(relative) as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),let gray=GrayFrame(image:image) else {throw NSError(domain:"trace",code:2)}
            return gray
        }
        let grid=try decode(BoardCalibration.self,f["calibration"]!),referenceGrid=try decode(BoardCalibration.self,f["referenceCalibration"]!)
        let image=try pixels(f["image"] as! String),reference=try pixels(f["referenceImage"] as! String)
        guard let observation=BoardDetector.detect(frame:image,reference:reference,calibration:grid,threshold:f["threshold"] as! Double,referenceCalibration:referenceGrid) else {throw NSError(domain:"trace",code:3)}
        let encoder=JSONEncoder()
        let fresh=try JSONSerialization.jsonObject(with:encoder.encode(observation.footprints+observation.placementFits))
        let results:[String:Any] = ["frameID":id,"savedFootprints":a["footprints"]!,"replayedFootprints":fresh,
            "replayedReadings":try JSONSerialization.jsonObject(with:encoder.encode(observation.readings)),"traceCalls":StoneVoteTrace.calls]
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-replay.json"))
        print("Native trace completed: \(StoneVoteTrace.calls) White fit calls")
    }
}
