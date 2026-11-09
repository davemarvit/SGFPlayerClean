import Foundation

/// A reviewed edit of accepted history. Replay uses the same rules engine as play;
/// the original recording and its evidence remain available after saving a copy.
@MainActor struct HistoricalMoveCorrection {
    let sourceURL:URL
    let sourceSignature:String
    let sourceReviews:Data
    let number:Int
    let destination:BoardPosition
    let keepsLaterMoves:Bool
    let text:String
    let game:SGFGame
    let positions:[BoardSnapshot]
    let reviews:DeferredMoveHistory
    var discardedMoves:Int
    static func fingerprint(_ history:DeferredMoveHistory)throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return try encoder.encode(history)
    }
    static func unavailableReason(_ recorder:GameRecorder)->String? {
        if recorder.clock.saveError != nil {return "Repair or reload the clock record before correcting a move."}
        if recorder.recoveryReadBlocked {return "Reload the recording before correcting a move."}
        if recorder.autosaveURL == nil || recorder.moveCount==0 {return "There is no saved move to correct."}
        if recorder.automaticCaptureStatus != nil {return "Finish or review the current capture first."}
        if recorder.pendingMoveCount>0 && !recorder.hasDeferredMoves {return "Review pending moves before correcting saved history."}
        return nil
    }
    init(recorder:GameRecorder,number:Int,destination:BoardPosition,keepsLaterMoves:Bool=true,reviewEdit:ReviewObservationEdit?=nil)throws {
        func fail(_ message:String)->RecordingStore.Failure {.init(message:message)}
        if let reason=Self.unavailableReason(recorder) {throw fail(reason)}
        guard (1...recorder.moveCount).contains(number),
              (0..<recorder.game.boardSize).contains(destination.row),(0..<recorder.game.boardSize).contains(destination.col) else {throw fail("Choose a saved move and an intersection on the board.")}
        let old=recorder.game.moves[number-1]
        guard old.1?.0 != destination.col || old.1?.1 != destination.row else {throw fail("Choose the intersection where this move was actually played.")}
        sourceURL=recorder.autosaveURL!;sourceSignature=RecordingIdentity.signature(for:recorder.game)
        sourceReviews=try Self.fingerprint(recorder.reviewHistory)
        self.number=number;self.destination=destination;self.keepsLaterMoves=keepsLaterMoves
        let tree=try SGFParser.parse(text:recorder.sgf())
        var nodes=tree.mainLineNodes
        nodes[0].props.removeValue(forKey:"RE") // A changed position invalidates an earlier score/result.
        let indexes=nodes.indices.filter{nodes[$0].props["B"] != nil || nodes[$0].props["W"] != nil}
        let index=indexes[number-1],tag=old.0 == .black ? "B":"W"
        let previous=nodes[index].props[tag]?.first ?? ""
        nodes[index].props[tag]=[SGFCoordinates.toSGF(x:destination.col,y:destination.row)]
        nodes[index].props["C",default:[]].append("Move corrected from SGF \(previous.isEmpty ? "pass":previous) to \(nodes[index].props[tag]![0]). Original recording: \(sourceURL.lastPathComponent)")
        if !keepsLaterMoves {nodes=Array(nodes.prefix(index+1))}
        nodes[0].props["C",default:[]].append("Historical move \(number) corrected. Original recording preserved: \(sourceURL.lastPathComponent)")
        text=SGFWriter.serialize(SGFTree(branches:[.init(sequence:nodes)]))
        game=SGFGame.from(tree:try SGFParser.parse(text:text))
        var initial=game;initial.moves=[];initial.sourceTree=nil
        let player=SGFPlayer();player.load(game:initial)
        var boards=[player.board]
        for (i,move) in game.moves.enumerated() {
            if let reason=player.tryPlayMove(color:move.0,x:move.1?.0 ?? -1,y:move.1?.1 ?? -1) {
                if i+1==number {throw fail("Move \(number) cannot be placed here: \(reason.rawValue). Choose another intersection.")}
                throw fail("Move \(i+1) would be illegal: \(reason.rawValue). Choose another intersection, or turn off Keep later moves to set the later sequence aside in the original recording.")
            }
            boards.append(player.board)
        }
        positions=boards;discardedMoves=recorder.moveCount-game.moves.count
        var history=recorder.reviewHistory
        if let reviewEdit {
            // Validate the original preview before rebuilding a changed destination.
            _=try reviewEdit.applying(to:history)
            let revised=try ReviewObservationEdit(recorder:recorder,reviewID:reviewEdit.reviewID,from:reviewEdit.from,to:destination)
            history=try revised.applying(to:history)
        }
        // Committed reviews are an audit trail of the original observations.
        // Pending sections must be reconsidered against the corrected baseline.
        let retainedMoveCount=game.moves.count
        if discardedMoves>0 {history.sections.removeAll{$0.committed && ($0.savedStart ?? 0)+($0.moves?.count ?? 0)>retainedMoveCount}}
        var before=DeferredMoveHistory.states(boards.last!)
        for i in history.sections.indices where !history.sections[i].committed {
            history.sections[i].before=before
            history.requireReview(at:i,reason:"Saved move \(number) was corrected. Check this observed board change against the corrected history.")
            history.sections[i].liveNext=nil
            before=history.sections[i].after
        }
        history.interrupt();history.turnOverride=nil;history.scoredPosition=nil
        history.anchorSignature=history.active ? RecordingIdentity.signature(for:game):nil
        history.baseMove=history.active ? game.moves.count:nil
        guard history.validate(size:game.boardSize,signature:RecordingIdentity.signature(for:game)) else {throw fail("The pending reviews could not be preserved. The recording has not changed.")}
        reviews=history
    }
}
