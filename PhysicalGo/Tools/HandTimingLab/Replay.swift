import Foundation
import ImageIO

/// Offline evaluation of the production detector/estimator, sampled from the
/// same native-rate capture at several phases. Manual labels are never input
/// to detection or fitting; they only associate outputs for scoring.
@main struct HandTimingReplay {
    struct Grid:Decodable {let size:Int;let corners:[ImagePoint]}
    struct Sample:Codable {let index:Int;let time:Double;let pose:HandMotionPose?;let source:String}
    struct Run:Codable {let fps:Double;let phase:Int;let estimates:[ClockPressEstimate];let comparisons:[Comparison]}
    struct Comparison:Codable {
        let lastObstructed:Int,firstClear:Int
        let lower:Double,upper:Double
        let estimate:ClockPressEstimate?
        let distanceOutsideManualInterval:Double?
        let estimatedBandOverlapsManualInterval:Bool?
    }
    static func main()throws {
        guard CommandLine.arguments.count==2 else {throw NSError(domain:"Usage: HandTimingReplay CAPTURE_FOLDER",code:1)}
        let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let grid=try JSONDecoder().decode(Grid.self,from:Data(contentsOf:folder.appendingPathComponent("calibration.json")))
        guard let calibration=BoardCalibration(size:grid.size,corners:grid.corners) else {throw NSError(domain:"Invalid grid corners",code:2)}
        let lines=try String(contentsOf:folder.appendingPathComponent("frames.jsonl")).split(separator:"\n")
        let frames=try lines.map{try JSONDecoder().decode(LabFrame.self,from:Data($0.utf8))}
        var labels=[LabLabel]()
        let labelURL=folder.appendingPathComponent("labels.json")
        if FileManager.default.fileExists(atPath:labelURL.path) {
            let data=try JSONDecoder().decode(LabLabels.self,from:Data(contentsOf:labelURL))
            guard data.session==folder.lastPathComponent else {throw NSError(domain:"Labels belong to another capture",code:3)}
            labels=data.withdrawals
        }
        var samples=[Sample](),previous = -Double.infinity
        for frame in frames where frame.file != nil {
            guard frame.timestamp.capturedAt.isFinite,frame.timestamp.capturedAt>previous,
                  let name=frame.file,URL(fileURLWithPath:name).lastPathComponent==name else {throw NSError(domain:"Invalid frame journal",code:4)}
            previous=frame.timestamp.capturedAt
            try autoreleasepool {
                guard let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw NSError(domain:"Cannot read \(name)",code:5)}
                samples.append(.init(index:frame.index,time:frame.timestamp.capturedAt,pose:BoardHandDetector.pose(image:image,calibration:calibration),source:frame.timestamp.source))
            }
        }
        guard let first=samples.first else {throw NSError(domain:"Capture has no saved frames",code:6)}
        labels.sort{$0.lastObstructed<$1.lastObstructed}
        for (index,label) in labels.enumerated() {
            guard label.lastObstructed<label.firstClear,samples.contains(where:{$0.index==label.lastObstructed}),samples.contains(where:{$0.index==label.firstClear}) else {throw NSError(domain:"Invalid manual label",code:7)}
            guard index==0 || labels[index-1].firstClear<label.lastObstructed else {throw NSError(domain:"Manual intervals overlap",code:8)}
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(samples).write(to:folder.appendingPathComponent("poses.json"),options:.atomic)
        var runs=[Run]()
        for fps in [5.0,10.0,30.0] {
            for phase in 0..<(fps==30 ? 1:6) {
                var estimator=HandMotionTiming(),next=first.time+Double(phase)/(6*fps),estimates=[ClockPressEstimate]()
                for sample in samples where fps==30 || sample.time+1e-7>=next {
                    if let estimate=estimator.observe(sample.pose,at:sample.time,size:grid.size,source:sample.source) {estimates.append(estimate)}
                    // Advance on a fixed schedule. Resetting to each selected
                    // frame's timestamp lets jitter collapse distinct phases.
                    repeat {next+=1/fps} while next<=sample.time+1e-7
                }
                let comparisons=labels.enumerated().map {index,label->Comparison in
                    let lower=samples.first{$0.index==label.lastObstructed}!.time
                    let upper=samples.first{$0.index==label.firstClear}!.time
                    // Partition the capture halfway between independently
                    // marked withdrawals. Bracket-overlap matching discarded
                    // early/late failures and would bias the accuracy report.
                    let windowStart=index==0 ? first.time:(samples.first{$0.index==labels[index-1].firstClear}!.time+lower)/2
                    let windowEnd=index+1==labels.count ? Double.infinity:(upper+samples.first{$0.index==labels[index+1].lastObstructed}!.time)/2
                    let matches=estimates.filter{$0.time>=windowStart && $0.time<windowEnd}
                    let estimate=matches.count==1 ? matches[0]:nil
                    let error=estimate.map{max(0,lower-$0.time,$0.time-upper)}
                    let overlap=estimate.flatMap{e in e.estimatedError.map{e.time+$0>=lower && e.time-$0<=upper}}
                    return .init(lastObstructed:label.lastObstructed,firstClear:label.firstClear,lower:lower,upper:upper,estimate:estimate,distanceOutsideManualInterval:error,estimatedBandOverlapsManualInterval:overlap)
                }
                runs.append(.init(fps:fps,phase:phase,estimates:estimates,comparisons:comparisons))
            }
        }
        try encoder.encode(runs).write(to:folder.appendingPathComponent("evaluation.json"),options:.atomic)
        print("Replayed \(samples.count) frames, \(labels.count) manual intervals, \(runs.count) sampling runs. See poses.json and evaluation.json.")
        print("Manual labels bound a crossing; they are not exact timestamps. Missing/ambiguous detector matches stay unscored. Model error is uncalibrated.")
    }
}
