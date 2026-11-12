import SwiftUI

struct BoardRestorationReviewView: View {
    @ObservedObject var recorder: GameRecorder
    let plan: BoardRestorationPlan
    let orientation: BoardOrientation
    let onClose: () -> Void
    let onSaved: () -> Void
    let onActualMoves: () -> Void
    var onCheckPhoto:(()->Void)?=nil
    var onCorrectMove:((Int,BoardPosition)->Void)?=nil
    @State private var error: String?
    @State private var revision:ReviewRevision?
    private var current:Bool {revision?.matches(recorder)==true}

    private var verification: ReviewBoardVerification.Status { recorder.boardRestorationVerificationStatus(plan) }
    private var ready: Bool { verification == .ready }
    private func coordinate(_ point: Int) -> String {
        let size = recorder.game.boardSize, last = Double(size - 1)
        let p = orientation.display(.init(x: Double(point % size) / last, y: Double(point / size) / last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x * last).rounded())])\(size - Int((p.y * last).rounded()))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(ready ? "Recorded position restored" : "Check stone location").font(.title2.bold())
                Spacer()
                Label(recorder.clock.running ? "Clocks running":"Clocks held", systemImage:recorder.clock.running ? "clock":"pause.circle").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved interpretation — drag a stone to correct it").font(.headline)
                    RecordedBoard(recorder: recorder, orientation: orientation, allowsLiveSelection: false,
                        boardOverride: DeferredMoveHistory.board(plan.target, size: recorder.game.boardSize),
                        highlightedPoints: plan.remaining(in: recorder.reviewCameraPosition).sorted(),
                        highlightColor: .orange, showsLastMoveMarker: false, onDrag:{from,to in
                            guard from != to,let number=HistoricalMoveCorrection.moveNumber(at:from,through:recorder.moveCount,game:recorder.game,positions:recorder.positions) else {return}
                            onCorrectMove?(number,to)
                        }, onPoint: { _ in })
                        .frame(width: 520, height: 520)
                    Text("The board above shows the saved position.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if case let .displaced(from, to, color) = plan.kind {
                        Text("\(color.rawValue.capitalized): saved at \(coordinate(from)), observed at \(coordinate(to))").font(.title3.bold())
                        Text("If the saved location is wrong, drag the stone above to its intended intersection. You can correct other moves in the same preview, then confirm them together.")
                        if let number=plan.displacedMoveNumber,number<=recorder.moveCount,let onCorrectMove {
                            Button("Correct move \(number) to \(coordinate(to))…") {onCorrectMove(number,BoardPosition(to/recorder.game.boardSize,to%recorder.game.boardSize))}
                        }
                        Text("Only if the stone was bumped accidentally: return it from \(coordinate(to)) to \(coordinate(from)), then confirm the restored position.")
                    } else {
                        Text("Recorded stones are missing").font(.title3.bold())
                        Text("If they were removed accidentally, put the stones back at \(plan.changed.sorted().map(coordinate).joined(separator: ", ")), matching the board shown here.")
                    }
                    Button("Recorded position is correct") {
                        guard current,let point=plan.changed.first(where:{plan.target[$0].stone != nil}) else {return}
                        error=recorder.acknowledgeRecordedPosition(point:point,position:recorder.issuePositionSignature)
                            ?? "Recorded position confirmed. Clear the view for recognition to check again; no move or clock balance changed."
                    }.disabled(!current || plan.changed.contains(where:{recorder.positionAcknowledgments[$0] != nil}))
                    Button("Pause for physical restoration") {recorder.holdForReviewMutation();revision=ReviewRevision(recorder)}
                        .disabled(recorder.state == .paused || !current)
                    Text(ready ? "Fresh camera views match the saved position. Confirm to clear this review."
                         : verification.guidance(coordinate: coordinate))
                    Text("Restoration adds no moves and leaves clock times unchanged.").font(.callout).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("These were played moves or captures…", action: onActualMoves).padding(.top, 12)
                }.frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if let onCheckPhoto {Button("Check camera photo…",action:onCheckPhoto).disabled(verification == .waitingForCamera)}
            if !current {Text("This review changed or resolved. Close and reopen it for current actions.").foregroundStyle(.orange)}
            Divider()
            HStack {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm restored position") {
                    guard current else {return}
                    error = recorder.confirmBoardRestoration(plan.id)
                    if error == nil { onSaved() }
                }.buttonStyle(.borderedProminent).disabled(!ready || !current)
            }
        }.padding(20).frame(minWidth: 882, minHeight: 670)
            .onAppear {if revision==nil {revision=ReviewRevision(recorder)}}
    }
}
