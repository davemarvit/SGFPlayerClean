import SwiftUI

struct PhysicalScoreButton:View {
    @ObservedObject var scoring:PhysicalScoring
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    var body:some View {
        Button("Score game") {scoring.open(recorder:recorder)}
            .disabled(!recorder.canScorePosition)
            .help("Pause play and estimate the final score with strong continued play.")
            .sheet(isPresented:$scoring.presented) {
                PhysicalScoringView(scoring:scoring,recorder:recorder,orientation:orientation)
                    .onDisappear {scoring.cancel()}
            }
    }
}

/// The score screen always forecasts continued play, even after recording ends.
/// An agreed result is a separate, explicit workflow for a settled position.
struct PhysicalScoringView:View {
    @ObservedObject var scoring:PhysicalScoring
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    @State private var reviewingAgreement=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("Estimated final score").font(.largeTitle.bold())
                    Spacer()
                    Button("Close scoring") {scoring.presented=false}.keyboardShortcut(.cancelAction)
                }
                Text("\(scoring.finalReview ? "Saved position" : "Move \(recorder.moveCount)") · \(recorder.game.info.rules ?? "Rules unspecified") · komi \(recorder.game.info.komi ?? "not set")")
                    .foregroundStyle(.secondary)
                if let result=scoring.projectedScoreDescription {
                    Text(result).font(.system(size:30,weight:.bold)).accessibilityIdentifier("projected-final-score")
                    Text("AI forecast with strong play from both sides, including komi.").font(.callout)
                }
                if scoring.busy {
                    HStack {ProgressView().controlSize(.small);Text(scoring.aiAvailable ? "Refining the estimate…":"Estimating the final score…")}
                }
                if let error=scoring.error {Text(error).foregroundStyle(.red)}
                if let session=scoring.session {
                    HStack(alignment:.top,spacing:24) {
                        PhysicalScoreBoard(session:session,ownership:scoring.projectedOwnership,likelyDead:scoring.likelyDead,
                                           finalReview:false,orientation:orientation).frame(width:500,height:500)
                        VStack(alignment:.leading,spacing:16) {
                            Text("Expected territory").font(.title3.bold())
                            Text("Shading shows where the AI expects territory to belong after continued play.")
                            ownershipLegend
                            Text("Stronger shading means greater confidence. Faint or unshaded areas are uncertain or neutral.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text("Faded stones with crosses are expected to be lost.")
                                .font(.callout).foregroundStyle(.secondary)
                            Divider()
                            Text("The score includes the AI’s expectations for unsettled areas, even where shading is faint.")
                                .font(.callout)
                            if scoring.aiAvailable {
                                Text("\(scoring.visits) search visits").font(.caption).foregroundStyle(.secondary)
                            }
                            if let result=recorder.game.info.result,!result.isEmpty {
                                Text("Recorded result: \(result)").font(.callout.bold())
                            }
                        }.frame(width:330,alignment:.leading)
                    }
                }
                Divider()
                PhysicalGameReviewView(review:scoring.review)
                Text(scoring.usesLivePosition ? "Using the retained game position. Clock and recording are paused." : "Using the recorded position. Clock and recording are paused.")
                    .font(.caption).foregroundStyle(.secondary)
                if scoring.finalReview {
                    Divider()
                    HStack {
                        Text("Finished playing and ready to agree a result?").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Review agreed result…") {reviewingAgreement=true}
                            .disabled(!scoring.aiAvailable || scoring.busy)
                    }
                } else {
                    Text("Close scoring and resume recording to continue playing.").font(.callout).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.frame(width:930,height:860)
            .sheet(isPresented:$reviewingAgreement) {
                PhysicalAgreedScoreView(scoring:scoring,recorder:recorder,orientation:orientation)
            }
    }
    private var ownershipLegend:some View {
        VStack(spacing:6) {
            LinearGradient(colors:[.black,Color(red:0.78,green:0.63,blue:0.39),.white],startPoint:.leading,endPoint:.trailing)
                .frame(height:16).clipShape(RoundedRectangle(cornerRadius:4)).accessibilityHidden(true)
            HStack {Text("Black");Spacer();Text("Uncertain");Spacer();Text("White")}.font(.caption)
        }
    }
}

/// Manual adjudication never replaces the main AI forecast or writes it as RE.
struct PhysicalAgreedScoreView:View {
    @ObservedObject var scoring:PhysicalScoring
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("Agree a completed game’s result").font(.title.bold())
                    Spacer()
                    Button("Back to estimate") {dismiss()}.keyboardShortcut(.cancelAction)
                }
                Text("Use this only when play is complete and both players agree on territory, dead groups and neutral points. For an unfinished game, use the AI estimate.")
                    .font(.callout)
                if let error=scoring.error {Text(error).foregroundStyle(.red)}
                if let session=scoring.session {
                    HStack(alignment:.top,spacing:24) {
                        PhysicalScoreBoard(session:session,ownership:[:],likelyDead:[:],finalReview:true,orientation:orientation,
                                           onTap:{scoring.toggle($0)},countedTerritory:scoring.countedTerritory).frame(width:500,height:500)
                        VStack(alignment:.leading,spacing:12) {
                            Text("Territory for agreement").font(.headline)
                            Text("Dots mark assigned territory. Review the board together before saving.").font(.caption).foregroundStyle(.secondary)
                            if let issue=session.issue {Text(issue).foregroundStyle(.orange)}
                            if let result=scoring.countedResult {
                                // Do not announce a winner from a partial territory assignment.
                                if scoring.allApproved {
                                    Text(result.winnerDescription(blackName:recorder.game.info.playerBlack,whiteName:recorder.game.info.playerWhite)).font(.title2.bold())
                                }
                                Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:8) {
                                    GridRow {Text("");Text("Black").bold();Text("White").bold()}
                                    row("Assigned total",result.black.total,result.white.total)
                                    row("Territory",Double(result.black.territory),Double(result.white.territory))
                                    if session.rule.territoryScoring {
                                        row("Captures",Double(result.black.captured),Double(result.white.captured))
                                        row("Dead prisoners",Double(result.black.markedDead),Double(result.white.markedDead))
                                    } else {row("Living stones",Double(result.black.livingStones),Double(result.white.livingStones))}
                                    row("Komi",result.black.komi,result.white.komi)
                                    row("Handicap",result.black.handicap,result.white.handicap)
                                }.monospacedDigit()
                                Text("\(scoring.unassignedEmptyPoints) unassigned empty points. Confirm these are neutral, or assign their territory before saving.")
                                    .font(.caption).foregroundStyle(.secondary)
                                PhysicalScoreApprovals(scoring:scoring)
                                if scoring.accepted {
                                    Label(recorder.hasUnfinishedReviews ? "Agreed result saved · SGF awaits reviews":"Agreed result saved in SGF",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Text(scoring.approvalStatus).font(.callout).foregroundStyle(scoring.allApproved ? Color.green:.secondary)
                                    Button("Save agreed result") {scoring.accept(recorder:recorder)}
                                        .buttonStyle(.borderedProminent).disabled(!scoring.canAccept)
                                }
                            }
                        }.frame(width:330,alignment:.leading)
                    }
                }
            }.padding(24)
        }.frame(width:930,height:860)
    }
    private func row(_ label:String,_ black:Double,_ white:Double)->some View {
        GridRow {Text(label);Text(PhysicalScoring.points(black));Text(PhysicalScoring.points(white))}
    }
}
