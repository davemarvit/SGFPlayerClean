import SwiftUI

struct PhysicalScoreButton:View {
    @ObservedObject var scoring:PhysicalScoring
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    var body:some View {
        Button("Score game") {scoring.open(recorder:recorder)}
            .disabled(!recorder.canScorePosition)
            .help("Pause play and ask the local AI for an estimate or end-of-game score.")
            .sheet(isPresented:$scoring.presented) {
                PhysicalScoringView(scoring:scoring,recorder:recorder,orientation:orientation)
                    .onDisappear {scoring.cancel()}
            }
    }
}

struct PhysicalScoringView:View {
    @ObservedObject var scoring:PhysicalScoring
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text(scoring.showsCountedTerritory ? "Review final score":"AI score estimate").font(.largeTitle.bold())
                    Spacer()
                    Button("Close scoring") {scoring.presented=false}.keyboardShortcut(.cancelAction)
                }
                Text("Clock and recording are paused. \(scoring.finalReview ? "Saved final position" : scoring.usesLivePosition ? "Retained game position" : "Move \(recorder.moveCount)") · \(recorder.game.info.rules ?? "Rules unspecified") · komi \(recorder.game.info.komi ?? "not set")")
                    .foregroundStyle(.secondary)
                if scoring.busy {HStack {ProgressView().controlSize(.small);Text(scoring.aiAvailable ? "Showing the saved analysis · refining the estimate…":"KataGo is analyzing this position…")}}
                if let error=scoring.error {Text(error).foregroundStyle(.red)}
                if let lead=scoring.displayedScoreLead {
                    Text(lead==0 ? "AI estimate: even":"AI estimate: \(lead>0 ? "Black":"White") leads by \(PhysicalScoring.points(abs(lead))) points")
                        .font(.title2.bold())
                    Text("\(scoring.visits) search visits · estimated outcome with continued play; unsettled areas may change").font(.caption).foregroundStyle(.secondary)
                }
                if let session=scoring.session {
                    HStack(alignment:.top,spacing:24) {
                        VStack(spacing:10) {
                            if scoring.finalReview {
                                Picker("Board markings",selection:$scoring.boardDisplay) {
                                    ForEach(PhysicalScoring.BoardDisplay.allCases,id:\.self) {Text($0.rawValue).tag($0)}
                                }.pickerStyle(.segmented)
                            }
                            PhysicalScoreBoard(session:session,ownership:scoring.ownership,likelyDead:scoring.likelyDead,finalReview:scoring.showsCountedTerritory,orientation:orientation,onTap:{if scoring.showsCountedTerritory {scoring.toggle($0)}},countedTerritory:scoring.countedTerritory).frame(width:500,height:500)
                        }.frame(width:500)
                        VStack(alignment:.leading,spacing:12) {
                            territoryLegend
                            if scoring.showsCountedTerritory {
                                Text("Proposed dead: \(session.deadStones.filter {session.board.stones[$0] == .black}.count) Black · \(session.deadStones.filter {session.board.stones[$0] == .white}.count) White").font(.callout.bold())
                                if let issue=session.issue {Text(issue).foregroundStyle(.orange)}
                                if let result=scoring.countedResult {
                                    Text((scoring.needsPrisonerConfirmation || !scoring.markingsConfirmed ? "Proposed count: ":"")+result.winnerDescription(blackName:recorder.game.info.playerBlack,whiteName:recorder.game.info.playerWhite)).font(.title2.bold())
                                    Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:8) {
                                        GridRow {Text("");Text("Black").bold();Text("White").bold()}
                                        row("Total",result.black.total,result.white.total)
                                        row("Territory",Double(result.black.territory),Double(result.white.territory))
                                        if session.rule.territoryScoring {
                                            row("Captures",Double(result.black.captured),Double(result.white.captured))
                                            row("Dead prisoners",Double(result.black.markedDead),Double(result.white.markedDead))
                                        } else {row("Living stones",Double(result.black.livingStones),Double(result.white.livingStones))}
                                        row("Komi",result.black.komi,result.white.komi)
                                        row("Handicap",result.black.handicap,result.white.handicap)
                                    }.monospacedDigit()
                                    Text("\(scoring.unassignedEmptyPoints) unmarked empty points are not counted. Check that these are neutral; assign Black or White territory where needed.").font(.caption).foregroundStyle(.secondary)
                                    PhysicalScoreApprovals(scoring:scoring)
                                    if scoring.accepted {Label(recorder.hasUnfinishedReviews ? "Agreed result saved · SGF awaits reviews":"Agreed result saved in SGF",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
                                    else {
                                        Text(scoring.approvalStatus).font(.callout).foregroundStyle(scoring.allApproved ? Color.green:.secondary).fixedSize(horizontal:false,vertical:true)
                                        Button("Save agreed result") {scoring.accept(recorder:recorder)}
                                            .buttonStyle(.borderedProminent).disabled(!scoring.canAccept)
                                    }
                                }
                            } else if scoring.finalReview {
                                Text("This is the AI’s estimate for the saved final position. Clearing the physical board does not change it.")
                                Text("For a final count, review dead groups and neutral areas together. The estimate does not replace a resignation or time result.").font(.callout).foregroundStyle(.secondary)
                                Button("Review final count") {scoring.boardDisplay = .counted}.buttonStyle(.borderedProminent)
                            } else {
                                Text("This game is still in progress. The estimate does not set a result or end the game.")
                                Text("Close scoring and resume recording to continue playing.").foregroundStyle(.secondary)
                                Button("End game and review final score") {scoring.reviewFinal(recorder:recorder);scoring.boardDisplay = .counted}
                                    .disabled(scoring.busy)
                            }
                        }.frame(width:330,alignment:.leading)
                    }
                }
                Text(scoring.usesLivePosition ? "Scoring uses the retained game position. Complete any reviews and finalize retained moves before exporting the SGF." : "Scoring uses the recorded position. Check the board and life-and-death markings together.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width:930,height:860)
    }
    private var territoryLegend:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(scoring.showsCountedTerritory ? "Counted territory":"AI territory estimate").font(.headline)
            HStack(spacing:16) {
                legendDot(.black,label:"Black")
                legendDot(.white,label:"White")
            }
            Text(scoring.showsCountedTerritory
                 ? "Dots show proposed territory. Review unmarked points."
                 : "Shading shows likely control; stronger shading means a stronger estimate. Unshaded areas are unsettled or neutral.")
                .font(.caption).foregroundStyle(.secondary)
            if !scoring.showsCountedTerritory {
                Text("Faded stones with crosses are likely to be lost, not confirmed dead.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.bottom,4)
    }
    private func legendDot(_ color:Color,label:String)->some View {
        HStack(spacing:6) {
            Circle().fill(color).overlay(Circle().stroke(.gray,lineWidth:0.5)).frame(width:12,height:12).accessibilityHidden(true)
            Text(label).font(.callout)
        }
    }
    private func row(_ label:String,_ black:Double,_ white:Double)->some View {
        GridRow {Text(label);Text(PhysicalScoring.points(black));Text(PhysicalScoring.points(white))}
    }
}
