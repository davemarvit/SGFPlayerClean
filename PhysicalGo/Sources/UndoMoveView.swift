import SwiftUI

struct UndoMoveView: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var recorder: GameRecorder
    @StateObject private var session: UndoMoveSession
    let onClose: () -> Void
    @State private var error: String?
    @State private var saved = false
    @State private var clockReview = false
    private var liveCamera: Bool { model.running && model.cameraState == .live && !model.frozen && !model.alignmentNeedsRecovery }
    private func finishSave() {
        if error == nil { saved = true; clockReview = recorder.clock.requiresReview }
    }
    init(model: ExperimentModel, recorder: GameRecorder, plan: UndoMovePlan, onClose: @escaping () -> Void) {
        self.model = model; self.recorder = recorder; self.onClose = onClose
        _session = StateObject(wrappedValue: UndoMoveSession(plan: plan))
    }
    private func coordinate(_ index: Int) -> String {
        let last = Double(session.plan.size - 1)
        let p = model.orientation.display(.init(x: Double(index % session.plan.size) / last, y: Double(index / session.plan.size) / last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x * last).rounded())])\(session.plan.size - Int((p.y * last).rounded()))"
    }
    var body: some View {
        Group {
            if saved { SavedReviewNotice(recorder: recorder, onClose: onClose) }
            else {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let plan = session.plan
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Undo move \(plan.moveNumber)").font(.title2.bold())
                            Spacer(); Label("Clocks paused", systemImage: "pause.circle")
                        }
                        HStack(alignment: .top, spacing: 22) {
                            RecordedBoard(recorder: recorder, orientation: model.orientation, allowsLiveSelection: false,
                                boardOverride: plan.target, highlightedPoints: plan.remove + plan.restore,
                                highlightColor: .orange, showsLastMoveMarker: false, onPoint: { _ in })
                                .frame(width: 520, height: 520)
                            VStack(alignment: .leading, spacing: 14) {
                                Text(plan.point.map { "Undo \(plan.color.rawValue.capitalized) at \(coordinate($0.row * plan.size + $0.col))" }
                                     ?? "Undo \(plan.color.rawValue.capitalized)’s pass").font(.headline)
                                Text("Restore the physical board to the position shown before confirming.")
                                if !plan.remove.isEmpty { Text("Remove the stone at \(plan.remove.map(coordinate).joined(separator: ", ")).") }
                                if !plan.restore.isEmpty { Text("Put the captured stones back at \(plan.restore.map(coordinate).joined(separator: ", ")), matching the colors shown.") }
                                if plan.point == nil { Text("A pass changes no stones. Keep the board as shown.") }
                                Text(session.applied ? "The move has been undone in memory. Retry saving before continuing."
                                     : session.verified() ? "The camera has verified the restored position. Confirm to undo this move."
                                     : session.verificationStatus().guidance(coordinate: coordinate))
                                Text("The original game is backed up. Known clock history is restored; any uncertain clock times need review. Play stays paused until you resume.")
                                    .font(.callout).foregroundStyle(.secondary)
                                if let error { Text(error).foregroundStyle(.red) }
                            }.frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        HStack {
                            Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                            Spacer()
                            Button(session.applied ? "Retry saving undo" : "Confirm undo") {
                                error = session.applied ? session.retrySave(recorder) : session.confirm(recorder)
                                finishSave()
                            }.buttonStyle(.borderedProminent).disabled(!session.applied && !session.verified())
                        }
                        Text(session.applied ? "The game stays paused until the undo is saved."
                             : "Cancel leaves the game unchanged and paused. If you moved stones, restore the current saved position before resuming.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
        }.frame(minWidth: 882, minHeight: 690)
            .onReceive(model.$lastVerifiedLiveFrameAt) { session.observeLive(model.visibleObservation, frameTime: $0, isLive: liveCamera) }
            .onChange(of: liveCamera) { _, live in if !live { session.invalidate() } }
            .sheet(isPresented: $clockReview, onDismiss: onClose) {
                LocalClockCorrection(clock: recorder.clock, recorder: recorder, resumeAfterReview: true)
            }
    }
}
