import SwiftUI

struct BoardRestorationReviewView: View {
    @ObservedObject var recorder: GameRecorder
    let plan: BoardRestorationPlan
    let orientation: BoardOrientation
    let onClose: () -> Void
    let onSaved: () -> Void
    let onActualMoves: () -> Void
    var onCheckPhoto:(()->Void)?=nil
    @State private var error: String?

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
                Text(ready ? "Recorded position restored" : "Restore the recorded position").font(.title2.bold())
                Spacer()
                Label("Clocks paused", systemImage: "pause.circle").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where the stones belong").font(.headline)
                    RecordedBoard(recorder: recorder, orientation: orientation, allowsLiveSelection: false,
                        boardOverride: DeferredMoveHistory.board(plan.target, size: recorder.game.boardSize),
                        highlightedPoints: plan.remaining(in: recorder.reviewCameraPosition).sorted(),
                        highlightColor: .orange, showsLastMoveMarker: false, onPoint: { _ in })
                        .frame(width: 520, height: 520)
                    Text("The board above shows the saved position.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if case let .displaced(from, to, color) = plan.kind {
                        Text("A \(color.rawValue) stone may have been bumped").font(.title3.bold())
                        Text("If it moved accidentally, return the stone from \(coordinate(to)) to \(coordinate(from)). Leave the other stones in place.")
                    } else {
                        Text("Recorded stones are missing").font(.title3.bold())
                        Text("If they were removed accidentally, put the stones back at \(plan.changed.sorted().map(coordinate).joined(separator: ", ")), matching the board shown here.")
                    }
                    Text(ready ? "Fresh camera views match the saved position. Confirm to clear this review."
                         : verification.guidance(coordinate: coordinate))
                    Text("Restoration adds no moves and leaves clock times unchanged.").font(.callout).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("These were played moves or captures…", action: onActualMoves).padding(.top, 12)
                }.frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if let onCheckPhoto {Button("Check camera photo…",action:onCheckPhoto).disabled(verification == .waitingForCamera)}
            Divider()
            HStack {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm restored position") {
                    error = recorder.confirmBoardRestoration(plan.id)
                    if error == nil { onSaved() }
                }.buttonStyle(.borderedProminent).disabled(!ready)
            }
        }.padding(20).frame(minWidth: 882, minHeight: 670)
    }
}
