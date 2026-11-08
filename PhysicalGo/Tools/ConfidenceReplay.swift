import Foundation
import ImageIO

/// Read-only adapter to the production detector, rules parser, and grid finder.
@main struct ConfidenceReplay {
    typealias Object = [String: Any]
    static func failure(_ message: String) -> NSError {
        NSError(domain:"ConfidenceReplay", code:1, userInfo:[NSLocalizedDescriptionKey:message])
    }
    static func decode<T:Decodable>(_ type:T.Type, _ value:Any?) throws -> T {
        guard let value else { throw failure("Missing input for \(type)") }
        return try JSONDecoder().decode(type, from:JSONSerialization.data(withJSONObject:value))
    }
    static func image(_ url:URL) throws -> CGImage {
        guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(src,0,nil) else { throw failure("Cannot read \(url.path)") }
        return image
    }
    static func replay(folder:URL, wanted:Set<Int>) throws -> [Object] {
        var frames=[Int:Object](), results=[Object](), seen=Set<Int>(), references=[String:GrayFrame]()
        func pixels(_ relative:String) throws -> GrayFrame {
            let file=folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(folder.path+"/"), let frame=GrayFrame(image:try image(file)) else {
                throw failure("Invalid frame asset \(relative)")
            }
            return frame
        }
        let log=try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8)
        for line in log.split(separator:"\n") {
            guard let e=try JSONSerialization.jsonObject(with:Data(line.utf8)) as? Object,
                  let id=e["frameID"] as? Int, wanted.contains(id) else {continue}
            if e["event"] as? String=="frame" {frames[id]=e}
            guard e["outcome"] as? String=="delivered to recorder" else {continue}
            guard seen.insert(id).inserted, let f=frames[id], let filename=f["image"] as? String,
                  let threshold=f["threshold"] as? Double, let archived=e["readings"] as? [Object] else {
                throw failure("Missing or duplicate analyzed frame \(id)")
            }
            let grid=try decode(BoardCalibration.self,e["calibration"]), frame=try pixels(filename)
            let view:BoardObservation
            if let ref=f["referenceImage"] as? String {
                if references[ref]==nil { references[ref]=try pixels(ref) }
                guard let reference=references[ref],let detected=BoardDetector.detect(frame:frame,reference:reference,
                    calibration:grid,threshold:threshold,referenceCalibration:try decode(BoardCalibration.self,f["referenceCalibration"])) else {
                    throw failure("Invalid reference at frame \(id)")
                }
                view=detected
            } else {
                view=BoardAppearanceDetector.detect(frame:frame,calibration:grid,threshold:threshold)
            }
            let savedFits=(e["footprints"] as? [Object] ?? []) + (e["placementFits"] as? [Object] ?? [])
            results.append(["id":id,"old":archived,"oldShapes":savedFits,
                "new":try JSONSerialization.jsonObject(with:JSONEncoder().encode(view.readings)),
                "newShapes":try JSONSerialization.jsonObject(with:JSONEncoder().encode(view.footprints+view.placementFits))])
        }
        guard seen==wanted else { throw failure("Missing labeled frames: \(wanted.subtracting(seen).sorted())") }
        return results
    }
    struct Corpus: Decodable {
        struct Frame: Decodable {
            let session:String, frame:Int, image:String, reference:String
            let calibration:BoardCalibration, reference_calibration:BoardCalibration
            let threshold:Double
        }
        let cases:[Frame]
    }
    static func corpus(_ folder:URL) throws -> [Object] {
        let manifest=try JSONDecoder().decode(Corpus.self, from:Data(contentsOf:folder.appendingPathComponent("manifest.json")))
        func pixels(_ relative:String) throws -> GrayFrame {
            let url=folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(folder.path+"/"), let result=GrayFrame(image:try image(url)) else {
                throw failure("Invalid fixture asset: \(relative)")
            }
            return result
        }
        var output=[Object](), references=[String:GrayFrame]()
        for frame in manifest.cases {
            if references[frame.reference]==nil {references[frame.reference]=try pixels(frame.reference)}
            guard let ref=references[frame.reference],
                  let result=BoardDetector.detect(frame:try pixels(frame.image), reference:ref,
                    calibration:frame.calibration,threshold:frame.threshold,referenceCalibration:frame.reference_calibration) else {
                throw failure("Invalid calibration or reference for \(frame.session) frame \(frame.frame)")
            }
            output.append(["session":frame.session,"frame":frame.frame,
                "readings":try JSONSerialization.jsonObject(with:JSONEncoder().encode(result.readings)),
                "shapes":try JSONSerialization.jsonObject(with:JSONEncoder().encode(result.footprints+result.placementFits))])
        }
        return output
    }
    static func main() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        let value:Any
        switch args.first {
        case "corpus" where args.count==2:
            value=try corpus(URL(fileURLWithPath:args[1]).standardizedFileURL.resolvingSymlinksInPath())
        case "frames" where args.count==3:
            let ids=try args[2].split(separator:",").map { id -> Int in
                guard let n=Int(id) else {throw failure("Invalid frame ID")};return n
            }
            value=try replay(folder:URL(fileURLWithPath:args[1]).standardizedFileURL.resolvingSymlinksInPath(),wanted:Set(ids))
        case "grid" where args.count==3:
            guard let size=Int(args[2]) else {throw failure("Invalid board size")}
            let input=try image(URL(fileURLWithPath:args[1]))
            if let grid=try AutoGridDetector.detect(image:input,size:size) {
                value=["quality":grid.quality,"pixels":grid.calibration.corners.map {
                    [$0.x*Double(input.width-1),$0.y*Double(input.height-1)]
                }] as Object
            } else { value=NSNull() }
        case "moves" where args.count==2:
            let tree=try SGFParser.parse(text:String(contentsOfFile:args[1],encoding:.utf8))
            let game=SGFGame.from(tree:tree)
            value=game.moves.map { move -> Any in
                guard let p=move.1 else {return NSNull()}
                return p.1*game.boardSize+p.0
            }
        default: throw failure("Use corpus FIXTURE | frames SESSION ID,... | grid IMAGE SIZE | moves SGF")
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]))
    }
}
