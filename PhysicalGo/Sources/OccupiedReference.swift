import Foundation

/// A labeled position, never an empty-board photograph. Explicit confirmation
/// seeds the first reference; automatic refresh needs independent visual evidence.
struct OccupiedReference: Codable {
    struct Patch: Codable {
        var levels:[Double], red:[Double], green:[Double]
        var center:Double
        var outside:[Double]?=nil
        var body:(light:Double,red:Double,green:Double) {
            guard [levels.count,red.count,green.count].allSatisfy({$0==16}) else {return (.nan,.nan,.nan)}
            let ids=[5,6,9,10]
            return (ids.map{levels[$0]}.reduce(0,+)/4,ids.map{red[$0]}.reduce(0,+)/4,ids.map{green[$0]}.reduce(0,+)/4)
        }
        func colorDistance(_ other:Self)->Double {
            let a=body,b=other.body,r=a.red-b.red,g=a.green-b.green
            return sqrt(r*r+g*g+(r+g)*(r+g))
        }
        func outsideAgreement(_ other:Self,excluding:Set<Int>=[])->Double {
            guard let a=outside,let b=other.outside,a.count==36,b.count==36 else {return 0}
            let usable=(0..<12).filter{!excluding.contains($0)}
            guard usable.count>=4 else {return 0}
            return Double(usable.filter {i in
                let r=a[i*3+1]-b[i*3+1],g=a[i*3+2]-b[i*3+2]
                return abs(a[i*3]-b[i*3])<=0.045 && sqrt(r*r+g*g+(r+g)*(r+g))<=0.025
            }.count)/Double(usable.count)
        }
        func unchangedOutside(_ other:Self)->Bool {outsideAgreement(other)>=10.0/12}
        func matches(_ other:Self)->Bool {
            guard [levels.count,red.count,green.count,other.levels.count,other.red.count,other.green.count].allSatisfy({$0==16}) else {return false}
            let light=zip(levels,other.levels).map{abs($0-$1)}.sorted()
            let color=(0..<16).map {i -> Double in
                let r=red[i]-other.red[i],g=green[i]-other.green[i]
                return sqrt(r*r+g*g+(r+g)*(r+g))
            }.sorted()
            return light[14]<=0.045 && color[14]<=0.025 && abs(center-other.center)<=0.05
        }
        static func sample(_ frame:GrayFrame,_ cal:BoardCalibration,_ p:Int)->Self? {
            func sample(_ c:Double,_ r:Double)->(Double,Double,Double)? {
                var l=0.0,red=0.0,green=0.0
                for dy in [-0.06,0,0.06] {for dx in [-0.06,0,0.06] {
                    let point=cal.point(col:c+dx,row:r+dy)
                    guard let v=frame.patchMean(point),let color=frame.patchColor(point) else {return nil}
                    l+=v;red+=color.red;green+=color.green
                }}
                return (l/9,red/9,green/9)
            }
            var levels=[Double](),red=[Double](),green=[Double]()
            for y in [-0.3,-0.18,0.18,0.3] {for x in [-0.3,-0.18,0.18,0.3] {
                guard let (l,r,g)=sample(Double(p%cal.size)+x,Double(p/cal.size)+y),l>0.08,l<0.94 else {return nil}
                levels.append(l);red.append(r);green.append(g)
            }}
            guard let (center,_,_)=sample(Double(p%cal.size),Double(p/cal.size)) else {return nil}
            var outside=[Double]()
            for sector in 0..<12 {
                let a=(Double(sector)+0.5)*Double.pi/6
                guard let (l,r,g)=sample(Double(p%cal.size)+cos(a)*0.8,Double(p/cal.size)+sin(a)*0.8) else {continue}
                outside += [l,r,g]
            }
            return .init(levels:levels,red:red,green:green,center:center,outside:outside.count==36 ? outside:nil)
        }
    }
    struct Entry: Codable {
        var patch:Patch
        var first:Double?=nil
        var matches=0
        enum CodingKeys:String,CodingKey {case patch}
    }
    struct Candidate {var patch:Patch;var first:Double;var count=1;var lastStrong:Double?=nil;var shape:StoneFootprint?=nil}
    struct WhiteEvidence:Codable,Equatable {
        var point:Int, score:Double, outline:Double, appearance:Double, locality:Double, gridOcclusion:Double, referenceEvidence:Double
        var knownWhite:Bool
    }
    struct Report:Codable,Equatable {
        var resolved=[Int](),refreshed=[Int](),recognizedWhite=[Int](),retainedOrigins=[Int]()
        var quarantined=[Int](),restored=[Int](),anchored=[Int]()
        var recognizedEmpty=[Int]()
        var whiteEvidence=[WhiteEvidence]()
        var available=0
        var excluded=0
        var stable=false
    }
    private(set) var identity=""
    private(set) var position=[Occupancy]()
    private(set) var calibration:BoardCalibration?
    private var entries=[Int:Entry]()
    // Suspect pixels are withheld, not forgotten. They may support a label
    // again only after fresh images match the original patch consecutively.
    private var quarantined:[Int:Entry]?=nil
    private var observedWhite=[Int:Candidate]()
    private var observedEmpty=[Int:Candidate]()
    // Genuine formerly empty pixels remain a before-image for a new White.
    // They never become a White template merely because the game expects White.
    private var whiteOrigins:[Int:Patch]?=nil
    // Explicitly observed White bodies remain anchors when only edge/shadow
    // pixels change. Reuse still requires independent current object evidence.
    private var whiteAnchors:[Int:Patch]?=nil
    private var whiteWitness=[Int:Candidate]()
    private(set) var generation=0
    private(set) var updatedAtUnix=0.0
    private var pending=[Int:Candidate]()
    private var challenged=Set<Int>()
    private var lastFrame:Double?
    private var stableSince:Double?
    private var stableFrames=0
    private var lastRefresh:Double?
    private(set) var report=Report()
    enum CodingKeys:String,CodingKey {case identity,position,calibration,entries,quarantined,whiteOrigins,whiteAnchors,generation,updatedAtUnix}
    var hasReference:Bool {!entries.isEmpty || quarantined?.isEmpty == false}

