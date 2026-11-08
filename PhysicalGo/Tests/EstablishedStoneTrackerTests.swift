import Foundation

@main struct EstablishedStoneTrackerTests {
    static func main() throws {
        setbuf(stdout,nil);var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        func view(_ stones:[Int:Occupancy],offsets:[Int:ImagePoint]=[:],unknown:Set<Int>=[],quality:Double=0.98,size:Int=9)->BoardObservation {
            let readings=(0..<size*size).map {i in IntersectionReading(row:i/size,col:i%size,occupancy:unknown.contains(i) ? .uncertain:stones[i] ?? .empty,confidence:0.98,delta:0)}
            let shapes=stones.keys.sorted().map {p in StoneFootprint(row:p/size,col:p%size,
                center:offsets[p] ?? .init(x:Double(p%size),y:Double(p/size)),radiusCol:0.5,radiusRow:0.5,quality:quality)}
            return .init(readings:readings,size:size,footprints:shapes)
        }
        let expected=(0..<81).map {$0==40 ? Occupancy.white:.empty}
        var t=EstablishedStoneTracker(),now=0.0
        func feed(_ observation:BoardObservation,_ count:Int=3,context:String="game")->BoardObservation {
            var result=observation
            for _ in 0..<count {now += 0.51;result=t.observe(observation,expected:expected,context:context,now:now)}
            return result
        }
        let centered=view([40:.white])
        _=feed(centered,2);check(t.tracks.isEmpty,"Initialized from fewer than three independent views")
        _=feed(centered,1);check(t.tracks.count==1,"Stable stone not established")
        let nudged=view([40:.white],offsets:[40:.init(x:4.25,y:4)])
        _=feed(nudged,2);check(t.tracks[40]!.shape.center.x==4,"One nudge immediately replaced stable geometry")
        _=feed(nudged,1);check(t.tracks[40]!.shape.center.x==4.25,"Stable off-center position did not update")
        check(t.tracks[40]!.point==40,"Nudge changed logical identity")
        let saved=t.tracks[40]!.shape.center
        _=feed(view([:],unknown:[40]),4)
        check(t.tracks[40]!.shape.center==saved,"Occlusion erased the prior physical center")
        check(t.report.uncertain==[40],"Missing outline not reported")
        _=feed(nudged,3)
        let stableTime=now
        _=t.observe(nudged,expected:expected,context:"game",now:now+0.1)
        check(!t.report.scanned,"Background scan ignored rate limit")
        _=t.observe(nudged,expected:expected,context:"game",now:now+0.1)
        check(!t.report.scanned,"Duplicate timestamp produced evidence")
        now=stableTime+0.2
        // Two fitted labels for ONE disk. Both fits see the same physical center.
        let duplicate=view([40:.white,41:.white],offsets:[40:.init(x:4.50,y:4),41:.init(x:4.50,y:4)])
        let firstDuplicate=feed(duplicate,1)
        check(firstDuplicate.signature[41] == .uncertain,"Duplicate entered move evidence while physical update was pending")
        check(t.tracks[40]!.shape.center.x==4.25,"Duplicate quarantine prematurely moved the physical anchor")
        let resolved=feed(duplicate,2)
        check(resolved.signature[40] == .white && resolved.signature[41] == .uncertain,"One disk was counted twice")
        check(resolved.trackedAssignments==[41:40],"Derived assignment lacks provenance")
        check(duplicate.signature[41] == .white && duplicate.trackedAssignments.isEmpty,"Raw camera evidence was overwritten")
        let shiftedAlias=view([41:.white],offsets:[41:.init(x:4.52,y:4)],unknown:[40])
        let associated=feed(shiftedAlias)
        check(associated.signature[40] == .white && associated.signature[41] == .uncertain,"Shifted disk lost its established identity")
        let definiteEmpty=view([41:.white],offsets:[41:.init(x:4.52,y:4)])
        check(feed(definiteEmpty).signature[40] == .empty,"A definite empty observation was overridden")
        let two=view([40:.white,41:.white])
        let untouched=feed(two)
        check(untouched.signature[41] == .white && untouched.trackedAssignments.isEmpty,"Two real stones merged")
        check(t.tracks[41]==nil,"New move enrolled before authoritative game update")
        // A recorded stone may disappear in a capture; never fill it from history.
        let absent=feed(view([:]))
        check(absent.signature[40] == .empty,"History filled a missing/captured stone")
        _=t.observe(view([:]),expected:Array(repeating:.empty,count:81),context:"game",now:now+0.51)
        check(t.tracks.isEmpty,"Captured identity retained after game update")
        now += 0.51
        _=feed(centered)
        let original=t.tracks[40]!.shape.center
        _=feed(view([40:.white],offsets:[40:.init(x:4.3,y:4)],quality:0.75))
        check(t.tracks[40]!.shape.center==original,"Weak outline poisoned tracking")
        var manual=duplicate;manual.manualPoints=[40,41]
        check(feed(manual).trackedAssignments.isEmpty,"Tracking overrode manual corrections")
        var blocked=centered;blocked.lightingBlocked=true
        _=feed(blocked,1);check(t.tracks.isEmpty,"Lighting failure retained active associations")
        _=feed(centered)
        _=feed(duplicate,1,context:"different game");check(t.tracks.isEmpty,"Track reused across games/orientations")
        _=feed(centered)
        now += 3
        _=feed(duplicate,1);check(t.tracks.isEmpty,"Camera gap retained active associations")
        _=feed(centered)
        let wildlyMoved=view([40:.white],offsets:[40:.init(x:4.75,y:4)])
        _=feed(wildlyMoved)
        check(t.tracks[40]!.shape.center.x==4,"Historical center drifted into a neighboring intersection")
        // Simultaneous coherent motion belongs to grid recovery, not individual nudges.
        let group:[Int:Occupancy]=[20:.black,24:.white,56:.white,60:.black]
        let expectedGroup=(0..<81).map{group[$0] ?? .empty}
        var motion=EstablishedStoneTracker()
        for n in 0..<3 {_=motion.observe(view(group),expected:expectedGroup,context:"group",now:Double(n)*0.51)}
        let shifted=view(group,offsets:Dictionary(uniqueKeysWithValues:group.keys.map{($0,ImagePoint(x:Double($0%9)+0.25,y:Double($0/9)))}))
        _=motion.observe(shifted,expected:expectedGroup,context:"group",now:1.53)
        check(!motion.report.possibleBoardShift,"One motion frame triggered board recovery")
        _=motion.observe(shifted,expected:expectedGroup,context:"group",now:2.04)
        check(motion.report.possibleBoardShift,"Coordinated motion was assimilated as independent nudges")
        check(motion.tracks[20]!.shape.center.x==2,"Coordinated shift overwrote anchored geometry")
        // Ambiguous same-color neighbors cannot share a disk.
        var shared=EstablishedStoneTracker()
        var expectedPair=expected;expectedPair[41] = .white
        for n in 0..<3 {_=shared.observe(two,expected:expectedPair,context:"pair",now:Double(n)*0.51)}
        for n in 3..<8 {
            let out=shared.observe(duplicate,expected:expectedPair,context:"pair",now:Double(n)*0.51)
            check(out.trackedAssignments.isEmpty,"Ambiguous disk assigned to two established stones")
        }
        // Replay measured outlines, not invented labels, from the saved off-center clip.
        struct Frame:Decodable {let captureUptime:Double;let readings:[IntersectionReading];let footprints:[StoneFootprint];let placementFits:[StoneFootprint]}
        let file=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/UniqueOffCenter/observations.json")
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:file))
        var historical=EstablishedStoneTracker(),samples=0
        let accepted=frames.last!.readings.map(\.occupancy).map{$0 == .uncertain ? Occupancy.empty:$0}
        for frame in frames {
            let observation=BoardObservation(readings:frame.readings,size:19,footprints:frame.footprints,placementFits:frame.placementFits)
            let out=historical.observe(observation,expected:accepted,context:"archive",now:frame.captureUptime)
            check(out.signature==observation.signature,"Tracker changed archived camera classifications without a duplicate")
            samples += 1
        }
        check(!historical.tracks.isEmpty,"Saved camera outlines never established physical tracks")
        var dense=EstablishedStoneTracker(),costs=[Double]()
        let packed=Dictionary(uniqueKeysWithValues:(0..<361).map{($0,$0%2==0 ? Occupancy.black:.white)})
        let packedView=view(packed,size:19),packedExpected=packedView.signature
        for n in 0..<200 {
            _=dense.observe(packedView,expected:packedExpected,context:"dense",now:Double(n)*0.21)
            costs.append(dense.report.processingSeconds)
        }
        print("Tracking 361 stones: mean \(costs.reduce(0,+)/Double(costs.count)*1000) ms; p95 \(costs.sorted()[189]*1000) ms")
        print("PASS: \(checks) established-stone checks; \(samples) historical observations; periodic updates, nudges, duplicate disks, real neighbors, capture, manual labels, gaps, lighting, and coordinated motion")
    }
}
