import Foundation

/// Durable chronology after an unresolved gap. This is a recovery record, not
/// accepted SGF history. Each stable physical transition is retained separately.
struct DeferredMoveHistory:Codable {
    struct Move:Codable,Equatable {
        let color:Stone
        let point:BoardPosition?
    }
    struct Section:Codable,Identifiable {
        var id=UUID()
        var reviewNumber:Int?
        var before:[Occupancy]
        var after:[Occupancy]
        var moves:[Move]?
        var resolvedAfter:[Occupancy]?
        var committed=false
        var savedStart:Int?
        var manual:Bool?
        var evidenceFolder:String?
        var suggestedOrders:[[Move]]?
        var reason:String
        var firstSeen:Double
        var confirmedAt:Double
        var recordedAt=Date().timeIntervalSince1970
        var resolvedAt:Double?
        var recoverySource:String?
        var undoneMoveNumbers:[Int]?
        // Observed turn is independent of later edits to historical move order.
        var liveNext:Stone?
    }
    var version=1
    var size=19
    var anchorSignature:String?
    var baseMove:Int?
    var endRequested=false
    var turnOverride:Stone?
    var scoredPosition:[Occupancy]?
    var sections:[Section]=[]
    private var candidate:[Occupancy]?
    private var first=0.0,last=0.0,frames=0
    private enum CodingKeys:String,CodingKey {case version,size,anchorSignature,baseMove,endRequested,sections,turnOverride,scoredPosition}
    var active:Bool {sections.contains{!$0.committed}}
    var reviews:[Section] {sections.filter{$0.reviewNumber != nil}}
    var unresolved:Int {sections.filter{!$0.committed && $0.moves == nil}.count}
    var retainedMoveCount:Int {sections.filter{!$0.committed}.reduce(0){$0+($1.moves?.count ?? 0)}}
    var latest:[Occupancy]? {sections.last(where:{!$0.committed})?.after}
    var nextColor:Stone? {turnOverride ?? sections.last(where:{!$0.committed}).flatMap{$0.liveNext ?? $0.moves?.last?.color.opponent}}
    var nextReviewNumber:Int {(reviews.compactMap(\.reviewNumber).max() ?? 0)+1}
    mutating func interrupt() {candidate=nil;frames=0;first=0;last=0}
    static func states(_ board:BoardSnapshot)->[Occupancy] {board.grid.flatMap{$0}.map{$0 == .black ? .black:$0 == .white ? .white:.empty}}
    static func board(_ states:[Occupancy],size:Int)->BoardSnapshot {
        var grid=Array(repeating:Array<Stone?>(repeating:nil,count:size),count:size),stones=[BoardPosition:Stone]()
        for (point,value) in states.enumerated() where point<size*size {
            grid[point/size][point%size]=value.stone
            if let stone=value.stone {stones[BoardPosition(point/size,point%size)]=stone}
        }
        return BoardSnapshot(size:size,grid:grid,stones:stones)
    }
    static func positionGame(_ states:[Occupancy],size:Int,rules:String?,turn:Stone)->SGFGame {
        var game=SGFGame();game.boardSize=size;game.initialPlayer=turn;game.info.rules=rules ?? "Japanese"
        game.setup=states.enumerated().compactMap{p,value in value.stone.map{($0,p%size,p/size)}}
        return game
    }
    /// Camera uncertainty is never a new stone or a capture. Existing ambiguous
    /// points retain the previous physical interpretation until clear evidence.
    @MainActor mutating func observe(_ observation:BoardObservation,base:BoardSnapshot,game:SGFGame,
                                    signature:String,now:Double,allowStart:Bool)->Bool {
        guard active || allowStart else {interrupt();return false}
        guard observation.size==game.boardSize,observation.readings.count==game.boardSize*game.boardSize,
              !observation.lightingBlocked else {interrupt();return false}
        let baseline=latest ?? Self.states(base)
        guard observation.readings.filter({$0.occupancy == .uncertain}).count<=max(2,baseline.count/20) else {interrupt();return false}
        let current=observation.readings.enumerated().map {point,r in
            r.occupancy == .uncertain || r.confidence<0.8 ? baseline[point]:r.occupancy
        }
        guard current != baseline else {interrupt();return false}
        if candidate != current || now-last>1.5 || now<=last {
            candidate=current;first=now;frames=1;last=now;return false
        }
        frames += 1;last=now
        guard frames>=5,now-first>=0.8 else {return false}
        let started=first;interrupt()
        let wasActive=active
        let previousTurn=wasActive ? nextColor : (game.moves.last?.0.opponent ?? game.initialPlayer ?? .black)
        if !wasActive {size=game.boardSize;anchorSignature=signature;baseMove=game.moves.count}
        let additions=current.indices.filter{current[$0].stone != nil && current[$0] != baseline[$0]}
        var ordered:[Move]?
        if wasActive,additions.count==1,let color=current[additions[0]].stone,
           nextColor == nil || nextColor==color {
            let point=additions[0]
            let trial=SGFPlayer();trial.load(game:Self.positionGame(baseline,size:size,rules:game.info.rules,turn:color))
            if trial.tryPlayMove(color:color,x:point%size,y:point/size)==nil,Self.states(trial.board)==current {
                ordered=[Move(color:color,point:BoardPosition(point/size,point%size))]
            }
        }
        let number=ordered == nil ? nextReviewNumber:nil
        var next=ordered?.last?.color.opponent
        // Without captures/replacements, color counts can identify the next
        // player even when the order of same-color stones is unknown.
        if next == nil,let previousTurn,
           baseline.indices.allSatisfy({baseline[$0] == .empty || baseline[$0]==current[$0]}) {
            let own=additions.filter{current[$0].stone==previousTurn}.count
            let other=additions.count-own
            if own==other || own==other+1 {next=own==other ? previousTurn:previousTurn.opponent}
        }
        turnOverride=nil
        sections.append(Section(reviewNumber:number,before:baseline,after:current,moves:ordered,
                                reason:ordered == nil ? "The move order across this change needs your review.":"Observed in order after an earlier gap; checked again when the gaps are resolved.",
                                firstSeen:started,confirmedAt:now,liveNext:next))
        return true
    }
    mutating func requireReview(at index:Int,reason:String) {
        if let previous=sections[index].moves,!previous.isEmpty {
            sections[index].suggestedOrders=(sections[index].suggestedOrders ?? [])+[previous]
        }
        if sections[index].reviewNumber == nil {sections[index].reviewNumber=nextReviewNumber}
        sections[index].moves=nil;sections[index].resolvedAfter=nil;sections[index].resolvedAt=nil;sections[index].reason=reason
    }
    func validate(size expectedSize:Int,signature:String)->Bool {
        guard version==1,size==expectedSize,Set(sections.map(\.id)).count==sections.count,
              Set(reviews.compactMap(\.reviewNumber)).count==reviews.count,
              (!active || anchorSignature==signature),sections.count<=10000 else {return false}
        return sections.allSatisfy {s in
            s.before.count==size*size && s.after.count==size*size &&
            !s.before.contains(.uncertain) && !s.after.contains(.uncertain) &&
            (s.resolvedAfter == nil || s.resolvedAfter!.count==size*size) &&
            (s.moves?.allSatisfy{m in m.point.map{(0..<size).contains($0.row) && (0..<size).contains($0.col)} ?? true} ?? !s.committed)
        }
    }
}
