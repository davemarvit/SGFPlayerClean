import Foundation

/// Camera evidence for legal prisoners, independent of move/clock completion.
/// No hardware, clock, game-history, or intended-intersection inference lives here.
struct PhysicalCaptureGuidance {
    struct Identity: Equatable {let session:UUID;let moveNumber:Int}
    struct Saved: Codable, Equatable {
        let moveNumber:Int
        let acceptedAtUnix:Double
        var removed:[Int]=[]
    }
    private struct Witness {let value:String;let first:Double;var last:Double;var count:Int}
    private(set) var identity:Identity?
    private(set) var prisoners:[Int:String]=[:]
    private(set) var removed=Set<Int>()
    private(set) var selected:Int?
    private(set) var placementConfirmed=false
    private var placement:(point:Int,color:String)?
    private var evidence:[Int:Witness]=[:]
    private var context:String?
    private var lastStamp:Double?
    private var evidenceAfter=0.0
    var remainingCount:Int {prisoners.count-removed.count}
    var pending:Bool {identity != nil}

    mutating func configure(identity:Identity,prisoners:[Int:String],placement:(Int,String)?,removed:[Int],evidenceAfter:Double) {
        guard self.identity != identity else {return}
        self=Self();self.identity=identity;self.prisoners=prisoners;self.evidenceAfter=evidenceAfter
        self.placement=placement.map {($0.0,$0.1)}
        self.removed=Set(removed).intersection(prisoners.keys)
        placementConfirmed=placement == nil
    }
    /// A combined cleanup/reply needs current, stable positive empty evidence
    /// for every other prisoner. A move on a prisoner point is allowed only if
    /// that prisoner was positively removed earlier; the old stone is not a reply.
    /// The persisted removal ledger alone cannot prove other points remain empty.
    func permitsReply(at point:Int)->Bool {
        guard pending else {return true}
        return prisoners.keys.allSatisfy {prisoner in
            if prisoner==point {return removed.contains(prisoner)}
            guard let witness=evidence[prisoner],let lastStamp else {return false}
            return witness.value=="empty" && witness.last==lastStamp &&
                witness.count>=3 && witness.last-witness.first>=0.45
        }
    }
    mutating func clear() {self=Self()}
    /// Hand/unknown evidence clears temporal witnesses. Pause/context change also
    /// discards physical AI-placement evidence, but never changes logical play.
    mutating func invalidate(dropPlacement:Bool=false,after:Double?=nil) {
        if let after {evidenceAfter=max(evidenceAfter,after)}
        evidence=[:]
        if dropPlacement {placementConfirmed=placement == nil;context=nil}
    }
    /// Caller supplies only positively classified, unambiguous cells from an
    /// admitted dark frame. nil means unknown; neither history nor light qualifies.
    /// Returns a prisoner positively present for >=3 frames spanning >=0.45s.
    mutating func observe(identity:Identity,values:[String?],stamp:Double,now:Double,context:String)->Int? {
        guard self.identity==identity else {return nil}
        guard stamp.isFinite,now.isFinite,stamp>=evidenceAfter,(0..<1.5).contains(now-stamp),!context.isEmpty else {invalidate();return nil}
        if let lastStamp,stamp<=lastStamp {return nil}
        if self.context != context {invalidate(dropPlacement:true);self.context=context}
        if let lastStamp,stamp-lastStamp>0.6 {invalidate()}
        lastStamp=stamp
        let points=Set(prisoners.keys).union(placement.map {[$0.point]} ?? [])
        var stable:[Int:String]=[:]
        for point in points {
            guard values.indices.contains(point),let value=values[point],["empty","black","white"].contains(value) else {evidence[point]=nil;continue}
            if var old=evidence[point],old.value==value,stamp-old.last<=0.6 {
                old.last=stamp;old.count+=1;evidence[point]=old
            } else {evidence[point]=Witness(value:value,first:stamp,last:stamp,count:1)}
            if let witness=evidence[point],witness.count>=3,stamp-witness.first>=0.45 {stable[point]=value}
        }
        if let placement,stable[placement.point]==placement.color {placementConfirmed=true}
        for point in prisoners.keys where stable[point]=="empty" {removed.insert(point)}
        if let selected,removed.contains(selected) {self.selected=nil}
        let present=prisoners.keys.filter {!removed.contains($0) && stable[$0]==prisoners[$0]}.sorted()
        if selected==nil {selected=present.first}
        guard placementConfirmed,let selected,present.contains(selected) else {return nil}
        return selected
    }
}
