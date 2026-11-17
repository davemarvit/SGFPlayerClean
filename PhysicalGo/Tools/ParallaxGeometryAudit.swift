import Foundation
import ImageIO

/// Independent native reference for the Python assignment-policy port.
@main struct ParallaxGeometryAudit {
    struct Frame:Decodable {
        let id:String,image:String,reference:String
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double,before:[Occupancy],targets:[Int]
    }
    static func main()throws {
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func load(_ path:String)throws->GrayFrame {
            guard let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),let gray=GrayFrame(image:image) else {throw NSError(domain:"ParallaxGeometryAudit",code:1)}
            return gray
        }
        func value<T:Encodable>(_ v:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(v))}
        var rows=[[String:Any]]()
        for f in frames {
            guard let view=BoardDetector.detect(frame:try load(f.image),reference:try load(f.reference),calibration:f.calibration,threshold:f.threshold,referenceCalibration:f.referenceCalibration) else {throw NSError(domain:"ParallaxGeometryAudit",code:2)}
            rows.append(["id":f.id,"before":try value(f.before),"targets":f.targets,"readings":try value(view.readings),"shapes":try value(view.footprints+view.placementFits),"assignmentOffsets":try value(view.assignmentOffsets(confirmedBoard:f.before))])
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]),as:UTF8.self))
    }
}
