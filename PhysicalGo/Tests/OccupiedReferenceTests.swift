import Foundation
import ImageIO

@main struct OccupiedReferenceTests {
    struct Frame:Decodable {let image:String,time:Double,calibration:BoardCalibration,readings:[IntersectionReading];let footprints:[StoneFootprint]?}
    static func main() throws {
        setbuf(stdout,nil);var checks=0
        func check(_ yes:Bool,_ why:String) {checks+=1;if !yes {print("FAIL",why);exit(1)}}
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/OccupiedReference")
        func photo(_ url:URL)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!)!}
        let cases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("cases.json")))
        let photos=cases.map{photo(root.appendingPathComponent($0.image))}
        let raw=cases.map{BoardObservation(readings:$0.readings,size:19)}
        var expected=[Occupancy](repeating:.empty,count:361)
        for p in [60,72,281,300,318,337] {expected[p] = .black}
        for p in [288,299,317,319,320] {expected[p] = .white}
        var reference=OccupiedReference(),time=cases[0].time
        func capture() {check(reference.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:expected,identity:"camera/game",now:time),"capture")}
        func feed(_ i:Int,independent:BoardObservation?=nil,valid:Bool=true,identity:String="camera/game",refresh:Bool=true)->BoardObservation {
            reference.observe(raw[i],independent:independent ?? raw[i],frame:photos[i],calibration:cases[i].calibration,
                expected:expected,identity:identity,now:time,valid:valid,allowRefresh:refresh)
        }
        capture();var fullMatches=0
        // A chosen AI destination still has an empty physical reference. It
        // must revalidate weak camera readings, but never erase a seen stone.
        var awaitingAI=reference
        var emptyTarget=raw[0]
        emptyTarget.readings[316] = .init(row:16,col:12,occupancy:.uncertain,confidence:0,delta:0)
        var targetSupport=false
        for j in 1...5 {
            let result=awaitingAI.observe(emptyTarget,independent:emptyTarget,frame:photos[0],calibration:cases[0].calibration,expected:expected,identity:"camera/game",now:time+Double(j)*0.2,valid:true,allowRefresh:false)
            targetSupport = targetSupport || (result.signature[316] == .empty && result.readings[316].confidence>=0.9)
        }
        check(targetSupport,"pending AI target lost verified empty support")
        var seenBlack=emptyTarget
        seenBlack.readings[316] = .init(row:16,col:12,occupancy:.black,confidence:1,delta:0.4)
        let arrived=awaitingAI.observe(seenBlack,independent:seenBlack,frame:photos[0],calibration:cases[0].calibration,expected:expected,identity:"camera/game",now:time+1.2,valid:true,allowRefresh:false)
        check(arrived.signature[316] == .black,"empty target reference erased independently detected AI stone")
        for i in 1..<cases.count {
            time=cases[i].time;let result=feed(i)
            if result.readings.enumerated().allSatisfy({$0.element.occupancy==expected[$0.offset] && $0.element.confidence>=0.8}) {fullMatches+=1}
            check(result.signature[297] != .white,"invented D7 stone")
        }
        check(fullMatches>=3,"real 11-stone sequence did not verify: \(fullMatches) full frames")
        let placedCases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("d7-cases.json")))
        var placedReference=reference,newWhites=0
        for f in placedCases {
            let pixels=photo(root.appendingPathComponent(f.image)),r=BoardObservation(readings:f.readings,size:19)
            let result=placedReference.observe(r,independent:r,frame:pixels,calibration:f.calibration,expected:expected,identity:"camera/game",now:f.time,valid:true,allowRefresh:true)
            if result.signature[297] == .white {newWhites+=1}
            check(result.signature[297] != .empty,"new D7 was absorbed as empty")
            check(placedReference.report.recognizedWhite.allSatisfy{$0==297 || expected[$0] == .white},"glare was recognized as an extra White")
        }
        check(newWhites>=3,"actual current-light D7 did not become White: \(newWhites)")
        // A committed move may invalidate nearby anchors, but fresh object
        // evidence against the genuine before-image must survive persistence.
        placedReference=try JSONDecoder().decode(OccupiedReference.self,from:JSONEncoder().encode(placedReference))
        var after=expected;after[297] = .white
        let last=placedCases.last!,lastPixels=photo(root.appendingPathComponent(last.image))
        let lastRaw=BoardObservation(readings:last.readings,size:19)
        var postCommitWhites=0,postCommitNeighbor=0
        for j in 1...70 {
            let result=placedReference.observe(lastRaw,independent:lastRaw,frame:lastPixels,calibration:last.calibration,expected:after,identity:"camera/game",now:last.time+Double(j)*0.2,valid:true,allowRefresh:true)
            if result.signature[297] == .white {postCommitWhites+=1}
            if result.signature[317] == .white {postCommitNeighbor+=1}
            check(placedReference.report.recognizedWhite.allSatisfy{$0==297 || expected[$0] == .white},"post-commit extra White")
        }
        check(postCommitWhites>=60,"new White lost independent evidence after commit/archive")
        check(postCommitNeighbor>=60,"actual unchanged neighbor lost after D7 commit")
        // A hand/laser interruption must restart the consecutive new-stone proof.
        _=placedReference.observe(lastRaw,independent:lastRaw,frame:lastPixels,calibration:last.calibration,expected:after,identity:"camera/game",now:last.time+15,valid:false,allowRefresh:true)
        check(placedReference.report.recognizedWhite.isEmpty,"obstructed White witness")
        // Partial references support clear regions without assigning an
        // uncertain stone (or its alternative intersections) a false label.
        var partial=OccupiedReference(),partialLabels=expected
        partialLabels[317] = .uncertain
        check(partial.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:partialLabels,identity:"partial",now:0),"partial capture rejected uncertain label")
        let masked=OccupiedReference.neighborhood([317],size:19)
        var partialRaw=raw[7];partialRaw.readings[317] = .init(row:16,col:13,occupancy:.uncertain,confidence:0,delta:0)
        var partialRefreshed=Set<Int>()
        for j in 1...70 {
            let result=partial.observe(partialRaw,independent:partialRaw,frame:photos[7],calibration:cases[7].calibration,expected:partialLabels,identity:"partial",now:Double(j)*0.2,valid:true,allowRefresh:true)
            partialRefreshed.formUnion(partial.report.refreshed)
            check(result.signature[317] == .uncertain,"partial reference guessed uncertain stone")
            check(Set(partial.report.resolved).isDisjoint(with:masked),"uncertain neighbor was resolved")
        }
        check(!partialRefreshed.isEmpty && partial.generation>1,"uncertain region blocked clear-area refresh")
        check(partialRefreshed.isDisjoint(with:masked),"uncertain neighborhood was trained")
        var displaced=raw[7]
        displaced.readings[317] = .init(row:16,col:13,occupancy:.white,confidence:1,delta:0)
        displaced.footprints.append(.init(row:16,col:13,center:.init(x:13.48,y:16),radiusCol:0.47,radiusRow:0.47,quality:1))
        let ambiguous=OccupiedReference.uncertainLocations(displaced,expected:expected)
        check(ambiguous.isSuperset(of:masked),"displaced stone alternatives were not masked")
        var ambiguousRef=reference
        _=ambiguousRef.observe(displaced,independent:displaced,frame:photos[7],calibration:cases[7].calibration,expected:expected,identity:"camera/game",now:cases.last!.time+0.2,valid:true,allowRefresh:true)
        check(Set(ambiguousRef.report.resolved).isDisjoint(with:masked),"displaced stone masked only for capture")
        // Real startup grid refinement (~0.064 intersection) must not discard
        // the reviewed reference. New stone and full board still need evidence.
        let restartCases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("restart-cases.json")))
        var restarted=try JSONDecoder().decode(OccupiedReference.self,from:Data(contentsOf:root.appendingPathComponent("reviewed-reference.json")))
        var restartWhites=0,restartFull=0
        for f in restartCases {
            var r=BoardObservation(readings:f.readings,size:19);r.footprints=f.footprints ?? []
            let result=restarted.observe(r,independent:r,frame:photo(root.appendingPathComponent(f.image)),calibration:f.calibration,expected:expected,identity:restarted.identity,now:f.time,valid:true,allowRefresh:true)
            if result.signature[297] == .white {restartWhites+=1}
            if result.readings.enumerated().allSatisfy({$0.element.occupancy==after[$0.offset] && $0.element.confidence>=0.8}) {restartFull+=1}
            check(restarted.hasReference,"natural grid refinement discarded archive")
            check(restarted.report.recognizedWhite.allSatisfy{$0==297 || expected[$0] == .white},"restart invented White")
        }
        check(restartWhites>=3,"D7 not recognized after actual restart: \(restartWhites)")
        check(restartFull>=3,"actual restart did not verify whole position: \(restartFull)")
        // Real quick reply: Black A6 and White B8 are both physically present.
        // Seed from the reviewed 14-stone photograph taken before either move.
        let b8Cases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("b8-cases.json")))
        let beforeB8=photo(root.appendingPathComponent("before-b8.png"))
        let beforeCal=try JSONDecoder().decode(BoardCalibration.self,from:Data(contentsOf:root.appendingPathComponent("before-b8-calibration.json")))
        var fourteen=after;fourteen[335] = .black;fourteen[336] = .white
        var fifteen=fourteen;fifteen[355] = .black
        var sixteen=fifteen;sixteen[334] = .white
        var b8=OccupiedReference()
        check(b8.captureConfirmed(frame:beforeB8,calibration:beforeCal,position:fourteen,identity:"b8",now:0),"14-stone seed")
        var negative=BoardObservation(readings:fourteen.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
        negative.readings[334] = .init(row:17,col:11,occupancy:.uncertain,confidence:0,delta:0)
        for j in 1...8 {
            let result=b8.observe(negative,independent:negative,frame:beforeB8,calibration:beforeCal,expected:fourteen,identity:"b8",now:Double(j)*0.2,valid:true,allowRefresh:true)
            check(result.signature[334] != .white,"before-B8 empty became White")
        }
        var b8Full=0,b8Consecutive=0,b8Longest=0
        for f in b8Cases {
            var r=BoardObservation(readings:f.readings,size:19);r.footprints=f.footprints ?? []
            let result=b8.observe(r,independent:r,frame:photo(root.appendingPathComponent(f.image)),calibration:f.calibration,expected:fifteen,identity:"b8",now:f.time,valid:true,allowRefresh:true)
            check(b8.report.recognizedWhite.allSatisfy{$0==334 || fifteen[$0] == .white},"B8 replay invented extra White")
            if result.readings.enumerated().allSatisfy({$0.element.occupancy==sixteen[$0.offset] && $0.element.confidence>=0.8}) {b8Full+=1;b8Consecutive+=1;b8Longest=max(b8Longest,b8Consecutive)} else {b8Consecutive=0}
        }
        check(b8Longest>=3,"quick reply never had enough consecutive full-board witnesses")
        var removedB8=negative;removedB8.readings[334] = .init(row:17,col:11,occupancy:.uncertain,confidence:0,delta:0)
        let gone=b8.observe(removedB8,independent:removedB8,frame:beforeB8,calibration:beforeCal,expected:sixteen,identity:"b8",now:b8Cases.last!.time+0.2,valid:true,allowRefresh:true)
        check(gone.signature[334] != .white,"temporal retention erased actual stone removal")
        check(b8Full>=3,"real 16-stone quick reply not fully observed: \(b8Full)")
        // Placing C7 changes adjacent White appearance slightly. Bounded body
        // noise must not lose those stones, or manufacture another White.
        let c7Cases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("c7-cases.json")))
        var c7=try JSONDecoder().decode(OccupiedReference.self,from:Data(contentsOf:root.appendingPathComponent("before-c7-confirmation.json")))
        let c7Before=c7.position
        var seventeen=c7Before;seventeen[316] = .black
        var c7Consecutive=0,c7Longest=0
        for f in c7Cases {
            var r=BoardObservation(readings:f.readings,size:19);r.footprints=f.footprints ?? []
            let result=c7.observe(r,independent:r,frame:photo(root.appendingPathComponent(f.image)),calibration:f.calibration,expected:c7Before,identity:c7.identity,now:f.time,valid:true,allowRefresh:true)
            check(c7.report.recognizedWhite.allSatisfy{seventeen[$0] == .white},"C7 replay invented White")
            if result.readings.enumerated().allSatisfy({$0.element.occupancy==seventeen[$0.offset] && $0.element.confidence>=0.8}) {c7Consecutive+=1;c7Longest=max(c7Longest,c7Consecutive)} else {c7Consecutive=0}
        }
        check(c7Longest>=3,"C7 placement did not produce enough consecutive 17-stone witnesses: \(c7Longest)")
        // The same tolerance must not preserve D7 when actual empty pixels return.
        var d7Gone=raw[0];d7Gone.readings[297] = .init(row:15,col:12,occupancy:.uncertain,confidence:0,delta:0)
        let c7Removed=c7.observe(d7Gone,independent:d7Gone,frame:photos[0],calibration:cases[0].calibration,expected:seventeen,identity:c7.identity,now:c7Cases.last!.time+0.2,valid:true,allowRefresh:false)
        check(c7Removed.signature[297] != .white,"known-White noise band hid actual D7 removal")
        // A temporarily changed patch must be withheld, then recover from the
        // original pixels without a manual recapture or confident raw label.
        var recovering=OccupiedReference()
        check(recovering.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:expected,identity:"recover",now:0),"recovery seed")
        var weakEmpty=raw[0];weakEmpty.readings[297] = .init(row:15,col:12,occupancy:.uncertain,confidence:0,delta:0)
        _=recovering.observe(weakEmpty,independent:weakEmpty,frame:photo(root.appendingPathComponent(placedCases[0].image)),calibration:placedCases[0].calibration,expected:expected,identity:"recover",now:1,valid:true,allowRefresh:false)
        check(recovering.report.quarantined.contains(297),"changed patch not quarantined")
        recovering=try JSONDecoder().decode(OccupiedReference.self,from:JSONEncoder().encode(recovering))
        for j in 1...4 {
            let result=recovering.observe(weakEmpty,independent:weakEmpty,frame:photos[0],calibration:cases[0].calibration,expected:expected,identity:"recover",now:1+Double(j)*0.21,valid:true,allowRefresh:false)
            if j<3 {check(result.signature[297] != .empty,"quarantined patch bypassed fresh revalidation")}
            if j==4 {check(result.signature[297] == .empty,"uncertain raw reading prevented genuine empty patch recovery")}
        }
        // A pending AI stone at another point cannot stop independent refresh.
        var local=OccupiedReference()
        check(local.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:expected,identity:"local",now:0),"local seed")
        var pendingStone=raw[0];pendingStone.readings[316] = .init(row:16,col:12,occupancy:.black,confidence:1,delta:0.4)
        var localUpdated=Set<Int>()
        for j in 1...70 {
            _=local.observe(pendingStone,independent:pendingStone,frame:photos[0],calibration:cases[0].calibration,expected:expected,identity:"local",now:Double(j)*0.2,valid:true,allowRefresh:true)
            localUpdated.formUnion(local.report.refreshed)
        }
        check(!localUpdated.isEmpty && !localUpdated.contains(316),"pending AI placement blocked all local refresh or trained wrong target")
        // Record a newly accepted White body before the periodic refresh. A
        // weak neighboring stone must not prevent independently witnessed color.
        var quickAnchor=OccupiedReference()
        check(quickAnchor.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:expected,identity:"anchor",now:0),"anchor seed")
        var positive=BoardObservation(readings:placedCases[0].readings,size:19)
        positive.readings[297] = .init(row:15,col:12,occupancy:.white,confidence:1,delta:0.2)
        positive.readings[317] = .init(row:16,col:13,occupancy:.uncertain,confidence:0,delta:0)
        var anchored=false
        for j in 1...5 {
            _=quickAnchor.observe(positive,independent:positive,frame:photo(root.appendingPathComponent(placedCases[0].image)),calibration:placedCases[0].calibration,expected:j==1 ? expected:after,identity:"anchor",now:Double(j)*0.21,valid:true,allowRefresh:true)
            anchored = anchored || quickAnchor.report.anchored.contains(297)
        }
        check(anchored && quickAnchor.generation==1,"new White waited for periodic refresh or used unconfirmed pixels")
        // Once the refresh deadline passes with no eligible patches, later
        // independent evidence still needs to accumulate across several frames.
        var overdue=OccupiedReference()
        check(overdue.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:expected,identity:"overdue",now:0),"overdue seed")
        let allWeak=BoardObservation(readings:expected.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:.uncertain,confidence:0,delta:0)},size:19)
        var learnedLate=false
        for j in 1...75 {
            var r=allWeak
            if j>55 {r.readings[288] = .init(row:15,col:3,occupancy:.white,confidence:1,delta:0)}
            _=overdue.observe(r,independent:r,frame:photos[0],calibration:cases[0].calibration,expected:expected,identity:"overdue",now:Double(j)*0.2,valid:true,allowRefresh:true)
            learnedLate = learnedLate || overdue.report.refreshed.contains(288)
        }
        check(learnedLate,"overdue refresh repeatedly discarded unfinished independent evidence")
        // Actual D10: former empty templates are recovered only as quarantined
        // evidence, and current grid/wood proof resolves lighting-changed empties.
        let d10Cases=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:root.appendingPathComponent("d10-cases.json")))
        var d10=try JSONDecoder().decode(OccupiedReference.self,from:Data(contentsOf:root.appendingPathComponent("d10-quarantined-reference.json")))
        let beforeD10=d10.position;var afterD10=beforeD10;afterD10[294] = .white
        var d10Run=0,d10Longest=0,gridRecovered=false
        for f in d10Cases {
            var r=BoardObservation(readings:f.readings,size:19);r.footprints=f.footprints ?? []
            let result=d10.observe(r,independent:r,frame:photo(root.appendingPathComponent(f.image)),calibration:f.calibration,expected:beforeD10,identity:d10.identity,now:f.time,valid:true,allowRefresh:true)
            gridRecovered = gridRecovered || d10.report.recognizedEmpty.contains(41)
            check(result.signature[294] == .white,"D10 erased during reference recovery")
            if result.readings.enumerated().allSatisfy({$0.element.occupancy==afterD10[$0.offset] && $0.element.confidence>=0.8}) {d10Run+=1;d10Longest=max(d10Longest,d10Run)} else {d10Run=0}
        }
        check(d10Longest>=3 && gridRecovered,"D10 full-board recovery lacked sustained positive grid evidence")
        // A primary high-confidence White must retain its genuine empty origin
        // before commit, so subsequent weaker frames can independently confirm it.
        var strongReference=reference
        let firstPlaced=placedCases[0],placedPixels=photo(root.appendingPathComponent(firstPlaced.image))
        var strongRaw=BoardObservation(readings:firstPlaced.readings,size:19)
        strongRaw.readings[297] = .init(row:15,col:12,occupancy:.white,confidence:1,delta:0)
        _=strongReference.observe(strongRaw,independent:strongRaw,frame:placedPixels,calibration:firstPlaced.calibration,expected:expected,identity:"camera/game",now:firstPlaced.time,valid:true,allowRefresh:true)
        check(strongReference.report.retainedOrigins.contains(297),"primary White lost empty before-image")
        var recoveredStrong=0
        for f in placedCases.dropFirst() {
            let r=BoardObservation(readings:f.readings,size:19)
            let result=strongReference.observe(r,independent:r,frame:photo(root.appendingPathComponent(f.image)),calibration:f.calibration,expected:after,identity:"camera/game",now:f.time,valid:true,allowRefresh:true)
            if result.signature[297] == .white {recoveredStrong+=1}
        }
        check(recoveredStrong>=3,"primary White could not be reverified after commit")
        // Archive restore retains labeled features, but needs new observations.
        reference=try JSONDecoder().decode(OccupiedReference.self,from:JSONEncoder().encode(reference))
        time+=0.2;_ = feed(7);check(reference.report.resolved.isEmpty,"archive trusted without revalidation")
        for _ in 0..<5 {time+=0.2;_=feed(7)}
        check(reference.report.resolved.contains(317),"confirmed White317 was not recovered")
        time+=0.2;_=feed(7,valid:false);check(reference.report.resolved.isEmpty,"hand/frozen/laser frame used reference")
        for _ in 0..<2 {time+=0.2;_=feed(7);check(reference.report.resolved.isEmpty,"interruption bypassed revalidation")}
        time+=0.21;_=feed(7);check(!reference.report.resolved.isEmpty,"clear frames failed to revalidate")
        let duplicate=feed(7);check(reference.report.resolved.isEmpty,"duplicate frame counted")
        check(duplicate.signature==raw[7].signature,"duplicate supplied adapted result")
        time+=0.2;_=feed(7,identity:"other camera");check(reference.report.resolved.isEmpty,"identity leak")
        // Policy timing uses repeated photographed inputs with synthetic fresh
        // timestamps; only the first sequence above is a real captured sequence.
        capture();var refreshed=Set<Int>()
        for _ in 0..<65 {time+=0.2;_=feed(7);refreshed.formUnion(reference.report.refreshed)}
        check(reference.generation>=2,"periodic refresh did not run")
        check(!refreshed.isEmpty,"no independent patches refreshed")
        for p in refreshed {
            let freshObject=reference.report.whiteEvidence.contains{$0.point==p && $0.score>=0.92}
            let occupied=Set(expected.indices.filter{expected[$0].stone != nil})
            let grid=BoardAppearanceDetector.gridEvidence(frame:photos[7],calibration:cases[7].calibration,col:Double(p%19),row:Double(p/19),relativeContrast:true)
            let freshEmpty=expected[p] == .empty && grid.horizontal>=0.75 && grid.vertical>=0.75 &&
                BoardAppearanceDetector.emptyConfidence(frame:photos[7],calibration:cases[7].calibration,point:p,threshold:0.13,occupied:occupied) != nil
            check((raw[7].readings[p].confidence>=0.9 && raw[7].signature[p]==expected[p]) || freshObject || freshEmpty,"reference learned without independent evidence")
        }
        var onlyWhite=expected
        for p in onlyWhite.indices where onlyWhite[p] == .white && p != 288 {onlyWhite[p] = .uncertain}
        var supportOnly=OccupiedReference()
        check(supportOnly.captureConfirmed(frame:photos[0],calibration:cases[0].calibration,position:onlyWhite,identity:"support",now:0),"support-only capture")
        var supportRaw=raw[7];supportRaw.readings[288] = .init(row:15,col:3,occupancy:.uncertain,confidence:0,delta:0)
        var supportRefreshed=Set<Int>(),wasSupported=false
        for j in 1...70 {
            _=supportOnly.observe(supportRaw,independent:supportRaw,frame:photos[7],calibration:cases[7].calibration,expected:onlyWhite,identity:"support",now:Double(j)*0.2,valid:true,allowRefresh:true)
            wasSupported = wasSupported || supportOnly.report.resolved.contains(288)
            supportRefreshed.formUnion(supportOnly.report.refreshed)
        }
        check(wasSupported && !supportRefreshed.contains(288),"unchanged reference support trained itself")
        let generation=reference.generation
        for _ in 0..<70 {time+=0.2;_=feed(7,refresh:false)}
        check(reference.generation==generation,"refresh toggle ignored")
        var wrong=raw[7];wrong.readings[297] = .init(row:15,col:12,occupancy:.white,confidence:1,delta:0.2)
        time+=0.2;_=feed(7,independent:wrong)
        check(!reference.report.resolved.contains(297),"strong new stone was overwritten")
        var removed=raw[7];removed.readings[317] = .init(row:16,col:13,occupancy:.empty,confidence:1,delta:0)
        time+=0.2;_=feed(7,independent:removed)
        check(!reference.report.resolved.contains(317),"strong removal overwritten")
        capture()
        let shifted=BoardCalibration(size:19,corners:cases[0].calibration.corners.map{.init(x:$0.x+0.005,y:$0.y)})!
        time+=0.2
        _=reference.observe(raw[0],independent:raw[0],frame:photos[0],calibration:shifted,expected:expected,identity:"camera/game",now:time,valid:true,allowRefresh:true)
        check(!reference.hasReference,"moved grid kept position reference")
        capture();expected[297] = .white
        for _ in 0..<5 {time+=0.2;_=feed(7)}
        check(!reference.report.resolved.contains(297),"move reused changed point label")
        check(reference.report.resolved.contains(317),"unchanged neighboring White lost its revalidated anchor")
        expected[297] = .empty;capture()
        let d7=photo(URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIWhiteD7Glare/placed-1.png"))
        var weakD7=raw[7];weakD7.readings[297] = .init(row:15,col:12,occupancy:.uncertain,confidence:0,delta:0)
        for _ in 0..<8 {
            time+=0.2
            let result=reference.observe(weakD7,independent:weakD7,frame:d7,calibration:cases[0].calibration,expected:expected,identity:"camera/game",now:time,valid:true,allowRefresh:true)
            check(result.signature[297] == .uncertain,"actual D7 White erased")
        }
        // A changed physical object must invalidate matching even if the raw
        // classifier remains uncertain: real added/removed White in glare.
        struct Glare:Decodable {let image:String,calibration:BoardCalibration,referenceCalibration:BoardCalibration;let threshold:Double;let expectedWhite:Bool}
        let glareRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/KnownPositionGlare")
        let g=try JSONDecoder().decode([Glare].self,from:Data(contentsOf:glareRoot.appendingPathComponent("cases.json")))
        let images=g.map{photo(glareRoot.appendingPathComponent($0.image))}
        let emptyPhoto=photo(glareRoot.appendingPathComponent("reference.png"))
        let readings=zip(g,images).map{BoardDetector.detect(frame:$1,reference:emptyPhoto,calibration:$0.calibration,threshold:$0.threshold,referenceCalibration:$0.referenceCalibration)!}
        for (start,end) in [(2,1),(1,2)] {
            var labels=readings[start].signature;labels[185]=start==1 ? .white:.empty
            // This photo set's accepted board has exactly these known stones.
            labels=Array(repeating:.empty,count:361);labels[60] = .black;labels[180] = .black;labels[300] = .white;labels[185]=start==1 ? .white:.empty
            var ref=OccupiedReference();check(ref.captureConfirmed(frame:images[start],calibration:g[start].calibration,position:labels,identity:"glare",now:0),"glare seed")
            var unclear=readings[end];unclear.readings[185] = .init(row:9,col:14,occupancy:.uncertain,confidence:0,delta:0)
            for j in 1...12 {
                let result=ref.observe(unclear,independent:unclear,frame:images[end],calibration:g[end].calibration,expected:labels,identity:"glare",now:Double(j)*0.21,valid:true,allowRefresh:true)
                check(result.signature[185] == .uncertain,"real placement/removal erased by reference")
            }
        }
        print("PASS: \(checks) occupied-reference checks; \(fullMatches) fully verified real frames, periodic independent refresh, archive, interruptions, placement and removal")
    }
}
