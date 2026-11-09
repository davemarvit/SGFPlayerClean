import Foundation

/// One explicit approval of a frozen position, never a source of live readings.
/// The current legal review must still have the same ID and target at commit.
struct CheckedReviewPhoto {
    let reviewID:UUID
    let target:[Occupancy]
    let position:[Occupancy]
    let capturedAt:Double
    func verifies(id:UUID,target:[Occupancy],requiredClear:Set<Int>,now:Double)->Bool {
        id==reviewID && self.target==target && capturedAt.isFinite && now.isFinite &&
        now>=capturedAt && now-capturedAt<=60 &&
        ReviewBoardVerification.matches(position,target:target,requiredClear:requiredClear)
    }
}
