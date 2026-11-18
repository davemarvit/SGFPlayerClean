import Foundation

/// One color/location hypothesis during one uninterrupted appearance episode.
/// Derived from bounded immutable observations plus explicit quality revisions;
/// it does not decide legality, captures, SGF order or clock arithmetic.
struct CandidateMoveHistory {
    struct View {
        let time:Double
        let processedAt:Double
        let observationID:String?
        let rawPosition:[Occupancy]
        let confidence:[Double]
        let rawConfidence:[Double]
        let estimate:ClockPressEstimate
        let aliases:[Int:Set<Int>]
        var whiteOutlineCenters:[Int:ImagePoint]=[:]
        // Retrospective timing retractions and all quality suspicions differ:
        // immediate masks have already been applied to the effective position.
        var discounted=Set<Int>()
        var shadowSuspects=Set<Int>()
        private(set) var position:[Occupancy]
        func supportsStone(at point:Int)->Bool {
            confidence[point]>=0.9 || (position[point] == .white && whiteOutlineCenters[point] != nil)
        }
        mutating func discount(_ points:Set<Int>) {
            discounted.formUnion(points);shadowSuspects.formUnion(points)
            for p in points where rawPosition.indices.contains(p) && rawPosition[p] == .black {position[p] = .uncertain}
        }
    }
    enum OccupancyState:String,Codable {case present,absent,oppositeColor,multipleStones,uncertain}
    // No shadow-clearance detector exists yet. Hand clearance never sets this
    // to "clear". A future measurement can extend this quality dimension.
    enum ShadowAssessment:String,Codable {case unknown,suspected}
    enum RelativeOrder:String {case before,after,unresolved}
    struct Sighting {
        let observationID:String?
        let capturedAt:Double
        let processedAt:Double
        let rawPoints:Set<Int>
        let visiblePoints:Set<Int>
        let rawScores:[Int:Double]
        let state:OccupancyState
        let shadow:ShadowAssessment
    }
    struct AppearanceInterval:Codable {
        let lastAbsentAt:Double?
        let presentBy:Double
    }
    struct Confirmation:Codable {
        enum Level:String,Codable {case strong,handSupported,consistent,cautious}
        let level:Level
        let clearViews:Int
        let span:Double
        let minimumScore:Double
        // The fresh witness certifying this decision; never a replacement for
        // the placement estimate. A durable press journals this witness once.
        let capturedAt:Double
        let processedAt:Double
        let observationID:String?
        var appearanceSupportedViews:Int?=nil
    }
    struct Snapshot:Codable {
        let episode:String
        let color:Stone
        let possibleLocations:[Int]
        let observedLocation:Int?
        let occupancy:OccupancyState
        let firstAppearanceAt:Double?
        let firstAppearanceObservationID:String?
        let firstSupportedAt:Double?
        let firstSupportedObservationID:String?
        let lastDefiniteAbsenceAt:Double?
        let lastContradictionAt:Double?
        let appearanceInterval:AppearanceInterval?
        let supportedHandExit:ClockPressEstimate?
        let pressEstimate:ClockPressEstimate?
        let confirmation:Confirmation?
        let suspectedShadowSamples:Int
        let shadowClearanceKnown:Bool
    }
    let locations:Set<Int>
    let color:Stone
    let epoch:String
    private let views:[View]
    private let eligible:[View]
    let lastContradictionAt:Double?
    let lastDefiniteAbsenceAt:Double?
    private let timingBoundary:Double