    static func neighborhood(_ points:Set<Int>,size:Int)->Set<Int> {
        var result=Set<Int>()
        guard size>0 else {return result}
        for p in points where (0..<size*size).contains(p) {
            let row=p/size,col=p%size
            for r in max(0,row-1)...min(size-1,row+1) {
                for c in max(0,col-1)...min(size-1,col+1) {result.insert(r*size+c)}
            }
        }
        return result
    }

    static func uncertainLocations(_ observation:BoardObservation,expected:[Occupancy])->Set<Int> {
        var points=Set(expected.indices.filter{expected[$0] == .uncertain})
        points.formUnion(observation.assignmentOffsets(confirmedBoard:expected).filter{$0.value>=0.30}.map(\.key))
        // An uncertain color reading can still have a displaced visible outline.
        for shape in observation.footprints+observation.placementFits where shape.quality>=0.86 &&
            max(abs(shape.center.x-Double(shape.col)),abs(shape.center.y-Double(shape.row)))>=0.30 {
            points.insert(shape.row*observation.size+shape.col)
        }
        return neighborhood(points,size:observation.size)
    }
    /// Caller must review the actual photograph against the included labels.
    /// Uncertain labels and excluded regions never become reference evidence.
    mutating func captureConfirmed(frame:GrayFrame,calibration:BoardCalibration,position:[Occupancy],identity:String,now:Double,excluding:Set<Int>=[])->Bool {
        guard !identity.isEmpty,now.isFinite,position.count==calibration.size*calibration.size else {return false}
        self=Self();self.identity=identity;self.position=position;self.calibration=calibration
        let excluded=excluding.union(Self.neighborhood(Set(position.indices.filter{position[$0] == .uncertain}),size:calibration.size))
        for p in position.indices where !excluded.contains(p) {
            if let patch=Patch.sample(frame,calibration,p) {
                entries[p] = .init(patch:patch)
                if position[p] == .white {
                    if whiteAnchors==nil {whiteAnchors=[:]};whiteAnchors?[p]=patch
                }
            }
        }
        generation=1;updatedAtUnix=Date().timeIntervalSince1970;lastRefresh=now
        report.available=entries.count
        return !entries.isEmpty
    }
    mutating func suspend() {
        pending.removeAll();whiteWitness.removeAll();observedWhite.removeAll();observedEmpty.removeAll();stableSince=nil;stableFrames=0;lastFrame=nil
        for p in Array(entries.keys) {entries[p]?.first=nil;entries[p]?.matches=0}
        for p in Array((quarantined ?? [:]).keys) {quarantined?[p]?.first=nil;quarantined?[p]?.matches=0}
        report=Report(available:entries.count)
    }
    mutating func observe(_ observation:BoardObservation,independent raw:BoardObservation,frame:GrayFrame,
                          calibration cal:BoardCalibration,expected:[Occupancy],identity:String,now:Double,
                          valid:Bool,allowRefresh:Bool,stoneThreshold:Double=0.13)->BoardObservation {
        report=Report(available:entries.count)
        guard hasReference,self.identity==identity,let base=calibration,base.size==cal.size,
              expected.count==position.count,observation.size==cal.size,raw.size==cal.size,
              observation.readings.count==expected.count,raw.readings.count==expected.count,
              raw.readings.enumerated().allSatisfy({$0.element.row==$0.offset/cal.size && $0.element.col==$0.offset%cal.size && $0.element.confidence.isFinite}),
              observation.readings.enumerated().allSatisfy({$0.element.row==$0.offset/cal.size && $0.element.col==$0.offset%cal.size}),
              now.isFinite,valid,!observation.lightingBlocked,!raw.lightingBlocked,
              observation.handObstructed != true,raw.handObstructed != true,
              observation.manualPoints.isEmpty,raw.manualPoints.isEmpty else {suspend();return observation}
        guard zip(base.corners,cal.corners).allSatisfy({a,b in
            guard let x=cal.gridPoint(for:a),let y=cal.gridPoint(for:b) else {return false}
            // Small supported grid refinements must still pass per-patch pixel checks.
            return hypot(x.x-y.x,x.y-y.y)<=0.10
        }) else {self=Self();return observation}
        if let lastFrame {
            guard now>lastFrame else {return observation}
            if now-lastFrame>0.6 {suspend()}
        }
        lastFrame=now
        if position != expected {
            let changed=position.indices.filter{position[$0] != expected[$0]}
            for p in position.indices where changed.contains(where:{abs($0/cal.size-p/cal.size)<=1 && abs($0%cal.size-p%cal.size)<=1}) {
                if changed.contains(p) {entries[p]=nil;quarantined?[p]=nil;observedEmpty[p]=nil;challenged.remove(p)}
                else {
                    // A nearby move may cast a shadow, but need not destroy an
                    // unchanged stone's anchor. Revalidate fresh pixels; any
                    // actual patch change still invalidates it below.
                    entries[p]?.first=nil;entries[p]?.matches=0
                }
            }
            for p in changed where expected[p] != .white {whiteOrigins?[p]=nil;whiteAnchors?[p]=nil;whiteWitness[p]=nil;observedWhite[p]=nil}
            position=expected;pending.removeAll();stableSince=nil;stableFrames=0
        }
        var result=observation
        let excluded=Self.uncertainLocations(raw,expected:expected).union(Self.uncertainLocations(observation,expected:expected))
        let occupied=Set(expected.indices.filter {expected[$0].stone != nil ||
            (raw.readings[$0].occupancy.stone != nil && raw.readings[$0].confidence>=0.8)})
        report.excluded=excluded.count
        for p in expected.indices {
            if excluded.contains(p) {
                quarantine(p);pending[p]=nil;whiteWitness[p]=nil;observedWhite[p]=nil;observedEmpty[p]=nil
                continue
            }
            let r=raw.readings[p]
            guard let patch=Patch.sample(frame,cal,p) else {
                pending[p]=nil;entries[p]?.first=nil;entries[p]?.matches=0;continue
            }
            var independentMatch=r.occupancy==expected[p] && r.confidence>=0.9
            // Keep independently observed new White appearance promptly. The
            // game must also have accepted that label before it becomes an
            // anchor; the game position alone can never supply these pixels.
            if r.occupancy == .white,r.confidence>=0.9 {
                if var c=observedWhite[p],c.patch.matches(patch) {c.count+=1;c.lastStrong=now;observedWhite[p]=c}
                else {observedWhite[p] = .init(patch:patch,first:now,lastStrong:now)}
                if expected[p] == .white,whiteAnchors?[p]==nil,let c=observedWhite[p],c.count>=3,now-c.first>=0.4 {
                    if whiteAnchors==nil {whiteAnchors=[:]};whiteAnchors?[p]=c.patch;report.anchored.append(p)
                }
            } else if let c=observedWhite[p],c.patch.matches(patch),now-(c.lastStrong ?? c.first)<=0.6,
                      r.occupancy == .uncertain || r.occupancy == .white {} else {observedWhite[p]=nil}
            let contradiction=r.occupancy != .uncertain && r.occupancy != expected[p] && r.confidence>=0.8
            if contradiction {
                // Preserve genuine empty pixels even when the primary detector
                // sees White immediately. Later uncertain frames still need
                // this independent before-image after the move is committed.
                if expected[p] == .empty,r.occupancy == .white,let before=entries[p]?.patch,
                   before.outside != nil,!before.matches(patch) {
                    if whiteOrigins==nil {whiteOrigins=[:]};whiteOrigins?[p]=before
                    report.retainedOrigins.append(p)
                }
                quarantine(p);pending[p]=nil;observedEmpty[p]=nil;challenged.insert(p);continue
            }
            if independentMatch {challenged.remove(p)}
            if var held=quarantined?[p] {
                if held.patch.matches(patch) {
                    if held.first==nil {held.first=now};held.matches+=1
                    quarantined?[p]=held
                    if held.matches>=3,now-held.first!>=0.4 {
                        entries[p]=held;quarantined?[p]=nil;challenged.remove(p);report.restored.append(p)
                    }
                } else {held.first=nil;held.matches=0;quarantined?[p]=held}
            }
            // A stale brightness template is not required when current wood
            // color and both grid axes independently establish emptiness. This
            // is a fresh image test, never an inference from an expected label.
            if expected[p] == .empty,(quarantined?[p] != nil || whiteOrigins?[p] != nil),
               let confidence=BoardAppearanceDetector.emptyConfidence(frame:frame,calibration:cal,point:p,
                    threshold:stoneThreshold,occupied:occupied),confidence>=0.75,
               {let grid=BoardAppearanceDetector.gridEvidence(frame:frame,calibration:cal,col:Double(p%cal.size),row:Double(p/cal.size),relativeContrast:true)
                return grid.horizontal>=0.75 && grid.vertical>=0.75}() {
                // Count fresh grid-and-wood proofs, not unstable edge pixels
                // shared with a neighboring stone. Each frame independently
                // passes both-axis visibility; a failed proof resets the run.
                if var c=observedEmpty[p] {c.count+=1;c.patch=patch;observedEmpty[p]=c}
                else {observedEmpty[p] = .init(patch:patch,first:now)}
                if let c=observedEmpty[p],c.count>=3,now-c.first>=0.4 {
                    if result.readings[p].occupancy == .uncertain || result.readings[p].confidence<0.8 {
                        result.readings[p] = .init(row:r.row,col:r.col,occupancy:.empty,confidence:0.9,delta:r.delta)
                    }
                    report.recognizedEmpty.append(p)
                    if c.count>=8,now-c.first>=1.4 {independentMatch=true;challenged.remove(p)}
                }
            } else {observedEmpty[p]=nil}
            if var entry=entries[p] {
                if entry.patch.matches(patch) {
                    if entry.first==nil {entry.first=now};entry.matches+=1;entries[p]=entry
                    if entry.matches>=3,now-entry.first!>=0.4,
                       result.readings[p].occupancy == .uncertain || result.readings[p].confidence<0.8 {
                        result.readings[p] = .init(row:r.row,col:r.col,occupancy:expected[p],confidence:0.9,delta:r.delta)
                        report.resolved.append(p)
                    }
                } else {
                    if expected[p] == .empty,entry.patch.outside != nil {
                        if whiteOrigins==nil {whiteOrigins=[:]};whiteOrigins?[p]=entry.patch
                        report.retainedOrigins.append(p)
                    }
                    quarantine(p);challenged.insert(p)
                }
            }
            // Combine independent clues instead of vetoing a real object on
            // one marginal photometric threshold. Scores are evidence weights,
            // not calibrated probabilities. Motion/contradiction gates remain.
            var whiteObserved=false
            let knownWhite=expected[p] == .white && whiteAnchors?[p] != nil
            let before=knownWhite ? whiteAnchors?[p]:whiteOrigins?[p]
            let coveredGrid=raw.coveredGridPoints.contains(p)
            if r.occupancy == .uncertain || (r.occupancy == .white && r.confidence<0.8),
               let before,[.empty,.white].contains(expected[p]),
               knownWhite || !before.matches(patch) || coveredGrid {
                let examples=entries.filter{$0.key != p && position[$0.key] == .white}.map{$0.value.patch}
                let fits=examples.filter{abs(patch.body.light-$0.body.light)<=0.12}
                    .map{patch.colorDistance($0)}.sorted()
                let colorChange=before.colorDistance(patch),lightChange=abs(before.body.light-patch.body.light)
                // A known body's small photometric variation is invariant, not
                // evidence against the stone. Fade only beyond that noise band;
                // larger changes still fail continuity. Shape, color exemplars,
                // grid occlusion and local surroundings remain independent cues.
                let referenceEvidence=knownWhite ? max(0,1-max(max(0,colorChange-0.01)/0.015,max(0,lightChange-0.04)/0.06)):
                    min(1,hypot(colorChange/0.025,lightChange/0.10))
                // Edge pixels belonging to neighboring stones are not stable
                // background samples: tiny grid-fit changes move across them.
                let neighbors=Self.neighborhood([p],size:cal.size).filter {
                    $0 != p && (expected[$0] != .empty ||
                        (raw.readings[$0].confidence>=0.8 && [.black,.white].contains(raw.readings[$0].occupancy)))
                }
                let excludedSectors=Set((0..<12).filter {sector in
                    let angle=(Double(sector)+0.5)*Double.pi/6
                    let x=Double(p%cal.size)+cos(angle)*0.8,y=Double(p/cal.size)+sin(angle)*0.8
                    return neighbors.contains{hypot(x-Double($0%cal.size),y-Double($0/cal.size))<0.60}
                })
                let locality=before.outsideAgreement(patch,excluding:excludedSectors)
                if fits.count>=2,fits[1]<=0.02,locality>=(knownWhite ? 0.5:0.75),
                   let shape=OccupiedStoneOutline.fit(frame:frame,calibration:cal,point:p,minimumContrast:0.018),
                   !raw.footprints.contains(where:{$0.row*cal.size+$0.col != p && $0.contains(shape.center,padding:0.08)}) {
                    let cross=BoardAppearanceDetector.gridEvidence(frame:frame,calibration:cal,col:Double(p%cal.size),row:Double(p/cal.size),relativeContrast:true)
                    let grid=max(0,1-max(cross.horizontal,cross.vertical))
                    let appearance=max(0,1-(fits[0]+fits[1])/0.04)
                    // Glary empty wood can match a White stone photometrically.
                    // In that case a newly covered reference cross supplies the
                    // before/after change, but only with a very strong disk,
                    // two matching White exemplars and unchanged surroundings.
                    let inkChange = !knownWhite && coveredGrid && shape.quality>=0.98 &&
                        fits[1]<=0.005 && grid>=0.95 && locality>=0.9
                    let referenceSupport=inkChange ? 1:referenceEvidence
                    let score=0.30*shape.quality+0.30*appearance+(knownWhite ? 0.05:0.15)*locality+0.15*grid+(knownWhite ? 0.20:0.10)*referenceSupport
                    report.whiteEvidence.append(.init(point:p,score:score,outline:shape.quality,appearance:appearance,locality:locality,gridOcclusion:grid,referenceEvidence:referenceEvidence,knownWhite:knownWhite))
                    if referenceSupport>=0.5,score>=0.92 {
                        whiteObserved=true
                        if var c=whiteWitness[p],c.patch.matches(patch) {
                            c.count+=1;c.lastStrong=now;c.shape=shape;whiteWitness[p]=c
                        } else {whiteWitness[p] = .init(patch:patch,first:now,lastStrong:now,shape:shape)}
                    }
                }
            }
            if !whiteObserved {
                // Brief classifier flicker is not a physical removal. Retain
                // recent object evidence only while current pixels still match.
                if let c=whiteWitness[p],c.patch.matches(patch),now-(c.lastStrong ?? c.first)<=0.6 {} else {whiteWitness[p]=nil}
            }
            if let c=whiteWitness[p],c.count>=3,now-c.first>=0.4,let shape=c.shape,
               r.occupancy == .uncertain || (r.occupancy == .white && r.confidence<0.8) {
                result.readings[p] = .init(row:r.row,col:r.col,occupancy:.white,confidence:0.95,delta:r.delta)
                result.footprints.append(shape);report.recognizedWhite.append(p)
                // Training still needs current strong object evidence; a merely
                // retained result cannot train its own appearance.
                if whiteObserved,expected[p] == .white,c.count>=8,now-c.first>=1.4 {independentMatch=true;challenged.remove(p)}
            }
            // Only independent raw readings or fresh multi-cue object evidence
            // can train; unchanged-reference support cannot train itself.
            if independentMatch,allowRefresh {
                if var c=pending[p],c.patch.matches(patch) {c.count+=1;pending[p]=c}
                else {pending[p] = .init(patch:patch,first:now)}
            } else {pending[p]=nil}
        }
        // Unknown regions do not prevent independent updates elsewhere. Mask
        // their neighboring pixels too, so a possible stone/shadow cannot leak
        // into empty training labels. This never resolves the unknown reading.
        let refreshExcluded=excluded.union(Self.neighborhood(Set(result.readings.indices.filter {
            result.readings[$0].occupancy == .uncertain || result.readings[$0].confidence<0.8
        }),size:cal.size))
        // Uncertain neighbors still prevent learning empty patches; a directly
        // observed stone can refresh its own appearance independently of them.
        for p in refreshExcluded where excluded.contains(p) || (expected[p] == .empty && !report.recognizedEmpty.contains(p)) ||
            result.readings[p].occupancy != expected[p] || result.readings[p].confidence<0.9 {pending[p]=nil}
        // Stability belongs to each independently witnessed patch. A pending
        // move elsewhere must not stop all other patches from refreshing.
        if allowRefresh {
            if stableSince==nil {stableSince=now};stableFrames+=1
            report.stable=stableFrames>=8 && now-stableSince!>=2
            if lastRefresh==nil {lastRefresh=now}
            if report.stable,now-lastRefresh!>=10 {
                for (p,c) in pending where c.count>=8 && now-c.first>=1.4 {
                    entries[p] = .init(patch:c.patch);quarantined?[p]=nil;report.refreshed.append(p)
                    if expected[p] == .white {
                        if whiteAnchors==nil {whiteAnchors=[:]};whiteAnchors?[p]=c.patch
                    }
                }
                if !report.refreshed.isEmpty {generation+=1;updatedAtUnix=Date().timeIntervalSince1970;lastRefresh=now}
                // Keep unfinished candidates after the deadline. Clearing them
                // on every overdue frame prevents any new candidate reaching
                // the required count and permanently starves local recovery.
                for p in report.refreshed {pending[p]=nil}
            }
        } else {stableSince=nil;stableFrames=0}
        report.available=entries.count
        return result
    }
    private mutating func quarantine(_ p:Int) {
        if var entry=entries.removeValue(forKey:p) {
            entry.first=nil;entry.matches=0
            if quarantined==nil {quarantined=[:]};quarantined?[p]=entry
            report.quarantined.append(p)
        }
        quarantined?[p]?.first=nil;quarantined?[p]?.matches=0
    }
}
