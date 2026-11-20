import SwiftUI

struct PlaySessionControls:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    var sidebar=false
    @State private var confirmEnd=false
    @State private var endNeedsAttention=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            let layout=sidebar ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)):AnyLayout(HStackLayout(spacing:16))
            layout {
                if model.playMode == .local {
                    let actions=AnyLayout(HStackLayout(spacing:sidebar ? 8:16))
                    actions {
                    Button(recorder.hasDeferredMoves && recorder.tentativeNextPlayer == nil ? "Pass" : "\((recorder.tentativeNextPlayer ?? recorder.nextPlayer).rawValue.capitalized) pass") {recorder.pass()}.disabled(!recorder.canPass)
                    PhysicalScoreButton(scoring:model.scoring,recorder:recorder,orientation:model.orientation)
                    }
                    HStack(spacing:8) {
                    Button("End game…") {confirmEnd=true}.disabled(!recorder.hasGame || recorder.state == .finished)
                    if recorder.state == .finished && recorder.hasUnfinishedReviews {
                        Button("Review unfinished moves") {recorder.reopenUnfinishedReview()}
                            .help("Open the retained moves for review. The clocks stay stopped.")
                    }
                    Button("Rotate view",systemImage:"rotate.right") {model.rotateView()}
                        .help("Rotate the board and camera view 90° clockwise. The recorded game and clocks are preserved.")
                    }
                }
                if !sidebar {Spacer()}
                HStack {
                if model.exportingSGF {ProgressView().controlSize(.small)}
                Button("Save SGF file",systemImage:"square.and.arrow.up") {Task {await model.saveSGFFile()}}
                    .actionAttention(model.playMode == .local && recorder.saveError != nil ? .required:.none)
                    .disabled(model.exportingSGF || (model.playMode == .local && (!recorder.hasGame || recorder.hasUnfinishedReviews)))
                if sidebar {
                    Button("Check board photo…") {model.beginBoardCorrection()}
                        .disabled(model.observation == nil || model.calibration == nil || model.alignmentNeedsRecovery)
                }
                }
            }
            if model.playMode == .online && !model.exportStatus.isEmpty {Text(model.exportStatus).font(.callout).textSelection(.enabled)}
        }.confirmationDialog("End this game?",isPresented:$confirmEnd,titleVisibility:.visible) {
            Button("End game") {recorder.finish();endNeedsAttention=recorder.state != .finished}
            Button("Cancel",role:.cancel) {}
        } message:{Text("Stop the clock and recording. The saved game remains available for scoring and export.")}
        .alert("Some moves still need attention",isPresented:$endNeedsAttention) {
            if recorder.canEndKeepingPending {
                Button("End and review later") {recorder.finish(retainingPending:true)}
            }
            Button("Keep reviewing",role:.cancel) {}
        } message:{Text(recorder.canEndKeepingPending
            ? "You can end the game now. Unverified moves and their clock evidence will be kept for later review. The complete SGF will remain unavailable until those moves are resolved."
            : recorder.status)}
    }
}

struct LiveRecognitionDiagnostics: View {
    @ObservedObject var model: ExperimentModel
    var body: some View {
        GroupBox("Live recognition") {
            VStack(alignment:.leading,spacing:8) {
                Text("Frame \(model.frameCount) · \(model.stable ? "Stable" : "Settling")").monospacedDigit()
                if let observation=model.observation {
                    let stones=observation.readings.filter {$0.occupancy.stone != nil}
                    let uncertain=observation.readings.filter {$0.occupancy == .uncertain}.count
                    Text("\(stones.count) stones · \(uncertain) uncertain intersections").monospacedDigit()
                    if let notice=observation.notice {Text(notice).foregroundStyle(.secondary)}
                    DisclosureGroup("Intersection confidence") {
                        ScrollView {
                            LazyVStack(alignment:.leading,spacing:3) {
                                ForEach(Array(observation.readings.enumerated()),id:\.offset) {_,reading in
                                    let point=PhysicalMoveInference.displayedPoint(row:reading.row,col:reading.col,size:observation.size,quarterTurns:model.viewQuarterTurns)
                                    let coordinate="\(Array("ABCDEFGHJKLMNOPQRST")[point % observation.size])\(observation.size-point/observation.size)"
                                    Text("\(coordinate) · \(reading.occupancy.rawValue) · \(Int((reading.confidence*100).rounded()))%")
                                        .font(.system(.caption,design:.monospaced))
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.frame(height:180)
                    }
                }
                DisclosureGroup("Latest alignment analysis") {
                    Text(model.latestAlignmentReport).font(.system(.caption,design:.monospaced))
                        .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("Use Correct board to inspect camera evidence for an intersection. Image capture is controlled separately below.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
        }
    }
}

/// Turn confirmation is a live-play action, independent of historical review.
struct LiveTurnPrompt:View {
    @ObservedObject var recorder:GameRecorder
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Whose turn is it?").font(.title3.bold())
            Text(recorder.clock.enabled ? "Recording continues. Confirm the current player to restart the clock; you can review earlier move order after the game." : "Recording continues. Confirm the current player; earlier move-order reviews can wait.").font(.callout).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("Black to play") {recorder.confirmLiveTurn(.black)}
                Button("White to play") {recorder.confirmLiveTurn(.white)}
            }.buttonStyle(.borderedProminent)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.orange.opacity(0.12),in:RoundedRectangle(cornerRadius:10))
    }
}
