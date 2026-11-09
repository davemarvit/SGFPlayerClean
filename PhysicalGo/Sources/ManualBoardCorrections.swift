import Foundation
import Combine

/// Labels belong to the single photograph being reviewed. They never replace
/// later live readings, locally or online.
@MainActor final class ManualBoardCorrections: ObservableObject {
    enum Choice: String, Codable, CaseIterable {
        case empty, black, white, automatic
        var occupancy: Occupancy? { Occupancy(rawValue:rawValue) }
        var label: String { self == .automatic ? "Use photo reading" : rawValue.capitalized }
    }
    @Published private(set) var values: [Int: Occupancy] = [:]
    @Published private(set) var draft: [Int: Occupancy]?
    @Published private(set) var edits: [Int: Choice] = [:]
    @Published private(set) var notice = ""
    private(set) var context: String?
    private(set) var size = 19
    var isEditing: Bool { draft != nil }
    var displayedValues: [Int: Occupancy] { draft ?? values }

    func bind(context: String, size: Int) {
        guard self.context != context || self.size != size else { return }
        clear(reason:"Manual corrections cleared for the new game or board orientation.")
        self.context=context; self.size=size
    }
    func begin(size: Int) {
        guard [9,13,19].contains(size), !isEditing else { return }
        if self.size != size { clear(reason:"Board size changed.") }
        self.size=size; draft=values; edits=[:]; notice=""
    }
    func set(_ choice: Choice, at point: Int) {
        guard isEditing, (0..<size*size).contains(point) else { return }
        draft?[point]=choice.occupancy; edits[point]=choice
    }
    func useCameraEverywhere() {
        guard let draft else { return }
        for point in draft.keys { set(.automatic,at:point) }
    }
    func commit() {
        guard draft != nil else { return }
        values=[:]; self.draft=nil; edits=[:]
        notice="Photo labels saved. Live recognition continues without overrides."
    }
    func cancel() { draft=nil; edits=[:] }
    func clear(reason: String) {
        if !values.isEmpty || isEditing { notice=reason }
        values=[:]; draft=nil; edits=[:]; context=nil
    }
    func apply(to observation: BoardObservation, preview: Bool = false) -> BoardObservation {
        guard preview, isEditing, observation.size==size else { return observation }
        let overrides=displayedValues
        var result=observation
        result=BoardObservation(readings:observation.readings.map { reading in
            guard let state=overrides[reading.row*size+reading.col] else { return reading }
            return IntersectionReading(row:reading.row,col:reading.col,occupancy:state,confidence:1,delta:reading.delta)
        },size:observation.size,notice:observation.notice,lightingBlocked:observation.lightingBlocked,
            lightingAdjusted:observation.lightingAdjusted,lightingField:observation.lightingField,
            footprints:observation.footprints.filter { overrides[$0.row*size+$0.col] == nil },
            placementFits:observation.placementFits.filter { overrides[$0.row*size+$0.col] == nil },
            manualPoints:Set(overrides.keys),trackedAssignments:observation.trackedAssignments.filter{overrides[$0.key]==nil && overrides[$0.value]==nil})
        return result
    }
}
