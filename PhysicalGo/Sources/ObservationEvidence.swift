import Foundation

/// Facts and interpretation are separate. A later hand can revise a particular
/// sighting, never the original camera output or every sighting of that point.
struct ObservationEvidence {
    struct Observation {
        let id:String
        let capturedAt:Double
        let processedAt:Double
        let raw:BoardObservation
    }
    struct Revision {
        let observationID:String
        let points:Set<Int>
        let reason:String
        let revisedAt:Double
    }
    static let maximumObservations=256
    static let lifetime=12.0
    private let epoch=UUID().uuidString
    private var sequence=0
    private(set) var observations=[Observation]()
    private(set) var revisions=[Revision]()
    mutating func append(_ raw:BoardObservation,processedAt:Double)->String {
        sequence+=1
        let stamp=raw.capturedAt ?? processedAt,id="\(epoch):\(sequence)"
        observations.append(.init(id:id,capturedAt:stamp,processedAt:processedAt,raw:raw))
        observations.removeAll{processedAt-$0.processedAt>Self.lifetime}
        if observations.count>Self.maximumObservations {observations.removeFirst(observations.count-Self.maximumObservations)}
        let retained=Set(observations.map(\.id));revisions.removeAll{!retained.contains($0.observationID)}
        return id
    }
    @discardableResult mutating func discount(capturedAt:Double,points:Set<Int>,reason:String,now:Double)->String? {
        guard !points.isEmpty,let observation=observations.last(where:{$0.capturedAt==capturedAt}) else {return nil}
        let previous=revisions.filter{$0.observationID==observation.id}.reduce(into:Set<Int>()){$0.formUnion($1.points)}
        let added=points.subtracting(previous)
        if !added.isEmpty {revisions.append(.init(observationID:observation.id,points:added,reason:reason,revisedAt:now))}
        return observation.id
    }
    func interpreted(_ observation:Observation)->BoardObservation {
        let points=revisions.filter{$0.observationID==observation.id}.reduce(into:Set<Int>()){$0.formUnion($1.points)}
        return observation.raw.discountingDarkReadings(points)
    }
}
