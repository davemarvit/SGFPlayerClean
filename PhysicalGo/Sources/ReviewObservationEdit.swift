import Foundation

/// A user correction to one saved camera interpretation, never a live override.
@MainActor struct ReviewObservationEdit:Identifiable {
    let id=UUID()
    let reviewID:UUID
    let recordingURL:URL?
    let signature:String
    let historyFingerprint:Data
    let from:BoardPosition,to:BoardPosition
    let original:[Occupancy]
    let corrected:[Occupancy]
    let savedMoveNumber:Int?
    init(recorder:GameRecorder,reviewID:UUID,from:BoardPosition,to:BoardPosition)throws {
        guard !recorder.recoveryReadBlocked,let section=recorder.reviewHistory.sections.first(where:{$0.id==reviewID}),!section.committed else {
            throw RecordingStore.Failure(message:"Choose an unresolved review before correcting its detected stones.")
        }
        let size=recorder.game.boardSize
        guard [from,to].allSatisfy({(0..<size).contains($0.row) && (0..<size).contains($0.col)}),from != to else {
            throw RecordingStore.Failure(message:"Drag a detected stone to a different intersection.")
        }
        let source=from.row*size+from.col,target=to.row*size+to.col
        guard let color=section.after[source].stone,section.after[target] == .empty else {
            throw RecordingStore.Failure(message:"Drag a detected stone to an empty intersection. No stones have changed.")
        }
        self.reviewID=reviewID;self.from=from;self.to=to
        recordingURL=recorder.autosaveURL;signature=RecordingIdentity.signature(for:recorder.game)
        historyFingerprint=try HistoricalMoveCorrection.fingerprint(recorder.reviewHistory)
        original=section.after
        var values=original;values[source] = .empty;values[target] = color == .black ? .black:.white
        corrected=values
        // An already corrected history can disagree with this older snapshot.
        // Only redirect to history editing when the source stone is still saved
        // there and belongs to the accepted prefix preceding this review.
        let base=min(recorder.reviewHistory.baseMove ?? recorder.moveCount,recorder.moveCount)
        if section.before[source].stone==color,recorder.positions[base].grid[from.row][from.col]==color {
            savedMoveNumber=(0..<base).reversed().first(where:{index in
                let move=recorder.game.moves[index]
                return move.0==color && move.1?.0==from.col && move.1?.1==from.row
            }).map{$0+1}
        } else {savedMoveNumber=nil}
    }
    func applying(to source:DeferredMoveHistory)throws->DeferredMoveHistory {
        guard try HistoricalMoveCorrection.fingerprint(source)==historyFingerprint,
              let index=source.sections.firstIndex(where:{$0.id==reviewID}),!source.sections[index].committed else {
            throw RecordingStore.Failure(message:"This review changed. Close the preview and check it again.")
        }
        var result=source
        if result.sections[index].originalCameraAfter==nil {result.sections[index].originalCameraAfter=original}
        result.sections[index].after=corrected
        for i in index..<result.sections.count where !result.sections[i].committed {
            if i>index {result.sections[i].before=result.sections[i-1].after}
            result.requireReview(at:i,reason:"Detected stone position corrected by a player. Check the actual moves against this interpretation.")
            result.sections[i].liveNext=nil;result.sections[i].suggestedOrders=nil
        }
        result.turnOverride=nil;result.scoredPosition=nil;result.interrupt()
        return result
    }
}
