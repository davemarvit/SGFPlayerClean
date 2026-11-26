// Metadata/provenance contract only. Pixel-support controls run separately.
import Foundation

@main struct EmptyCrossingEvidenceTests {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ message:String) {precondition(condition,message);checks+=1}
        let support=EmptyCrossingSupport(woodMatches:20,woodSamples:24,railMatches:[3,4],railSamples:[4,4],innerMatches:4,innerSamples:4)
        func fixture(point:Int=40)->BoardObservation {
            let reading=IntersectionReading(row:point/9,col:point%9,occupancy:.empty,confidence:0.75,delta:0.003)
            let frame=UUID(),reference=UUID()
            var o=BoardObservation(readings:(0..<81).map {
                $0==point ? reading:.init(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)
            },size:9,capturedAt:100,handObstructed:false,evidenceFrameID:frame,evidenceReferenceID:reference)
            o.emptyCrossingEvidence[point] = .init(frameID:frame,referenceID:reference,capturedAt:100,reading:reading,support:support)
            return o
        }
        for point in [0,4,8,36,40,44,72,76,80] {
            let original=fixture(point:point)
            check(original.hasFreshEmptyCrossingEvidence(at:point),"Complete same-image support must qualify at edges/corners/interior")
            check(original.readings[point].confidence==0.75,"Proof must not relabel scalar confidence")
            for color in [Occupancy.black,.white,.uncertain] {
                var changed=original
                changed.readings[point] = .init(row:point/9,col:point%9,occupancy:color,confidence:1,delta:0)
                check(changed.emptyCrossingEvidence[point]==nil,"Replacement reading must drop its old proof")
                changed.readings[point]=original.readings[point]
                check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Restoring a label must not resurrect old pixel proof")
            }
            var changed=original;changed.capturedAt=100.1
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Reusing an observation at a later timestamp is not fresh proof")
            changed.capturedAt=100
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Restoring time must not resurrect proof")
            changed=original;changed.evidenceFrameID=UUID()
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Same timestamp on another image is not the same evidence")
            changed=original;changed.evidenceReferenceID=UUID()
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"A replaced reference invalidates the receipt")
            changed=original;changed.manualPoints=[point];changed.manualPoints=[]
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Manual override cannot retain or restore visual proof")
            changed=original;changed.trackedAssignments=[point:(point+1)%81];changed.trackedAssignments=[:]
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Tracker reassignment cannot retain or restore visual proof")
            changed=original;changed.handObstructed=true
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Wood proof cannot clear a hand")
            changed=original;changed.handObstructed=nil
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Unknown hand state is not clear")
            changed=original;changed.lightingBlocked=true
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Exposure block remains authoritative")
            changed=original;changed.coveredGridPoints=[point]
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"Disappearing rails contradict empty-crossing proof")
            changed=original;changed.footprints=[.init(row:point/9,col:point%9,
                center:.init(x:Double(point%9),y:Double(point/9)),radiusCol:0.4,radiusRow:0.4,quality:0.95)]
            check(!changed.hasFreshEmptyCrossingEvidence(at:point),"A covering stone outline contradicts empty-crossing proof")
            changed.footprints=[]
            check(changed.hasFreshEmptyCrossingEvidence(at:point),"Same-image geometry refinement may remove a contradictory outline; exact pixels and reading still match")
        }
        for matches in 0..<4 {
            let incomplete=EmptyCrossingSupport(woodMatches:24,woodSamples:24,railMatches:[4,4],railSamples:[4,4],innerMatches:matches,innerSamples:4)
            check(incomplete.isComplete,"Inner probes may straddle ink; independent existing wood and both rail gates decide support")
        }
        check(!EmptyCrossingSupport(woodMatches:24,woodSamples:24,railMatches:[4,2],railSamples:[4,4],innerMatches:4,innerSamples:4).isComplete,"One weak rail axis cannot be rescued by perfect other evidence")
        check(!EmptyCrossingSupport(woodMatches:12,woodSamples:15,railMatches:[2,2],railSamples:[2,2],innerMatches:4,innerSamples:4).isComplete,"Too few actual wood samples cannot establish support")
        let original=fixture(),receipt=original.emptyCrossingEvidence[40]!
        var mismatch=original
        mismatch.emptyCrossingEvidence=[41:receipt]
        check(!mismatch.hasFreshEmptyCrossingEvidence(at:41),"Point identity must match the receipt reading")
        mismatch=original
        mismatch.emptyCrossingEvidence[40] = .init(frameID:UUID(),referenceID:receipt.referenceID,capturedAt:100,reading:receipt.reading,support:support)
        check(!mismatch.hasFreshEmptyCrossingEvidence(at:40),"A foreign image receipt cannot attach to this observation")
        print("PASS: \(checks) empty-crossing evidence provenance checks")
    }
}
