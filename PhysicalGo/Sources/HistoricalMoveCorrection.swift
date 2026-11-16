import Foundation

/// A reviewed edit of accepted history. Replay uses the same rules engine as play;
/// the original recording and its evidence remain available after saving a copy.
@MainActor struct HistoricalMoveCorrection {
    struct Edit:Equatable {let number:Int;let destination:BoardPosition?}
    let edits:[Edit]
    let sourceURL:URL
    let sourceSignature:String
    let sourceReviews:Data
    let number:Int
    let destination:BoardPosition?
    var removesFalseDetection:Bool {edits.count==1 && destination==nil}
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
    static func moveNumber(at point:BoardPosition,through number:Int,game:SGFGame,positions:[BoardSnapshot])->Int? {
        guard (0..<game.boardSize).contains(point.row),(0..<game.boardSize).contains(point.col),
              (0..<positions.count).contains(number),number<=game.moves.count,
              let color=positions[number].grid[point.row][point.col] else {return nil}
        return game.moves.indices.prefix(number).reversed().first { i in
            let move=game.moves[i]
            return move.0==color && move.1?.0==point.col && move.1?.1==point.row
        }.map{$0+1}
    }
    init(recorder:GameRecorder,number:Int,destination:BoardPosition,keepsLaterMoves:Bool=true,reviewEdit:ReviewObservationEdit?=nil)throws {
        try self.init(recorder:recorder,edits:[.init(number:number,destination:destination)],keepsLaterMoves:keepsLaterMoves,reviewEdit:reviewEdit)
    }
    init(recorder:GameRecorder,edits:[Edit],keepsLaterMoves:Bool=true,reviewEdit:ReviewObservationEdit?=nil)throws {
        func fail(_ message:String)->RecordingStore.Failure {.init(message:message)}
        if let reason=Self.unavailableReason(recorder) {throw fail(reason)}
        let edits=edits.sorted{$0.number<$1.number}
        guard !edits.isEmpty,Set(edits.map(\.number)).count==edits.count else {throw fail("Choose each move's corrected location once.")}
        guard keepsLaterMoves || edits.count==1 else {throw fail("Keep later moves while correcting several moves together.")}
        for edit in edits {
            guard (1...recorder.moveCount).contains(edit.number) else {throw fail("Choose a saved move.")}
            let old=recorder.game.moves[edit.number-1]
            guard let destination=edit.destination else {
                guard edits.count==1,edit.number==recorder.moveCount,old.1 != nil,reviewEdit==nil else {
                    throw fail("Remove a false detection only for the latest saved placement, as a separate correction. Earlier moves may affect later turns and captures.")
                }
                continue
            }
            guard (0..<recorder.game.boardSize).contains(destination.row),(0..<recorder.game.boardSize).contains(destination.col) else {throw fail("Choose an intersection on the board.")}
            guard old.1?.0 != destination.col || old.1?.1 != destination.row else {throw fail("Choose a different intersection for move \(edit.number).")}
        }
        self.edits=edits
        let number=edits[0].number,destination=edits[0].destination
        sourceURL=recorder.autosaveURL!;sourceSignature=RecordingIdentity.signature(for:recorder.game)
        sourceReviews=try Self.fingerprint(recorder.reviewHistory)
        self.number=number;self.destination=destination;self.keepsLaterMoves=keepsLaterMoves
        let tree=try SGFParser.parse(text:recorder.sgf())
        var nodes=tree.mainLineNodes
        nodes[0].props.removeValue(forKey:"RE") // A changed position invalidates an earlier score/result.
        let indexes=nodes.indices.filter{nodes[$0].props["B"] != nil || nodes[$0].props["W"] != nil}
        // Apply the whole batch before replay: one correction may make another
        // legal (for example, two moves whose locations were interchanged).
        for edit in edits {
            let index=indexes[edit.number-1],tag=recorder.game.moves[edit.number-1].0 == .black ? "B":"W"
            let previous=nodes[index].props[tag]?.first ?? ""
            guard let destination=edit.destination else {
                // No placement occurred: remove the turn, never replace it with a pass.
                nodes=Array(nodes.prefix(index))
                nodes[0].props["C",default:[]].append("False detection removed: move \(edit.number), SGF \(previous). Original recording: \(sourceURL.lastPathComponent)")
                continue
            }
            nodes[index].props[tag]=[SGFCoordinates.toSGF(x:destination.col,y:destination.row)]
            nodes[index].props["C",default:[]].append("Move corrected from SGF \(previous.isEmpty ? "pass":previous) to \(nodes[index].props[tag]![0]). Original recording: \(sourceURL.lastPathComponent)")
        }
        if !keepsLaterMoves {nodes=Array(nodes.prefix(indexes[number-1]+1))}
        nodes[0].props["C",default:[]].append("Historical moves \(edits.map{String($0.number)}.joined(separator:", ")) corrected. Original recording preserved: \(sourceURL.lastPathComponent)")
        text=SGFWriter.serialize(SGFTree(branches:[.init(sequence:nodes)]))
        game=SGFGame.from(tree:try SGFParser.parse(text:text))
        var initial=game;initial.moves=[];initial.sourceTree=nil
        let player=SGFPlayer();player.load(game:initial)
        var boards=[player.board]
        for (i,move) in game.moves.enumerated() {
            if let reason=player.tryPlayMove(color:move.0,x:move.1?.0 ?? -1,y:move.1?.1 ?? -1) {
                throw fail("Move \(i+1) would be illegal: \(reason.rawValue). Your edits are kept in this preview. Correct that move or another affected move before saving.")
            }
            boards.append(player.board)
        }
        positions=boards;discardedMoves=recorder.moveCount-game.moves.count
        var history=recorder.reviewHistory
        if let reviewEdit,let correction=edits.first(where:{$0.number==reviewEdit.savedMoveNumber}),let destination=correction.destination {
            // Validate the original preview before rebuilding a changed destination.
            _=try reviewEdit.applying(to:history)
            let revised=try ReviewObservationEdit(recorder:recorder,reviewID:reviewEdit.reviewID,from:reviewEdit.from,to:destination)
            history=try revised.applying(to:history)
        }
        // Committed reviews are an audit trail of the original observations.
        // Pending sections must be reconsidered against the corrected baseline.
        let retainedMoveCount=game.moves.count
        if destination==nil {
            for i in history.sections.indices {
                guard history.sections[i].committed,let start=history.sections[i].savedStart,
                      start<number,number<=start+(history.sections[i].moves?.count ?? 0) else {continue}
                history.sections[i].undoneMoveNumbers=Array(Set((history.sections[i].undoneMoveNumbers ?? [])+[number])).sorted()
            }
        } else if discardedMoves>0 {history.sections.removeAll{$0.committed && ($0.savedStart ?? 0)+($0.moves?.count ?? 0)>retainedMoveCount}}
        var before=DeferredMoveHistory.states(boards.last!)
        var knownPrefix=true
        for i in history.sections.indices where !history.sections[i].committed {
            // A physical relocation can already match the corrected history.
            // Resolve only the fully explained prefix; a later snapshot after
            // an unresolved change cannot establish chronology on its own.
            if knownPrefix,history.sections[i].moves==nil,history.sections[i].after==before {
                history.sections[i].moves=[]
                history.sections[i].resolvedAfter=before
                history.sections[i].resolvedAt=Date().timeIntervalSince1970
                history.sections[i].recoverySource="Saved move \(number) corrected; this observed position exactly matches the corrected legal history. No additional move was played."
                history.sections[i].savedStart=game.moves.count
                history.sections[i].committed=true
                history.sections[i].liveNext=nil
                continue
            }
            knownPrefix=false
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
