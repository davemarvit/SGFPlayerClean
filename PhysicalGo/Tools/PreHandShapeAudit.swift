import Foundation
import ImageIO

/// Offline image adapter. Input truth labels are deliberately not decoded.
@main struct PreHandShapeAudit {
    struct Frame:Decodable {
        let id:String,image:String,reference:String
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
    }
    static func main()throws {
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func load(_ path:String)throws->GrayFrame {
            guard let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),let gray=GrayFrame(image:image)
            else {throw NSError(domain:"PreHandShapeAudit",code:1)}
            return gray
        }
        var rows=[[String:Any]]()
        for f in frames {
            guard let view=BoardDetector.detect(frame:try load(f.image),reference:try load(f.reference),
                calibration:f.calibration,threshold:f.threshold,referenceCalibration:f.referenceCalibration)
            else {throw NSError(domain:"PreHandShapeAudit",code:2)}
            rows.append(["id":f.id,"readings":try JSONSerialization.jsonObject(with:JSONEncoder().encode(view.readings)),
                         "shapes":try JSONSerialization.jsonObject(with:JSONEncoder().encode(view.footprints+view.placementFits))])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]))
    }
}
