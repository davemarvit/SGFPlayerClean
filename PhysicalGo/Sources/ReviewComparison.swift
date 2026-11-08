import Foundation

/// Compare the selected legal result with the frozen evidence, never the moving live feed.
enum ReviewComparison {
    struct Difference:Identifiable {
        let point:Int
        let selected:Occupancy
        let camera:Occupancy
        var id:Int {point}
        func coordinate(size:Int,orientation:BoardOrientation)->String {
            let last=Double(size-1)
            let p=orientation.display(.init(x:Double(point%size)/last,y:Double(point/size)/last))
            return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x*last).rounded())])\(size-Int((p.y*last).rounded()))"
        }
        var explanation:String {"Your sequence: \(selected.rawValue). Saved camera: \(camera.rawValue)."}
    }
    static func differences(selected:BoardSnapshot,camera:[Occupancy])->[Difference] {
        let states=DeferredMoveHistory.states(selected)
        guard states.count==camera.count else {return []}
        return states.indices.compactMap {states[$0]==camera[$0] ? nil:Difference(point:$0,selected:states[$0],camera:camera[$0])}
    }
}
