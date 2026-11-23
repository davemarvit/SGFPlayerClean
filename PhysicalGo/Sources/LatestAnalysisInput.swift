import Foundation

/// One replaceable live input, never a backlog. Context changes and age checks
/// prevent a delayed analysis from reviving a stale camera view.
struct LatestAnalysisInput<Value> {
    private struct Item {let value:Value;let capturedAt:Double;let revision:Int}
    private var pending:Item?
    mutating func offer(_ value:Value,capturedAt:Double,revision:Int) {
        guard capturedAt.isFinite else {return}
        if let pending,pending.revision==revision,pending.capturedAt>=capturedAt {return}
        pending=Item(value:value,capturedAt:capturedAt,revision:revision)
    }
    mutating func take(now:Double,revision:Int)->Value? {
        defer {pending=nil}
        guard let pending,pending.revision==revision,now.isFinite,
              now>=pending.capturedAt,now-pending.capturedAt<=0.2 else {return nil}
        return pending.value
    }
}
