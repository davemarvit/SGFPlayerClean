import Foundation

/// A local lighting baseline, learned only from independent empty
/// readings at saved-empty intersections. Never learns from its own output.
struct KnownEmptyLighting {
    struct Report:Codable {var learned=0;var resolved=[Int]();var appearanceConfirmed=[Int]()}
    private struct Patch {
        let levels:[Double]
        let colors:[BoardChroma]
        let center:Double
        func distance(to other:Self)->(level:Double,color:Double,center:Double) {
            let light=zip(levels,other.levels).map {abs($0-$1)}.sorted()
            let chroma=zip(colors,other.colors).map {($0-$1).magnitude}.sorted()
            return (light[14],chroma[14],abs(center-other.center))
        }
    }
    private struct Entry {
        var patch:Patch
        var first:Double
        var last:Double
        var count=1
        var noise=0.0
        var revalidating=false
        var confirmationFirst:Double?
        var confirmations=0
        var trained:Bool {count>=8 && last-first>=1.4}
        var ready:Bool {trained && !revalidating}
        var tolerance:Double {max(0.022,min(0.025,noise*2+0.005))}
    }
    private var entries=[Int:Entry]()
    private var challenged=Set<Int>()
    private var context=""
    private var expected=[Occupancy]()
    private var lastTime:Double?
    private var suspended=false
    private var previousCalibration:BoardCalibration?
    private(set) var report=Report()
    mutating func reset() {self=Self()}
    /// Keep established evidence dormant, never partially learned runs. No
    /// interrupted time counts toward training, expiry, or fresh confirmation.
    mutating func suspend() {
        report=Report()
        guard !suspended else {return}
        suspended=true
        entries=entries.filter {$0.value.trained}
        for p in Array(entries.keys) {
            entries[p]?.revalidating=true
            entries[p]?.confirmationFirst=nil
            entries[p]?.confirmations=0
        }
    }
    private func patch(_ frame:GrayFrame,_ calibration:BoardCalibration,_ point:Int)->Patch? {
        var levels=[Double](),colors=[BoardChroma]()
        for y in [-0.3,-0.18,0.18,0.3] {for x in [-0.3,-0.18,0.18,0.3] {
            let p=calibration.point(col:Double(point%calibration.size)+x,row:Double(point/calibration.size)+y)
            guard let level=frame.patchMean(p),let color=frame.patchColor(p),
                  level>0.08,level<0.94 else {return nil}
            levels.append(level);colors.append(color)
        }}
        guard let center=frame.patchMean(calibration.point(col:Double(point%calibration.size),row:Double(point/calibration.size))) else {return nil}
        return Patch(levels:levels,colors:colors,center:center)
    }
    mutating func observe(_ raw:BoardObservation,frame:GrayFrame,calibration:BoardCalibration,
                          expected position:[Occupancy],context identity:String,now:Double,valid:Bool,
                          appearanceThreshold:Double?=nil)->BoardObservation {
        report=Report()
        guard now.isFinite,raw.size==calibration.size,
              position.count==raw.size*raw.size,raw.readings.count==position.count,
              raw.readings.enumerated().allSatisfy({$0.element.row==$0.offset/raw.size && $0.element.col==$0.offset%raw.size})
        else {reset();return raw}
        if context != identity || expected != position {reset();context=identity;expected=position}
        guard valid,!raw.lightingBlocked else {suspend();return raw}
        if let lastTime {
            guard now>lastTime else {return raw}
            if now-lastTime>1.5 {suspend()}
            if suspended {
                // Preserve each baseline's observed age across the interruption.
                for p in Array(entries.keys) {
                    entries[p]?.first += now-lastTime
                    entries[p]?.last += now-lastTime
                }
            }
        }
        suspended=false
        if let previousCalibration {
            let shift=zip(previousCalibration.corners,calibration.corners).contains {old,new in
                guard let a=calibration.gridPoint(for:old),let b=calibration.gridPoint(for:new) else {return true}
                return hypot(a.x-b.x,a.y-b.y)>0.05
            }
            if shift {entries.removeAll()}
        }
        previousCalibration=calibration;lastTime=now
        // The known occupied count and colors validate this context, but never
        // cap the number of visible stones: a newly placed stone passes through.
        guard position.indices.allSatisfy({position[$0].stone==nil ||
            (raw.readings[$0].occupancy==position[$0] && raw.readings[$0].confidence>=0.9)})
        else {entries.removeAll();return raw}
        entries=entries.filter {now-$0.value.last<=30}
        let occupied=Set(position.indices.filter {position[$0].stone != nil || raw.readings[$0].occupancy.stone != nil})
        var readings=raw.readings
        for p in position.indices where position[p] == .empty {
            let reading=raw.readings[p]
            guard !raw.manualPoints.contains(p),reading.occupancy.stone==nil,
                  let current=patch(frame,calibration,p) else {entries[p]=nil;continue}
            let referenceEmpty=reading.occupancy == .empty && reading.confidence>=0.8
            if var entry=entries[p],entry.revalidating {
                let difference=current.distance(to:entry.patch)
                if difference.level<=entry.tolerance && difference.color<=0.012 && difference.center<=0.04 {
                    if entry.confirmationFirst==nil {entry.confirmationFirst=now}
                    entry.confirmations+=1
                    if entry.confirmations>=3,now-entry.confirmationFirst!>=0.4 {entry.revalidating=false}
                    entries[p]=entry
                } else {
                    entries[p]=nil
                    if !referenceEmpty {challenged.insert(p)}
                }
            }
            if referenceEmpty {challenged.remove(p)}
            let appearanceEmpty:Bool
            if !referenceEmpty,!challenged.contains(p),let threshold=appearanceThreshold,
               BoardAppearanceDetector.emptyConfidence(frame:frame,calibration:calibration,point:p,
                   threshold:threshold,occupied:occupied) != nil {
                appearanceEmpty=true;report.appearanceConfirmed.append(p)
            } else {appearanceEmpty=false}
            if referenceEmpty || appearanceEmpty {
                if var entry=entries[p] {
                    let difference=current.distance(to:entry.patch)
                    if difference.level<=0.025 && difference.color<=0.012 && difference.center<=0.04 {
                        entry.noise=max(entry.noise,difference.level)
                        entry.last=now;entry.count+=1
                        // Keep the independently observed anchor fixed; gradual
                        // changes must not teach an approaching object as wood.
                        entries[p]=entry
                    } else if referenceEmpty {entries[p]=Entry(patch:current,first:now,last:now)}
                    else {entries[p]=nil;challenged.insert(p)}
                } else {entries[p]=Entry(patch:current,first:now,last:now)}
            }
            if reading.occupancy == .uncertain,let entry=entries[p],entry.ready {
                let difference=current.distance(to:entry.patch)
                if difference.level<=entry.tolerance && difference.color<=0.012 && difference.center<=0.04 {
                    readings[p] = .init(row:reading.row,col:reading.col,occupancy:.empty,confidence:0.85,delta:reading.delta)
                    report.resolved.append(p)
                } else {entries[p]=nil;challenged.insert(p)}
            }
        }
        report.learned=entries.values.filter(\.ready).count
        guard !report.resolved.isEmpty else {return raw}
        return BoardObservation(readings:readings,size:raw.size,notice:raw.notice,
            lightingBlocked:raw.lightingBlocked,lightingAdjusted:raw.lightingAdjusted,lightingField:raw.lightingField,
            footprints:raw.footprints,placementFits:raw.placementFits,manualPoints:raw.manualPoints,
            trackedAssignments:raw.trackedAssignments,capturedAt:raw.capturedAt,
            handObstructed:raw.handObstructed,clockPressEstimate:raw.clockPressEstimate,centeringEvidence:raw.centeringEvidence)
    }
}
