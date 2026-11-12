import Foundation

/// A proposal may be inspected during play. Its source must still match before
/// an explicit mutation can take a hold. Observation counters are not revisions.
@MainActor struct ReviewRevision:Equatable {
    let url:URL?
    let game:String
    let history:Data?
    let placements:[String]
    init(_ recorder:GameRecorder) {
        url=recorder.autosaveURL;game=RecordingIdentity.signature(for:recorder.game)
        history=try? HistoricalMoveCorrection.fingerprint(recorder.reviewHistory)
        placements=Self.placements(recorder.tentativeHistory.checkpoint)
    }
    static func placements(_ checkpoint:MoveObservationHistory.Checkpoint)->[String] {
        checkpoint.paths.map {path in
            let choices=(path.locationChoices ?? [:]).keys.sorted().map {"\($0):\(path.locationChoices![$0]!.sorted())"}.joined(separator:";")
            return "\(path.moves):\(choices):\((path.playerConfirmed ?? []).sorted())"
        }.sorted()
    }
    func matches(_ recorder:GameRecorder)->Bool {self==Self(recorder)}
}
