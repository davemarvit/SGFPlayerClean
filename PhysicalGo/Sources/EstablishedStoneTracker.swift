import Foundation

/// Physical geometry is separate from the authoritative game position. This
/// value type runs on the camera analysis queue and never changes SGF or OGS.
struct EstablishedStoneTracker {
    struct Track: Codable {
        let point:Int
        let color:Occupancy
        var shape:StoneFootprint
        var lastSeen:Double
    }
    struct Report: Codable {
        var tracked=0
        var updated=0
        var uncertain=[Int]()
        var remapped=[Int:Int]() // raw detection -> game intersection, NOT labels
        var possibleBoardShift=false
        var scanSeconds=0.0
        var processingSeconds=0.0
        var scanned=false
    }
    private struct Proposal {let color:Occupancy;var shape:StoneFootprint;var first:Double;var last:Double;var count:Int}
    private struct Disk {var shape:StoneFootprint;var sources:Set<Int>;let color:Occupancy;var confidence:Double}
    private(set) var tracks=[Int:Track]()
    private var proposals=[Int:Proposal]()
    private var context=""
    private var shiftStarted:Double?
    private var lastFrame:Double?
    private var lastScan = -Double.infinity
    private(set) var report=Report()
    static let scanInterval=0.5

    mutating func reset() {self=Self()}
    private func distance(_ a:ImagePoint,_ b:ImagePoint)->Double {hypot(a.x-b.x,a.y-b.y)}
    private func disks(_ observation:BoardObservation)->[Disk] {
        var result=[Disk]()
        // Merge two fits of the SAME physical disk, never two nearby stones.
        // Conflicting colors/outlines remain separate and block association.
        for shape in observation.footprints+observation.placementFits {
            let p=shape.row*observation.size+shape.col
            guard observation.readings.indices.contains(p),shape.quality>=0.90,
                  shape.center.x.isFinite,shape.center.y.isFinite,
                  (-0.65...Double(observation.size)-0.35).contains(shape.center.x),
                  (-0.65...Double(observation.size)-0.35).contains(shape.center.y),
                  (0.30...0.65).contains(shape.radiusCol),(0.30...0.65).contains(shape.radiusRow),
                  observation.readings[p].confidence>=0.90,
                  observation.readings[p].occupancy.stone != nil,
                  !observation.manualPoints.contains(p) else {continue}
            let reading=observation.readings[p]
            if let i=result.firstIndex(where:{$0.color==reading.occupancy && distance($0.shape.center,shape.center)<0.18 &&
                abs($0.shape.radiusCol-shape.radiusCol)<0.12 && abs($0.shape.radiusRow-shape.radiusRow)<0.12}) {
                result[i].sources.insert(p)
                result[i].confidence=min(result[i].confidence,reading.confidence)
                if shape.quality>result[i].shape.quality {result[i].shape=shape}
            } else {result.append(Disk(shape:shape,sources:[p],color:reading.occupancy,confidence:reading.confidence))}
        }
        return result
    }
    /// Each disk and each logical intersection must have exactly one plausible
    /// partner. Ambiguity is retained; a nearest-neighbor guess is insufficient.
    private func associations(_ disks:[Disk],expected:[Occupancy],size:Int,now:Double)->[Int:Int] {
        var byPoint=[Int:[Int]](),byDisk=[Int:[Int]]()
        for (d,disk) in disks.enumerated() {
            let row=Int(disk.shape.center.y.rounded()),col=Int(disk.shape.center.x.rounded())
            for r in max(0,row-1)...min(size-1,row+1) {
                for c in max(0,col-1)...min(size-1,col+1) {
                    let p=r*size+c
                    guard expected[p]==disk.color else {continue}
                    let logical=ImagePoint(x:Double(c),y:Double(r))
                    guard distance(logical,disk.shape.center)<=0.65 else {continue}
                    if let track=tracks[p],now-track.lastSeen<=2 {
                        guard distance(track.shape.center,disk.shape.center)<=0.40 else {continue}
                    } else {
                        guard disk.sources.contains(p),disk.shape.contains(logical,padding:-0.04) else {continue}
                    }
                    byPoint[p,default:[]].append(d);byDisk[d,default:[]].append(p)
                }
            }
        }
        var matches=[Int:Int]()
        for (p,ds) in byPoint where ds.count==1 && byDisk[ds[0]]?.count==1 {matches[p]=ds[0]}
        return matches
    }
    mutating func observe(_ raw:BoardObservation,expected:[Occupancy],context newContext:String,
                          now:Double,valid:Bool=true)->BoardObservation {
        let processingStart=ProcessInfo.processInfo.systemUptime
        report=Report()
        defer {report.processingSeconds=ProcessInfo.processInfo.systemUptime-processingStart}
        guard valid,!raw.lightingBlocked,expected.count==raw.size*raw.size,
              raw.readings.count==expected.count,raw.size>0,
              raw.readings.enumerated().allSatisfy({$0.element.row==$0.offset/raw.size && $0.element.col==$0.offset%raw.size}),
              now.isFinite else {reset();return raw}
        if context != newContext {reset();context=newContext}
        if let lastFrame {
            guard now>lastFrame else {return raw}
            if now-lastFrame>1 {tracks=[:];proposals=[:];shiftStarted=nil;lastScan = -Double.infinity}
        }
        lastFrame=now
        // Captures, undo, new games and color changes invalidate identities.
        tracks=tracks.filter{expected[$0.key]==$0.value.color}
        proposals=proposals.filter{expected[$0.key]==$0.value.color}
        let visible=disks(raw),matches=associations(visible,expected:expected,size:raw.size,now:now)
        var displacements=[ImagePoint]()
        for (p,d) in matches {
            if let track=tracks[p],now-track.lastSeen<=2 {
                let next=visible[d].shape.center
                displacements.append(.init(x:next.x-track.shape.center.x,y:next.y-track.shape.center.y))
            }
        }
        var coherentShift=false
        if displacements.count>=4 {
            let dx=displacements.map(\.x).sorted()[displacements.count/2]
            let dy=displacements.map(\.y).sorted()[displacements.count/2]
            coherentShift=hypot(dx,dy)>0.18 &&
                Double(displacements.filter{hypot($0.x-dx,$0.y-dy)<0.09}.count)/Double(displacements.count)>=0.7
        }
        if coherentShift {
            if shiftStarted == nil {shiftStarted=now}
            report.possibleBoardShift=now-shiftStarted!>=0.5
            proposals=[:];report.tracked=tracks.count;return raw
        }
        shiftStarted=nil
        if now-lastScan>=Self.scanInterval {
            let start=ProcessInfo.processInfo.systemUptime
            lastScan=now;report.scanned=true
            for p in expected.indices where expected[p].stone != nil {
                guard let d=matches[p] else {proposals[p]=nil;report.uncertain.append(p);continue}
                let shape=visible[d].shape
                // Large/unresolved displacement is visible as a warning. It
                // must not be assimilated repeatedly into an unbounded drift.
                let logical=ImagePoint(x:Double(p%raw.size),y:Double(p/raw.size))
                guard shape.contains(logical,padding:0.06) else {proposals[p]=nil;report.uncertain.append(p);continue}
                if var proposal=proposals[p],now-proposal.last<=1.1,distance(proposal.shape.center,shape.center)<=0.12 {
                    proposal.shape=shape;proposal.last=now;proposal.count += 1;proposals[p]=proposal
                } else {proposals[p]=Proposal(color:expected[p],shape:shape,first:now,last:now,count:1)}
                if let proposal=proposals[p],proposal.count>=3,now-proposal.first>=1 {
                    tracks[p]=Track(point:p,color:expected[p],shape:shape,lastSeen:now)
                    report.updated += 1
                }
            }
            report.scanSeconds=ProcessInfo.processInfo.systemUptime-start
        }
        report.tracked=tracks.count
        // Fresh geometry must independently match on EVERY delivered frame.
        // Stored shapes alone never supply occupancy or hide a captured stone.
        var readings=raw.readings,remapped=[Int:Int]()
        for (p,d) in matches {
            guard let track=tracks[p],now-track.lastSeen<=2,
                  // Quarantine a duplicate immediately during a supported nudge;
                  // do not let it become a move while geometry earns three views.
                  distance(track.shape.center,visible[d].shape.center)<=0.40,
                  visible[d].shape.contains(.init(x:Double(p%raw.size),y:Double(p/raw.size)),padding:0.06),
                  !raw.manualPoints.contains(p) else {continue}
            let aliases=visible[d].sources.filter{$0 != p}
            guard !aliases.isEmpty,
                  aliases.allSatisfy({expected[$0] == .empty && !raw.manualPoints.contains($0)}),
                  raw.readings[p].occupancy == .uncertain || raw.readings[p].occupancy==expected[p],
                  !visible.enumerated().contains(where:{$0.offset != d && !$0.element.sources.isDisjoint(with:visible[d].sources.union([p]))}) else {continue}
            readings[p] = .init(row:p/raw.size,col:p%raw.size,occupancy:expected[p],confidence:visible[d].confidence,delta:raw.readings[p].delta)
            for alias in aliases {
                // No positive empty evidence: suppress a duplicate as UNKNOWN,
                // never train an empty label from the historical expectation.
                readings[alias] = .init(row:alias/raw.size,col:alias%raw.size,occupancy:.uncertain,confidence:0,delta:raw.readings[alias].delta)
                remapped[alias]=p
            }
        }
        report.remapped=remapped
        guard !remapped.isEmpty else {return raw}
        var interpreted=BoardObservation(readings:readings,size:raw.size,notice:raw.notice,lightingBlocked:raw.lightingBlocked,
            lightingAdjusted:raw.lightingAdjusted,lightingField:raw.lightingField,footprints:raw.footprints,
            placementFits:raw.placementFits,manualPoints:raw.manualPoints,centeringEvidence:raw.centeringEvidence)
        interpreted.trackedAssignments=remapped
        return interpreted
    }
}
