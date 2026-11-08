import Foundation
import ImageIO

@main struct StoneAppearanceAudit {
    struct Corpus:Decodable {
        struct Frame:Decodable {
            let session:String,frame:Int,image:String,reference:String
            let calibration:BoardCalibration,reference_calibration:BoardCalibration
            let threshold:Double
        }
        let cases:[Frame]
    }
    struct Label {let session:String,frame:Int,point:Int,episode:String,truth:String}
    struct Record {
        let label:Label
        let features:StoneAppearanceFeatures
        let trainContext:StoneNeighborContext
        let observedContext:StoneNeighborContext
        let baseline:IntersectionReading
        let geometry:Bool
    }
    static func main()throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        let manifest=try JSONDecoder().decode(Corpus.self,from:Data(contentsOf:folder.appendingPathComponent("manifest.json")))
        let labels=try String(contentsOf:folder.appendingPathComponent("labels.csv"),encoding:.utf8).split(whereSeparator:\.isNewline).dropFirst().map {line -> Label in
            let c=line.split(separator:",").map(String.init)
            return Label(session:c[0],frame:Int(c[2])!,point:Int(c[3])!,episode:c[4],truth:c[5])
        }
        func image(_ relative:String)throws->GrayFrame {
            let url=folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(folder.path+"/"),let src=CGImageSourceCreateWithURL(url as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(src,0,nil),let frame=GrayFrame(image:image) else {throw NSError(domain:"audit",code:1)}
            return frame
        }
        var records=[Record](),references=[String:GrayFrame]()
        for f in manifest.cases {
            let frame=try image(f.image)
            if references[f.reference]==nil {references[f.reference]=try image(f.reference)}
            let reference=references[f.reference]!
            let rows=labels.filter{$0.session==f.session && $0.frame==f.frame}
            let known=Dictionary(uniqueKeysWithValues:rows.compactMap {l -> (Int,Occupancy)? in
                guard let truth=Occupancy(rawValue:l.truth),truth != .uncertain else {return nil};return(l.point,truth)
            })
            guard let view=BoardDetector.detect(frame:frame,reference:reference,calibration:f.calibration,threshold:f.threshold,referenceCalibration:f.reference_calibration) else {throw NSError(domain:"audit",code:2)}
            for l in rows {
                guard let features=StoneAppearanceFeatures.extract(frame:frame,reference:reference,calibration:f.calibration,referenceCalibration:f.reference_calibration,point:l.point) else {throw NSError(domain:"audit",code:3)}
                let shape=(view.footprints+view.placementFits).contains{$0.row==l.point/f.calibration.size && $0.col==l.point%f.calibration.size && $0.quality>=0.85}
                records.append(Record(label:l,features:features,
                    trainContext:StoneNeighborContext.measure(point:l.point,size:f.calibration.size,known:known),
                    observedContext:StoneNeighborContext.observed(point:l.point,observation:view),
                    baseline:view.readings[l.point],geometry:shape))
            }
        }
        var output=[[String:Any]](),folds=[[String:Any]]()
        for session in Set(labels.map(\.session)).sorted() {
            var seen=Set<String>()
            // One labeled example per episode. Repeated adjacent frames are not independent training samples.
            let training=records.filter{$0.label.session != session}.compactMap {r -> StoneAppearanceModel.Example? in
                guard let truth=Occupancy(rawValue:r.label.truth),truth != .uncertain,
                      seen.insert("\(r.label.session)/\(r.label.point)/\(r.label.episode)/\(r.label.truth)").inserted else {return nil}
                return .init(point:r.label.point,label:truth,features:r.features,context:r.trainContext)
            }
            guard let model=StoneAppearanceModel(examples:training) else {throw NSError(domain:"audit",code:4)}
            folds.append(["heldOutSession":session,"trainingExamples":training.count,"emptyContextComponents":model.components.map(\.group)])
            for r in records where r.label.session==session {
                let plain=model.predict(r.features)
                let contextual=model.predict(r.features,context:r.observedContext)
                func proposed(_ p:StoneAppearanceModel.Prediction)->String {
                    guard r.baseline.occupancy == .uncertain,p.label != .uncertain,
                          p.label == .empty ? r.features.values[3]>=0.035 : r.geometry else {return r.baseline.occupancy.rawValue}
                    return p.label.rawValue
                }
                output.append(["session":session,"frame":r.label.frame,"point":r.label.point,"episode":r.label.episode,"truth":r.label.truth,
                    "baseline":r.baseline.occupancy.rawValue,"model":plain.label.rawValue,"contextModel":contextual.label.rawValue,
                    "proposal":proposed(plain),"contextProposal":proposed(contextual),"neighborContext":r.observedContext.group,
                    "trainingNeighborContext":r.trainContext.group,"features":r.features.values])
            }
        }
        let data=try JSONSerialization.data(withJSONObject:["folds":folds,"rows":output],options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
