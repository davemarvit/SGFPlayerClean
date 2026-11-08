import Foundation

/// Detection overlays never modify the retained or saved game. A camera-only
/// stone remains visibly distinct until the recorder can place it in history.
enum InterpretationDetectionMarks {
    enum Kind:Equatable {case uncertain,untracked,disagreement}
    struct Mark {let point:Int;let kind:Kind;let occupancy:Occupancy}
    static func make(board:BoardSnapshot?,observation:BoardObservation?,size:Int)->[Mark] {
        guard let board,board.size==size,let observation,observation.size==size,
              observation.readings.count==size*size else {return []}
        return observation.readings.enumerated().compactMap {point,reading in
            let known=board.grid[point/size][point%size]
            if let known {
                if reading.occupancy.stone != known {return Mark(point:point,kind:.disagreement,occupancy:reading.occupancy)}
            } else if reading.occupancy.stone != nil {
                return Mark(point:point,kind:.untracked,occupancy:reading.occupancy)
            } else if reading.occupancy == .uncertain {
                return Mark(point:point,kind:.uncertain,occupancy:.uncertain)
            }
            return nil
        }
    }
}
