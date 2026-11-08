import Foundation

/// Recover a proposal from recorded sightings, including frames collected while
/// paused. This never changes the game or clock and never invents passes/captures.
enum ReviewOrderRecovery {
    struct Frame {let time:Double;let position:[UInt8];var lightingBlocked=false}
    struct Interval {let point:Int;let color:Stone;let emptyThrough:Double;let presentBy:Double}
    struct Result {
        var orders:[[Int]]=[]
        var intervals:[Interval]=[]
        var message:String
        var turnConflict:Interval?=nil
    }
    private struct Run {var value:UInt8;var first:Double;var last:Double;var count:Int;var clearCount:Int}
    static func symbol(_ value:Occupancy)->UInt8 {
        switch value {case .black:return 66;case .white:return 87;case .empty:return 46;case .uncertain:return 63}
    }
    static func recover(before:[Occupancy],after:[Occupancy],first:Stone,frames:[Frame])->Result {
        guard before.count==after.count,!before.isEmpty else {return Result(message:"The saved board sizes do not match.")}
        let points=before.indices.filter{before[$0] != after[$0]}
        guard !points.isEmpty,points.count<=64,points.allSatisfy({before[$0] == .empty && after[$0].stone != nil}) else {
            return Result(message:"This section includes removals or changed colors. Its captures or camera corrections still need manual review.")
        }
        let expected=before.map(symbol)
        // Start from the last clear view of the starting position. A later hand
        // shadow must not turn an old flash into a supposed early black move.
        let baseline=frames.lastIndex {frame in
            !frame.lightingBlocked && frame.position.count==expected.count && points.allSatisfy{frame.position[$0]==46} &&
                expected.indices.allSatisfy{frame.position[$0]==expected[$0] || frame.position[$0]==63}
        }
        guard let baseline else {return Result(message:"No clear starting position was retained for this section. Keep the manual review.")}
        let input=frames.dropFirst(max(0,baseline-24))
        var intervals=[Interval]()
        // A global lighting pause does not erase locally repeated sightings.
        // Require a matching unblocked reading within each run, so a run seen
        // only during disturbed lighting cannot establish a placement boundary.
        for point in points {
            let final=symbol(after[point])
            var run:Run?,runs=[Run]()
            func retain(_ value:Run?) {
                if let value,value.value != 63,value.count>=3,value.clearCount>0,value.last-value.first>=0.4 {runs.append(value)}
            }
            for frame in input where frame.position.count==expected.count {
                let v=frame.position[point],value:UInt8=(v==46 || v==final) ? v:63
                if var previous=run,previous.value==value,frame.time>previous.last,frame.time-previous.last<=1.5 {
                    previous.last=frame.time;previous.count+=1;if !frame.lightingBlocked {previous.clearCount+=1};run=previous
                } else {retain(run);run=Run(value:value,first:frame.time,last:frame.time,count:1,clearCount:frame.lightingBlocked ? 0:1)}
            }
            retain(run)
            guard let empty=runs.last(where:{$0.value==46}),
                  let present=runs.first(where:{$0.value==final && $0.first>empty.last}) else {
                return Result(message:"Some stones lack repeated empty-to-stone sightings. Their order still needs manual review.")
            }
            intervals.append(Interval(point:point,color:after[point].stone!,emptyThrough:empty.last,presentBy:present.first))
        }
        // Only nonoverlapping placement intervals establish precedence. When
        // intervals overlap, enumerate alternating orders instead of guessing.
        var orders=[[Int]](),nodes=0,exhausted=false
        func visit(_ remaining:[Interval],_ path:[Int],_ color:Stone) {
            guard !exhausted else {return}
            nodes+=1
            if nodes>20000 || orders.count>=32 {exhausted=true;return}
            if remaining.isEmpty {orders.append(path);return}
            for candidate in remaining where candidate.color==color {
                guard !remaining.contains(where:{$0.point != candidate.point && $0.presentBy<candidate.emptyThrough}) else {continue}
                visit(remaining.filter{$0.point != candidate.point},path+[candidate.point],color.opponent)
            }
        }
        visit(intervals,[],first)
        if exhausted {return Result(intervals:intervals,message:"Too many orders fit the available sightings. The missing interval still needs manual review.")}
        guard !orders.isEmpty else {
            let earliest=intervals.first {candidate in
                candidate.color != first && intervals.allSatisfy {$0.point==candidate.point || candidate.presentBy<=$0.emptyThrough}
            }
            return Result(intervals:intervals,message:earliest == nil
                ? "The sightings and alternating turns disagree. Check for a missed pass or camera error."
                : "The camera saw \(earliest!.color.rawValue.capitalized) first, but the saved game expects \(first.rawValue.capitalized). This may be an out-of-turn placement; do not change a stone’s color unless the camera got it wrong.",turnConflict:earliest)
        }
        return Result(orders:orders,intervals:intervals,message:orders.count==1
            ? "One order fits the repeated sightings. Check the numbered moves before saving."
            : "\(orders.count) orders fit the repeated sightings. Choose the order you played; the other moves will be numbered for you.")
    }
    /// Bounded, background-only read. Keep original wall-clock ordering across
    /// app restarts, and exclude observations later than this frozen review.
    static func load(url:URL,before:[Occupancy],after:[Occupancy],first:Stone,through:Double)throws->Result {
        let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
        let length=try handle.seekToEnd(),limit:UInt64=64*1024*1024
        let offset=length>limit ? length-limit:0
        try handle.seek(toOffset:offset)
        let data=try handle.readToEnd() ?? Data()
        var lines=data.split(separator:10)
        if offset>0,!lines.isEmpty {lines.removeFirst()}
        var frames=[Frame]()
        for line in lines {
            guard let entry=try? JSONSerialization.jsonObject(with:Data(line)) as? [String:Any],
                  entry["event"] as? String=="observation",
                  let time=entry["time"] as? Double,time<=through,
                  let position=entry["position"] as? String,position.utf8.count==before.count else {continue}
            frames.append(Frame(time:time,position:Array(position.utf8),lightingBlocked:entry["lightingBlocked"] as? Bool ?? false))
        }
        return recover(before:before,after:after,first:first,frames:frames)
    }
}