    init(views:[View],locations:Set<Int>,color:Stone,epoch:String,after time:Double,consumedUntil:Double,
         matching:((View)->Bool)?=nil) {
        self.views=views;self.locations=locations;self.color=color;self.epoch=epoch
        lastDefiniteAbsenceAt=views.last {view in locations.allSatisfy{view.position[$0] == .empty}}?.time
        lastContradictionAt=views.last {view in
            locations.allSatisfy{view.position[$0] == .empty} || locations.contains{view.position[$0].stone==color.opponent}
        }?.time
        timingBoundary=Self.boundary(views,points:locations,after:lastContradictionAt ?? -.infinity)
        let boundary=timingBoundary
        eligible=views.filter {view in
            guard view.time>boundary,view.estimate.time>=time,view.estimate.time>consumedUntil else {return false}
            let occupied=locations.filter{view.position[$0].stone != nil}
            return occupied.count==1 && occupied.contains{view.position[$0].stone==color && view.supportsStone(at:$0)} && (matching?(view) ?? true)
        }
    }
    /// Suspect evidence before the first independent sighting prevents unsafe
    /// backdating; suspect evidence afterward is not a definite contradiction.
    static func boundary(_ views:[View],points:Set<Int>,after contradiction:Double)->Double {
        let firstClear=views.first {view in
            view.time>contradiction && points.contains{view.position.indices.contains($0) && view.position[$0].stone != nil}
        }?.time ?? .infinity
        let suspect=views.last {view in view.time<firstClear && !view.discounted.isDisjoint(with:points)}?.time ?? -.infinity
        return max(contradiction,suspect)
    }
    static func supportedEstimate(_ view:View,after contradiction:Double)->ClockPressEstimate {
        guard view.estimate.time>contradiction else {
            return .init(time:view.time,method:.clearFrame,timestampSource:view.estimate.timestampSource,
                         fallbackReason:"Earlier hand estimate predates a contradictory stone reading")
        }
        return view.estimate
    }
    private func supportedEstimate(_ view:View,after contradiction:Double)->ClockPressEstimate {
        Self.supportedEstimate(view,after:contradiction)
    }
    var firstSupportedAt:Double? {eligible.first?.time}
    var pressEstimate:ClockPressEstimate? {eligible.first.map{Self.supportedEstimate($0,after:timingBoundary)}}
    var hasCurrentSupport:Bool {eligible.last != nil && eligible.last?.time==views.last?.time}
    var pendingEstimate:ClockPressEstimate? {hasCurrentSupport ? pressEstimate:nil}
    private var firstAppearance:View? {
        views.first {view in view.time>(lastContradictionAt ?? -.infinity) && locations.contains{view.rawPosition[$0].stone==color}}
    }
    private func state(_ view:View)->OccupancyState {
        let occupied=locations.filter{view.position[$0].stone != nil}
        if occupied.count>1 {return .multipleStones}
        if occupied.contains(where:{view.position[$0].stone==color}) {return .present}
        if !occupied.isEmpty {return .oppositeColor}
        return locations.allSatisfy{view.position[$0] == .empty} ? .absent:.uncertain
    }
    var sightings:[Sighting] {
        views.filter{$0.time>(lastContradictionAt ?? -.infinity)}.map {view in
            .init(observationID:view.observationID,capturedAt:view.time,processedAt:view.processedAt,
                  rawPoints:locations.filter{view.rawPosition[$0].stone==color},
                  visiblePoints:locations.filter{view.position[$0].stone==color},
                  rawScores:Dictionary(uniqueKeysWithValues:locations.map{($0,view.rawConfidence[$0])}),state:state(view),
                  shadow:view.shadowSuspects.isDisjoint(with:locations) ? .unknown:.suspected)
        }
    }
    func snapshot(ignoring:Set<Int>=[])->Snapshot {
        let first=firstAppearance,estimate=pressEstimate
        let current=views.last
        let present=current.map{v in locations.filter{v.position[$0].stone==color}} ?? []
        let identity=first?.observationID ?? first.map{String($0.time)} ?? "unseen"
        return .init(episode:"\(epoch)/\(color.rawValue)/\(locations.sorted())/\(identity)",color:color,
                     possibleLocations:locations.sorted(),observedLocation:present.count==1 ? present.first:nil,
                     occupancy:current.map(state) ?? .uncertain,
                     firstAppearanceAt:first?.time,firstAppearanceObservationID:first?.observationID,
                     firstSupportedAt:firstSupportedAt,firstSupportedObservationID:eligible.first?.observationID,
                     lastDefiniteAbsenceAt:lastDefiniteAbsenceAt,lastContradictionAt:lastContradictionAt,
                     appearanceInterval:firstSupportedAt.map{.init(lastAbsentAt:lastDefiniteAbsenceAt,presentBy:$0)},
                     supportedHandExit:estimate.flatMap{[.handMotion,.handBracket].contains($0.method) ? $0:nil},
                     pressEstimate:estimate,confirmation:confirmation(ignoring:ignoring),
                     suspectedShadowSamples:views.filter{$0.time>(lastContradictionAt ?? -.infinity) && !$0.shadowSuspects.isDisjoint(with:locations)}.count,shadowClearanceKnown:false)
    }
    /// Advisory evidence only. First-detection sorting cannot prove order. Both
    /// stones need repeated support and a repeated empty interval between them;
    /// the legal-history resolver remains responsible for choosing SGF order.
    func relativeOrder(to other:Self)->RelativeOrder {
        guard epoch==other.epoch,locations.isDisjoint(with:other.locations) else {return .unresolved}
        func precedes(_ early:Self,_ late:Self)->Bool {
            guard let first=early.eligible.first,
                  let established=early.eligible.first(where:{$0.time-first.time>=0.15}),
                  let later=late.eligible.first,
                  late.eligible.contains(where:{$0.time-later.time>=0.15}) else {return false}
            let absent=late.views.filter {view in
                view.time>=first.time && view.time<later.time && late.locations.allSatisfy{view.position[$0] == .empty}
            }
            guard let a=absent.first,let b=absent.last else {return false}
            return absent.count>=2 && b.time-a.time>=0.15 && b.time>=established.time
        }
        if precedes(self,other) {return .before}
        if precedes(other,self) {return .after}
        return .unresolved
    }
    func confirmation(ignoring:Set<Int>)->Confirmation? {
        confirmation(ignoring:ignoring,allowAppearance:true)
    }
    private func confirmation(ignoring:Set<Int>,allowAppearance:Bool)->Confirmation? {
        let supported=allowAppearance ? eligible:eligible.filter {view in
            locations.contains {view.position[$0].stone==color && view.confidence[$0]>=0.9}
        }
        guard let first=supported.first,let newest=views.last,supported.last?.time==newest.time else {return nil}
        // Uncertainty interrupts confirmation, but does not erase the earlier
        // timestamp. Definite absence/opposite colour is retracted by callers.
        let unclear=views.last {view in
            view.time>=first.time && locations.filter{view.position[$0].stone != nil}.count != 1
        }?.time ?? -.infinity
        let run=supported.filter{$0.time>unclear}
        guard let start=run.first,let last=run.last else {return nil}
        let scores=run.flatMap {view in locations.compactMap {p in view.position[p].stone != nil ? view.confidence[p]:nil}}
        guard let score=scores.min(),score.isFinite,score>=0.8 else {return nil}
        let ignored=ignoring.union(locations)
        var previous=start.position
        let stable=run.allSatisfy {view in
            guard view.position.filter({$0 == .uncertain}).count<=max(2,view.position.count/20) else {return false}
            let changes=view.position.indices.filter {p in
                !ignored.contains(p) && view.position[p] != .uncertain && previous[p] != .uncertain && view.position[p] != previous[p]
            }
            // A later reply must not invalidate a completed earlier turn.
            // Flickering/removing stones, colour changes, and bursts of new
            // stones elsewhere lower confidence in the whole observation.
            guard changes.count<=1,changes.allSatisfy({previous[$0] == .empty && view.position[$0].stone != nil}) else {return false}
            for p in previous.indices where view.position[p] != .uncertain {previous[p]=view.position[p]}
            return true
        }
        if score<0.9 {
            // A low point-reading score never gets relabeled as high confidence.
            // Instead require at least six recent, stable disk outlines over a
            // full second. Confirm now but retain the FIRST supported timestamp.
            // Faster camera delivery must not shorten the confirmation interval.
            var recent=[View]()
            for view in run.reversed() {
                recent.insert(view,at:0)
                if recent.count>=6,last.time-view.time>=1.0 {break}
            }
            guard color == .white,stable,recent.count>=6,let a=recent.first,let b=recent.last,
                  b.time-a.time>=1.0,zip(recent,recent.dropFirst()).allSatisfy({$0.1.time-$0.0.time<=0.65}) else {
                return confirmation(ignoring:ignoring,allowAppearance:false)
            }
            let centers=recent.compactMap {view in locations.compactMap{view.whiteOutlineCenters[$0]}.first}
            guard centers.count==recent.count,let anchor=centers.first,
                  centers.allSatisfy({hypot($0.x-anchor.x,$0.y-anchor.y)<=0.12}) else {
                return confirmation(ignoring:ignoring,allowAppearance:false)
            }
            return .init(level:.cautious,clearViews:recent.count,span:b.time-a.time,minimumScore:score,
                capturedAt:b.time,processedAt:b.processedAt,observationID:b.observationID,appearanceSupportedViews:recent.count)
        }
        let estimate=supportedEstimate(first,after:timingBoundary)
        let hand=estimate.method == .handMotion || estimate.method == .handBracket
        let handInterval=hand && estimate.observedLower != nil && estimate.observedUpper != nil
        let preciseHand=handInterval && estimate.latestPlausibleTime-estimate.earliestPlausibleTime<=0.6
        let level:Confirmation.Level
        let count:Int,seconds:Double
        if score>=0.97 && stable && preciseHand {
            level = .strong;count=2;seconds=0.2
        } else if stable && handInterval {
            level = .handSupported;count=2;seconds=0.4
        } else if score>=0.97 && stable && !hand {
            level = .consistent;count=4;seconds=0.6
        } else {
            level = .cautious;count=6;seconds=1.0
        }
        let span=last.time-start.time
        guard run.count>=count,span>=seconds else {return nil}
        return .init(level:level,clearViews:run.count,span:span,minimumScore:score,
                     capturedAt:last.time,processedAt:last.processedAt,observationID:last.observationID)
    }

}
