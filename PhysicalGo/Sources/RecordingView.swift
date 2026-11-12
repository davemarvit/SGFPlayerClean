import SwiftUI

struct RecordingView: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var recorder: GameRecorder
    @ObservedObject private var onlineBoard: PhysicalOnlineBoard
    init(model: ExperimentModel, recorder: GameRecorder, showsRecordingControls:Bool=true,initialDisplay:Display = .live) {
        self.model=model; self.recorder=recorder; self.onlineBoard=model.onlineBoard; self.showsRecordingControls=showsRecordingControls;_display=State(initialValue:initialDisplay)
    }
    enum Display:Hashable {case live,saved,feed,inspect}
    var showsRecordingControls=true
    @State private var display=Display.live
    @State private var confirmNew=false
    @State private var manualPoint:BoardPosition?
    @State private var recovery:MoveRecoveryDraft?
    @State private var recoveryFirstPoint:BoardPosition?
    @State private var reviewRecoveryClocks=false
    @State private var showRecoveryClockReview=false
    @State private var undoPlan:UndoMovePlan?
    @State private var correctionSelection:HistoricalMoveSelection?
    @State private var pendingPlacement:PendingPlacementSelection?
    @State private var correctionError:String?
    @State private var observationEdit:ReviewObservationEdit?
    private var unrecordedDetections:Int {
        InterpretationDetectionMarks.make(board:recorder.positions.last,observation:model.visibleObservation,size:recorder.game.boardSize).filter{$0.kind == .untracked}.count
    }
    private var checkPoints:Set<Int> {RecordingClarity.checkPoints(recorder:recorder,observation:model.visibleObservation)}
    private func openReview(_ id:UUID) {
        model.reviewPresentation.open(recorder:recorder,id:id,orientation:model.orientation,onCheckPhoto:{model.beginBoardCorrection()})
    }
    private func reviewMarkedStone(_ point:Int) {
        switch RecordingClarity.action(at:point,recorder:recorder) {
        case .review(let id):openReview(id)
        case .pendingPlacement(let number):
            recorder.pause();recorder.returnToLatest()
            pendingPlacement = .init(number:number)
        case .missedMoves(let index):beginRecovery(at:BoardPosition(index/recorder.game.boardSize,index%recorder.game.boardSize))
        case .recordedPlacement(let number):
            recorder.pause();recorder.returnToLatest()
            if let reason=HistoricalMoveCorrection.unavailableReason(recorder) {correctionError=reason}
            else {correctionSelection = .init(number:number)}
        }
    }
    private func beginRecovery(at point:BoardPosition?=nil) {
        if recorder.hasDeferredMoves,let section=recorder.reviewHistory.reviews.first(where:{$0.moves==nil}) ?? recorder.reviewHistory.reviews.last {openReview(section.id);return}
        recoveryFirstPoint=point
        recorder.pause();recorder.returnToLatest();recorder.clock.pause("Ordering missed moves · clock and recording paused")
        recovery=MoveRecoveryDraft(recorder:recorder,observation:model.visibleObservation)
    }
    private func beginCorrection(from:BoardPosition,to:BoardPosition) {
        guard from != to else {return}
        guard !onlineBoard.enabled else {correctionError="Leave online play before editing a local game record. This does not change moves on the server.";return}
        let through=display == .saved ? recorder.reviewIndex:recorder.moveCount
        let shown=display == .saved ? recorder.reviewedBoard:recorder.interpretedBoard
        let color=shown?.grid[from.row][from.col]
        guard color != nil else {return}
        recorder.pause();correctionError=nil
        if recorder.positions[through].grid[from.row][from.col]==color,
           let number=HistoricalMoveCorrection.moveNumber(at:from,through:through,game:recorder.game,positions:recorder.positions) {
            if let reason=HistoricalMoveCorrection.unavailableReason(recorder) {correctionError=reason;return}
            correctionSelection=HistoricalMoveSelection(number:number,destination:to)
        } else if let section=recorder.reviewHistory.sections.last(where:{!$0.committed}) {
            do {observationEdit=try ReviewObservationEdit(recorder:recorder,reviewID:section.id,from:from,to:to)}
            catch {correctionError=error.localizedDescription}
        } else if let path=recorder.tentativeHistory.bestCandidate,
                  let offset=path.moves.lastIndex(of:from.row*recorder.game.boardSize+from.col) {
            pendingPlacement = .init(number:recorder.moveCount+offset+1,destination:to)
        } else {correctionError="This detection has not established a move yet. Keep the board clear for another view."}
    }
    private func coordinate(_ p:BoardPosition)->String {
        let last=Double(recorder.game.boardSize-1)
        let point=model.orientation.display(ImagePoint(x:Double(p.col)/last,y:Double(p.row)/last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((point.x*last).rounded())])\(recorder.game.boardSize-Int((point.y*last).rounded()))"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            if showsRecordingControls && !onlineBoard.enabled { recordingSection }
            if !showsRecordingControls || model.playMode == .local || model.showDiagnostics {boardSection}
        }
        .onChange(of:model.showDiagnostics) {_,visible in if !visible && display == .inspect {display = .live}}
        .onChange(of:display) {_,view in
            if view == .saved {recorder.pause()}
            else if view == .live && recorder.reviewing {recorder.returnToLatest()}
        }
        .onChange(of:recorder.autosaveURL) {_,_ in display = .live;model.reviewPresentation.close();undoPlan=nil;correctionSelection=nil}
        .onChange(of:recorder.state) {_,state in
            if state == .verifying || (state == .recording && display == .saved) {display = .live}
        }
        .sheet(item:$recovery,onDismiss:{
            if reviewRecoveryClocks {reviewRecoveryClocks=false;showRecoveryClockReview=true}
        }) {draft in
            MoveRecoveryView(recorder:recorder,orientation:model.orientation,draft:draft,initialSelection:recoveryFirstPoint) {
                if recorder.state == .finished {return}
                if recorder.clock.enabled {reviewRecoveryClocks=true}
                else {recorder.resume()}
            }
        }
        .sheet(isPresented:$showRecoveryClockReview) {LocalClockCorrection(clock:recorder.clock,recorder:recorder,resumeAfterReview:true)}
        .sheet(item:$undoPlan) {plan in
            UndoMoveView(model:model,recorder:recorder,plan:plan,onClose:{undoPlan=nil})
        }
        .sheet(item:$correctionSelection) {selection in
            HistoricalMoveCorrectionView(recorder:recorder,orientation:model.orientation,number:selection.number,onClose:{correctionSelection=nil},initialDestination:selection.destination)
        }
        .sheet(item:$pendingPlacement) {item in
            PendingPlacementReviewView(recorder:recorder,orientation:model.orientation,number:item.number,initialDestination:item.destination,onClose:{pendingPlacement=nil})
        }
        .sheet(item:$observationEdit) {edit in
            ReviewObservationEditView(recorder:recorder,edit:edit,orientation:model.orientation,onClose:{observationEdit=nil},onSaved:{},onHistorySaved:{observationEdit=nil})
        }
        .sheet(isPresented:$confirmNew) {
            ScrollView { VStack(alignment:.leading,spacing:14) {
                Text("Start a new game").font(.title2.bold())
                NewGameSettings(model:model,showsClockSettings:false)
                Text(model.newGameHandicap>0 ? "Start with a verified empty board. After starting, place the handicap stones shown; the camera will check them before White plays." : "Clear the physical board and keep your hands out of view. Black plays first.")
                if recorder.hasGame { Text("Your previous game is saved separately.") }
                if model.frozen && model.running {
                    Button("Resume camera") {model.toggleFreeze()}
                } else if !model.running && !model.cameraID.isEmpty {
                    Button("Start camera") {model.start()}
                } else if model.showsStartupReferenceControl {
                    StartupReferenceControl(model:model)
                }
                Label(model.newGameReadiness,systemImage:model.canStartNewRecording ? "checkmark.circle.fill" : "info.circle")
                    .lineLimit(5,reservesSpace:true)
                    .frame(maxWidth:.infinity,alignment:.topLeading)
                    .help(model.newGameReadiness)
                HStack {
                    Spacer()
                    Button("Cancel") {confirmNew=false}.keyboardShortcut(.cancelAction)
                    Button("Start recording") {
                        let previousURL=recorder.autosaveURL
                        model.startRecording()
                        if (recorder.state == .recording || recorder.state == .verifying) && recorder.autosaveURL != previousURL {confirmNew=false}
                    }.disabled(!model.canStartNewRecording).keyboardShortcut(.defaultAction)
                }
            }.padding(20) }.frame(width:500,height:650)
        }
        .alert("Record a missed move?",isPresented:Binding(get:{manualPoint != nil},set:{if !$0 {manualPoint=nil}}),presenting:manualPoint) {point in
            Button("Record move") {recorder.manualMove(at:point);manualPoint=nil}
            Button("Cancel",role:.cancel) {manualPoint=nil}
        } message: {point in Text("Record \(recorder.nextPlayer.rawValue) at \(coordinate(point))? This is a manual correction to the latest position.")}
    }
    private var recordingSection:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:10) {
                Text("Recording").font(.system(size:14*model.interfaceScale,weight:.semibold))
                RecordingTransport(model:model,recorder:recorder)
                RecordingStateLabel(recorder:recorder,textScale:model.interfaceScale)
                Text(recorder.status).font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                Picker("Sound", selection:$model.soundMode) {
                    ForEach(ExperimentModel.RecordingSounds.allCases,id:\.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }.help("Adjustments only chimes once when a stone needs repositioning. All feedback includes move confirmations and recording warnings.")
                HStack {
                    if recorder.hasGame {
                        Button("\((recorder.liveNextPlayer ?? recorder.nextPlayer).rawValue.capitalized) pass") {recorder.pass()}.disabled(!recorder.canPass)
                    }
                    Spacer()
                    Button("New game…") {confirmNew=true}
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
        }
    }
    private var boardSection:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("Board interpretation").font(.system(size:14*model.interfaceScale,weight:.semibold))
                    Spacer()
                    if recorder.hasGame && !onlineBoard.enabled {
                        Button("Undo move…",systemImage:"arrow.uturn.backward") {beginUndo()}
                            .disabled(UndoMovePlan.unavailableReason(recorder) != nil)
                            .help(UndoMovePlan.unavailableReason(recorder) ?? "Pause and review the last saved move before undoing it.")
                    }
                }
                if recorder.hasGame && !onlineBoard.enabled {
                    RecordedTurnIndicator(recorder:recorder,textScale:model.interfaceScale)
                    Picker("Board display",selection:$display) {
                        Text("Live position").tag(Display.live)
                        Text("Saved moves").tag(Display.saved)
                        Text("Live feed").tag(Display.feed)
                        if model.showDiagnostics {Text("Inspect detection").tag(Display.inspect)}
                    }.pickerStyle(.segmented)
                    Text(recorder.hasDeferredMoves ? "\(recorder.moveCount) in SGF · \(recorder.reviewHistory.retainedMoveCount) later moves retained · \(recorder.reviewHistory.unresolved) reviews needed" : "\(recorder.moveCount) saved · \(recorder.pendingMoveCount) pending · \(unrecordedDetections) detected outside saved history")
                        .font(.system(size:14*model.interfaceScale,weight:.semibold)).monospacedDigit()
                }
                if display == .feed && !onlineBoard.enabled && recorder.hasGame {
                    CameraCanvas(model:model).allowsHitTesting(false).frame(height:520)
                    Text("Live camera · same orientation as the board. Switch to Live position to order missed moves.").font(.callout).foregroundStyle(.secondary)
                } else if onlineBoard.enabled || !recorder.hasGame || display == .inspect {
                    if model.showDiagnostics {DetectionInspectionView(model:model,recorder:recorder)}
                    else {DetectedBoard(model:model,recorder:recorder).aspectRatio(1,contentMode:.fit).frame(maxWidth:520)}
                } else {
                    HStack(alignment:.top,spacing:16) {
                        SquareBoardLayout {
                        RecordedBoard(recorder:recorder,orientation:model.orientation,showsLivePosition:display == .live,
                                      observation:display == .live ? model.visibleObservation : nil,
                                      allowsLiveSelection:display == .live && recorder.state != .finished,
                                      onDrag:beginCorrection) {point in
                            if display == .live {
                                let index=point.row*recorder.game.boardSize+point.col
                                if checkPoints.contains(index) || recorder.interpretationWarnings.contains(index) {reviewMarkedStone(index)}
                                else {beginRecovery(at:point)}
                            } else {manualPoint=point}
                        }
                        }.frame(maxWidth:520)
                        if !recorder.reviewHistory.reviews.isEmpty {
                            ReviewQueueRail(recorder:recorder,onReview:openReview)
                        }
                    }
                    Text("Drag a wrongly recorded stone to its intended intersection. Use Saved moves to find earlier stones. Review and confirm several corrections together.").font(.callout)
                    if let correctionError {Text(correctionError).foregroundStyle(.orange)}
                    ZStack(alignment:.topLeading) {
                        liveBoardActions.opacity(display == .live ? 1:0)
                            .allowsHitTesting(display == .live).accessibilityHidden(display != .live)
                        VStack(alignment:.leading,spacing:10) {
                            reviewControls.frame(maxWidth:520)
                            if recorder.canEdit {
                                Text("To enter a missed move, click its empty intersection above. Undo removes the last move; browsing does not change history.")
                                    .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                            }
                        }.opacity(display == .saved ? 1:0)
                            .allowsHitTesting(display == .saved).accessibilityHidden(display != .saved)
                    }

                }
                if recorder.hasGame && !onlineBoard.enabled {
                    if model.showDiagnostics {confidenceDetails}
                    HStack {
                        if let reason=UndoMovePlan.unavailableReason(recorder),recorder.moveCount>0 {
                            Text("Undo move: \(reason)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let error=recorder.diagnosticError {Text(error).foregroundStyle(.red)}
                    if let error=recorder.reviewSaveError,recorder.reviewHistory.reviews.isEmpty {
                        Text(error).foregroundStyle(.red)
                        Button(recorder.recoveryReadBlocked ? "Reload saved history":"Retry saving recording") {recorder.retryRecordingSave()}
                    }
                    if let error=recorder.pendingSaveError {Text(error).foregroundStyle(.red)}
                    if recorder.saveError != nil || recorder.pendingSaveError != nil || (recorder.clock.enabled && recorder.clock.saveError != nil) {
                        Button(recorder.recoveryReadBlocked ? "Reload saved history":"Retry saving recording") {recorder.retryRecordingSave()}
                    }
                    if let error=recorder.saveError {Text(error).foregroundStyle(.red)}
                    else if let url=recorder.autosaveURL {
                        Button("Show autosaved game") {NSWorkspace.shared.activateFileViewerSelecting([url])}
                            .font(.system(size:12*model.interfaceScale))
                    }
                }
                if model.showDiagnostics {DetectionTuningView(model:model,recorder:recorder)}
                Divider()
                CameraControlsView(model:model)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
        }
    }
    private var liveBoardActions:some View {
        VStack(alignment:.leading,spacing:10) {
            if let explanation=RecordingClarity.explanation(recorder:recorder,observation:model.visibleObservation,orientation:model.orientation) {
                Text(explanation).font(.system(size:14*model.interfaceScale)).foregroundStyle(.orange)
            }
            if let capture=recorder.pendingCaptureReview {
                Button("Finish capture…",systemImage:"checkmark.circle") {openReview(capture.id)}
                    .buttonStyle(.borderedProminent).tint(.orange)
            } else if let restoration=recorder.pendingBoardRestoration {
                Button("Check moved stones…",systemImage:"arrow.uturn.backward.circle") {openReview(restoration.id)}
                    .buttonStyle(.borderedProminent).tint(.orange)
            } else {
            if !checkPoints.isEmpty {
                Button("Review highlighted stones…",systemImage:"checkmark.circle") {if let point=checkPoints.sorted().first {reviewMarkedStone(point)}}
                    .buttonStyle(.borderedProminent).tint(.orange)
                Text("Click a marked stone to address its issue: confirm a location, review missing moves, or check a capture or recorded placement.")
                    .font(.callout)
            }
            Button("Order missed moves…",systemImage:"list.number") {beginRecovery()}
                .buttonStyle(.borderedProminent)
                .actionAttention(unrecordedDetections>0 ? .required:.none)
                .disabled(recorder.state == .finished)
            Text("If moves are missing or their order is wrong, choose Order missed moves and approve their sequence.").font(.callout)
            }
            Text("Red ring: pending move needs checking. Dashed red: detected stone outside the retained sequence. Orange: a persistent conflict or ambiguous placement to check. Center dot: last interpreted move.")
                .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
            Text(recorder.hasDeferredMoves ? "Observed position · reviewed history is kept separately until finalized" : "Live position · \(recorder.moveCount+recorder.pendingConfidence.count) moves")
                .font(.system(size:13*model.interfaceScale).monospacedDigit())
        }
    }
    private func beginUndo() {
        guard let plan=UndoMovePlan(recorder:recorder) else {return}
        recorder.pause();recorder.returnToLatest()
        undoPlan=plan
    }
    private var reviewControls:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text(reviewLabel).font(.system(size:13*model.interfaceScale).monospacedDigit())
                Spacer()
                Button("Correct move…") {recorder.pause();correctionSelection=HistoricalMoveSelection(number:recorder.reviewIndex)}
                    .disabled(recorder.reviewIndex==0 || HistoricalMoveCorrection.unavailableReason(recorder) != nil || onlineBoard.enabled)
                    .help(HistoricalMoveCorrection.unavailableReason(recorder) ?? "Correct the saved intersection and check subsequent moves")
            }
            HStack {
                navigation("Starting position",icon:"backward.end.fill",target:0).disabled(recorder.reviewIndex==0)
                navigation("Previous move",icon:"chevron.left",target:recorder.reviewIndex-1).disabled(recorder.reviewIndex==0)
                navigation("Next move",icon:"chevron.right",target:recorder.reviewIndex+1).disabled(recorder.reviewIndex==recorder.moveCount)
                navigation("Latest move",icon:"forward.end.fill",target:recorder.moveCount).disabled(recorder.reviewIndex==recorder.moveCount)
                Spacer()
                Text("Go to move")
                TextField("Move number",value:Binding(get:{recorder.reviewIndex},set:{recorder.seek($0)}),format:.number)
                    .frame(width:50).accessibilityLabel("Go to saved move")
                Text("/ \(recorder.moveCount)").monospacedDigit()
            }
        }
    }
    @ViewBuilder private var confidenceDetails:some View {
        if !recorder.pendingConfidence.isEmpty {
            DisclosureGroup("Move confidence") {
                VStack(alignment:.leading,spacing:5) {
                    ForEach(Array(recorder.pendingConfidence.prefix(6).enumerated()),id:\.offset) {index,evidence in
                        HStack {
                            let point=evidence.point.map{coordinate(BoardPosition($0/recorder.game.boardSize,$0%recorder.game.boardSize))} ?? "location unclear"
                            Text("\(recorder.moveCount+index+1) · \(point)")
                            Spacer()
                            Text(evidence.placementUncertain ? "Placement unclear" : evidence.level.capitalized)
                                .foregroundStyle(evidence.level=="high" ? Color.green : evidence.level=="medium" ? .blue : .orange)
                        }.font(.system(size:12*model.interfaceScale)).monospacedDigit()
                    }
                    if recorder.pendingConfidence.count>6 {Text("+ \(recorder.pendingConfidence.count-6) later moves retained")}
                    Text("Repeated sightings build confidence. SGF waits until the earlier moves and sequence are clear.")
                        .foregroundStyle(.secondary)
                }.font(.system(size:11*model.interfaceScale))
            }.padding(8).background(.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
        }
    }
    private func navigation(_ label:String,icon:String,target:Int)->some View {
        Button {display = .saved;recorder.seek(target)} label:{Image(systemName:icon)}.help(label).accessibilityLabel(label)
    }
    private var reviewLabel:String {
        guard recorder.reviewIndex>0 else {return recorder.moveCount==0 ? "No moves recorded yet" : "Starting position · 0 of \(recorder.moveCount)"}
        let move=recorder.game.moves[recorder.reviewIndex-1]
        let point=move.1.map{coordinate(BoardPosition($0.1,$0.0))} ?? "Pass"
        return "Move \(recorder.reviewIndex) · \(move.0.rawValue.capitalized) \(point)"
    }
}

struct RecordedBoard: View {
    @ObservedObject var recorder: GameRecorder
    let orientation: BoardOrientation
    var showsLivePosition = false
    var observation:BoardObservation? = nil
    var allowsLiveSelection=false
    var boardOverride:BoardSnapshot?=nil
    var numberedMoves:[BoardPosition?]=[]
    var highlightedPoints:[Int]=[]
    var highlightColor:Color = .pink
    var showsLastMoveMarker=true
    var onDrag:((BoardPosition,BoardPosition)->Void)?=nil
    let onPoint:(BoardPosition)->Void
    @State private var draggedFrom:BoardPosition?
    @State private var draggedLocation:CGPoint?
    var body: some View {
        GeometryReader { proxy in
            let side=min(proxy.size.width,proxy.size.height), margin:CGFloat=26
            let origin=CGPoint(x:(proxy.size.width-side)/2+margin,y:margin)
            let boardSize=recorder.game.boardSize
            let pitch=(side-2*margin)/Double(boardSize-1)
            Canvas { context,_ in
                context.fill(Path(roundedRect:CGRect(x:origin.x-margin,y:0,width:side,height:side),cornerRadius:8),with:.color(Color(red:0.8,green:0.66,blue:0.43)))
                var lines=Path()
                for i in 0..<recorder.game.boardSize {
                    let d=Double(i)*pitch
                    lines.move(to:CGPoint(x:origin.x+d,y:origin.y)); lines.addLine(to:CGPoint(x:origin.x+d,y:origin.y+side-2*margin))
                    lines.move(to:CGPoint(x:origin.x,y:origin.y+d)); lines.addLine(to:CGPoint(x:origin.x+side-2*margin,y:origin.y+d))
                }
                context.stroke(lines,with:.color(.black.opacity(0.6)),lineWidth:0.7)
                func point(_ p:BoardPosition)->CGPoint {
                    let xy=orientation.display(ImagePoint(x:Double(p.col)/Double(boardSize-1),y:Double(p.row)/Double(boardSize-1)))
                    return CGPoint(x:origin.x+xy.x*(side-2*margin),y:origin.y+xy.y*(side-2*margin))
                }
                for label in BoardCoordinates.labels(size:boardSize,orientation:BoardOrientation(0),margin:min(0.55,18/pitch)) {
                    context.draw(Text(label.text).font(.system(size:max(8,min(11,pitch*0.42)),weight:.regular)).foregroundColor(.black),
                        at:CGPoint(x:origin.x+label.grid.x*pitch,y:origin.y+label.grid.y*pitch))
                }
                let n=recorder.game.boardSize, near=n==9 ? 2 : 3, far=n-1-near
                let stars=n==19 ? [3,9,15].flatMap{r in [3,9,15].map{BoardPosition(r,$0)}} : [BoardPosition(near,near),BoardPosition(near,far),BoardPosition(far,near),BoardPosition(far,far),BoardPosition(n/2,n/2)]
                for star in stars { let p=point(star); context.fill(Path(ellipseIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(.black)) }
                let board=boardOverride ?? (showsLivePosition ? recorder.interpretedBoard : recorder.reviewedBoard)
                let rings=showsLivePosition && boardOverride == nil ? recorder.interpretationWarnings : []
                for (position,color) in board?.stones ?? [:] {
                    let p=point(position),r=pitch*0.44
                    context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(color == .black ? .black : .white))
                    if rings.contains(position.row*boardSize+position.col) {
                        context.stroke(Path(ellipseIn:CGRect(x:p.x-r-2,y:p.y-r-2,width:2*r+4,height:2*r+4)),with:.color(.red),lineWidth:2.8)
                    }
                }
                if showsLivePosition {
                    for mark in InterpretationDetectionMarks.make(board:board,observation:observation,size:boardSize) where recorder.adjustmentIssues[mark.point] != nil {
                        let p=point(BoardPosition(mark.point/boardSize,mark.point%boardSize)),r=pitch*0.46
                        let circle=Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
                        switch mark.kind {
                        case .untracked:
                            context.fill(circle,with:.color((mark.occupancy == .black ? Color.black : .white).opacity(0.45)))
                            context.stroke(circle,with:.color(.red),style:StrokeStyle(lineWidth:2,dash:[3,3]))
                        case .disagreement:
                            context.stroke(circle,with:.color(.orange),style:StrokeStyle(lineWidth:1.5,dash:[2,3]))
                        case .uncertain:
                            context.fill(Path(ellipseIn:CGRect(x:p.x-pitch*0.10,y:p.y-pitch*0.10,width:pitch*0.2,height:pitch*0.2)),with:.color(.orange))
                        }
                    }
                }
                if showsLivePosition && boardOverride == nil {
                    for index in RecordingClarity.checkPoints(recorder:recorder,observation:observation) {
                        let p=point(BoardPosition(index/boardSize,index%boardSize)),r=pitch*0.50
                        let ring=Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r))
                        context.stroke(ring,with:.color(.black.opacity(0.8)),lineWidth:5)
                        context.stroke(ring,with:.color(.orange),lineWidth:3.5)
                    }
                }
                let marker=showsLivePosition ? recorder.lastInterpretedPoint : (recorder.reviewIndex>0 ? recorder.game.moves[recorder.reviewIndex-1].1.map{$0.1*boardSize+$0.0} : nil)
                if showsLastMoveMarker,numberedMoves.isEmpty,let marker, let color=board?.grid[marker/boardSize][marker%boardSize] {
                    let p=point(BoardPosition(marker/boardSize,marker%boardSize))
                    context.fill(Path(ellipseIn:CGRect(x:p.x-pitch*0.13,y:p.y-pitch*0.13,width:pitch*0.26,height:pitch*0.26)),with:.color(color == .black ? .white : .black))
                }
                for (offset,position) in numberedMoves.enumerated() {
                    guard let position,numberedMoves.lastIndex(where:{$0==position})==offset else {continue}
                    let p=point(position),r=pitch*0.38
                    context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.color(.blue))
                    context.draw(Text("\(offset+1)").font(.system(size:max(10,pitch*0.55),weight:.bold)).foregroundColor(.white),at:p)
                }
                for index in highlightedPoints {
                    let p=point(BoardPosition(index/boardSize,index%boardSize)),r=pitch*0.50
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(highlightColor),lineWidth:3)
                }
                if let from=draggedFrom,let location=draggedLocation,let color=board?.grid[from.row][from.col] {
                    let r=pitch*0.44
                    let ghost=Path(ellipseIn:CGRect(x:location.x-r,y:location.y-r,width:2*r,height:2*r))
                    context.fill(ghost,with:.color((color == .black ? Color.black:Color.white).opacity(0.75)))
                    context.stroke(ghost,with:.color(.blue),lineWidth:2)
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:4).onChanged {drag in
                guard onDrag != nil else {return}
                if draggedFrom==nil {
                    let p=orientation.source(ImagePoint(x:(drag.startLocation.x-origin.x)/(side-2*margin),y:(drag.startLocation.y-origin.y)/(side-2*margin)))
                    let col=Int((p.x*Double(boardSize-1)).rounded()),row=Int((p.y*Double(boardSize-1)).rounded())
                    let board=boardOverride ?? (showsLivePosition ? recorder.interpretedBoard:recorder.reviewedBoard)
                    guard (0..<boardSize).contains(row),(0..<boardSize).contains(col),board?.grid[row][col] != nil else {return}
                    draggedFrom=BoardPosition(row,col);recorder.pause()
                }
                draggedLocation=drag.location
            }.onEnded {drag in
                defer {draggedFrom=nil;draggedLocation=nil}
                guard let onDrag else {return}
                func position(_ location:CGPoint)->BoardPosition? {
                    let p=orientation.source(ImagePoint(x:(location.x-origin.x)/(side-2*margin),y:(location.y-origin.y)/(side-2*margin)))
                    let col=Int((p.x*Double(boardSize-1)).rounded()),row=Int((p.y*Double(boardSize-1)).rounded())
                    guard (0..<boardSize).contains(row),(0..<boardSize).contains(col) else {return nil}
                    return BoardPosition(row,col)
                }
                if let from=position(drag.startLocation),let to=position(drag.location) {onDrag(from,to)}
            }.exclusively(before:SpatialTapGesture().onEnded { tap in
                guard allowsLiveSelection || (!showsLivePosition && recorder.canEdit) else { return }
                let p=orientation.source(ImagePoint(x:(tap.location.x-origin.x)/(side-2*margin),y:(tap.location.y-origin.y)/(side-2*margin)))
                let col=Int((p.x*Double(recorder.game.boardSize-1)).rounded()),row=Int((p.y*Double(recorder.game.boardSize-1)).rounded())
                guard (0..<recorder.game.boardSize).contains(row),(0..<recorder.game.boardSize).contains(col) else {return}
                if !allowsLiveSelection && recorder.reviewedBoard?.grid[row][col] != nil {return}
                onPoint(BoardPosition(row,col))
            }))
        }.accessibilityLabel(showsLivePosition ? "Live interpretation: \(recorder.moveCount) saved, \(recorder.pendingMoveCount) pending, \(recorder.interpretationWarnings.count) stones need attention" : "Recorded game at move \(recorder.reviewIndex) of \(recorder.moveCount)")
    }
}

/// Familiar transport controls stay above the board, separate from move review.
private struct RecordingTransport:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    private var active:Bool {recorder.state == .recording || recorder.state == .verifying}
    private var ready:Bool {model.recordingControlReady}
    private var recordTint:Color {active || (ready && recorder.state != .finished) ? .red : .gray}
    private var recordLabel:String {
        if recorder.state == .paused {return recorder.awaitingFirstStart ? "Start" : "Resume"}
        if recorder.state == .verifying {return "Preparing"}
        return active ? (recorder.retainingTentativeMoves ? "Tracking" : recorder.needsAttention ? "Blocked" : "Recording") : "Record"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:10) {
                Button {
                    if recorder.state == .paused {model.resumeRecording()} else {model.startRecording()}
                } label: {
                    HStack(spacing:9) {
                        Image(systemName:"record.circle").font(.system(size:32*model.interfaceScale,weight:.medium)).foregroundStyle(recordTint)
                        Text(recordLabel).font(.system(size:14*model.interfaceScale,weight:.semibold))
                    }.frame(maxWidth:.infinity,minHeight:52*model.interfaceScale)
                        .background(recordTint.opacity(active ? 0.16 : 0.08),in:RoundedRectangle(cornerRadius:10))
                        .overlay(RoundedRectangle(cornerRadius:10).stroke(recordTint.opacity(0.45),lineWidth:1))
                        .contentShape(RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain).disabled(active || !ready || recorder.state == .finished)
                    .accessibilityLabel(recorder.awaitingFirstStart ? "Start game" : recorder.state == .paused ? "Resume recording" : "Start recording")
                    .help(recorder.awaitingFirstStart ? "Start the game after verifying the board" : recorder.state == .paused ? "Resume saving moves to this game" : "Start recording a new game from an empty board")
                Button {recorder.pause()} label: {
                    HStack(spacing:9) {
                        Image(systemName:"pause.fill").font(.system(size:27*model.interfaceScale,weight:.semibold))
                        Text("Pause").font(.system(size:14*model.interfaceScale,weight:.semibold))
                    }.frame(maxWidth:.infinity,minHeight:52*model.interfaceScale)
                        .background(Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                        .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.primary.opacity(0.2),lineWidth:1))
                        .contentShape(RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain).disabled(!active).accessibilityLabel("Pause recording")
                    .help("Pause saving moves; the camera preview continues")
            }
            if !active {
                RecordingReadinessPanel(model:model,recorder:recorder)
            }
        }
    }
}

/// Reserve the same space before and after capture; completion stays latched to the reference.
struct StartupReferenceControl:View {
    @ObservedObject var model:ExperimentModel
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            Group {
                if model.startupReferenceCaptured {
                    Label("Reference captured",systemImage:"checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {model.captureStartupReference()} label: {
                        Label("Board is empty — capture reference",systemImage:"camera.viewfinder")
                    }.buttonStyle(.bordered)
                        .disabled(!model.canCaptureStartupReference)
                        .help("Remove all stones and hands before capturing. This does not start recording.")
                }
            }.font(.system(size:13*model.interfaceScale,weight:.semibold))
                .frame(height:30*model.interfaceScale,alignment:.leading)
            Text(model.startupReferenceCaptured
                 ? "No need to capture again. Wait for Ready to record, then start recording."
                 : "Remove all stones and hands before clicking. Then keep the board empty until Ready.")
                .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                .lineLimit(3,reservesSpace:true)
                .frame(maxWidth:.infinity,alignment:.topLeading)
        }
    }
}

/// The reason Record is disabled and the safe empty-board fallback belong together.
private struct RecordingReadinessPanel:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    var compact=false
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            if model.showsStartupReferenceControl {
                StartupReferenceControl(model:model)
            }
            if compact {
                Text(model.recordingReadiness).font(.system(size:12*model.interfaceScale))
                    .foregroundStyle(.secondary).lineLimit(2,reservesSpace:true)
                    .frame(maxWidth:.infinity,alignment:.leading).help(model.recordingReadiness)
            } else {
            Label(model.recordingReadinessTitle,systemImage:model.recordingControlReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size:17*model.interfaceScale,weight:.bold))
                .foregroundStyle(model.recordingControlReady ? Color.green : Color.orange)
                .lineLimit(2,reservesSpace:true)
            Text(model.recordingReadiness)
                .font(.system(size:13*model.interfaceScale))
                .lineLimit(5,reservesSpace:true)
                .frame(maxWidth:.infinity,alignment:.topLeading)
                .help(model.recordingReadiness)
            }
        }
    }
}

private struct RecordedTurnIndicator:View {
    @ObservedObject var recorder:GameRecorder
    let textScale:Double
    private var color:Stone {
        if recorder.reviewIndex==recorder.moveCount {return recorder.nextPlayer}
        return recorder.reviewIndex==0 ? (recorder.game.initialPlayer ?? .black) : recorder.game.moves[recorder.reviewIndex-1].0.opponent
    }
    var body:some View {
        if recorder.hasDeferredMoves {
            VStack(alignment:.leading,spacing:3) {
                Text("\(recorder.reviewHistory.unresolved) sections need review").font(.headline).foregroundStyle(.red)
                Text(recorder.liveNextPlayer.map{"\($0.rawValue.capitalized) to play · review earlier sequences after the game."} ?? "Confirm the current player below the clocks. Earlier sequences can wait.").font(.callout)
            }
        } else if recorder.state != .finished {
            HStack(spacing:9) {
                Circle().fill(color == .black ? Color.black : .white)
                    .overlay(Circle().stroke(Color.gray,lineWidth:1))
                    .frame(width:22*textScale,height:22*textScale)
                    .accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) {
                    Text(recorder.state == .verifying && recorder.game.handicap>0 ? "Place handicap stones first" : "\(color.rawValue.capitalized) to play").font(.system(size:17*textScale,weight:.semibold))
                    Text(recorder.pendingMoveCount>0 ? "Checking \(recorder.pendingMoveCount) possible moves · turn changes after confirmation" : recorder.reviewing ? "At reviewed move \(recorder.reviewIndex)" : recorder.hasGame ? "Recorded position · move \(recorder.moveCount)" : "New game")
                        .font(.system(size:11*textScale)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RecordingStateLabel:View {
    @ObservedObject var recorder:GameRecorder
    let textScale:Double
    var tint:Color {recorder.awaitingFirstStart ? .accentColor : recorder.retainingTentativeMoves ? .orange : recorder.needsAttention || (recorder.state == .recording && recorder.synchronized) ? .red : .orange}
    private var title:String {
        switch recorder.state {
        case .idle:return "NOT RECORDING — camera preview only"
        case .paused:return recorder.awaitingFirstStart ? "READY — press Start to begin":"PAUSED — moves are not being saved"
        case .verifying:return "WAITING — not recording yet"
        case .finished:return "FINISHED — moves are not being saved"
        case .recording:
            if recorder.hasDeferredMoves {return "RECORDING LATER MOVES · \(recorder.reviewHistory.unresolved) reviews needed"}
            if recorder.retainingTentativeMoves {return "TRACKING · \(recorder.moveCount) saved · \(recorder.pendingMoveCount) pending"}
            return "\(recorder.needsAttention ? "NOT SAVING MOVES" : recorder.synchronized ? "RECORDING" : "CHECKING BOARD") · \(recorder.moveCount) \(recorder.moveCount == 1 ? "move" : "moves") saved"
        }
    }
    var body:some View {
        Label(title,systemImage:recorder.awaitingFirstStart ? "play.circle.fill" : recorder.state == .recording ? "record.circle.fill" : recorder.state == .finished ? "stop.fill" : "pause.fill")
            .font(.system(size:14*textScale,weight:.bold)).foregroundStyle(tint).fixedSize(horizontal:false,vertical:true)
    }
}

/// Keep camera activity visually distinct from saving moves, including before a game starts.
struct RecordingStatusBanner: View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    @ObservedObject private var clock:LocalGameClock
    let textScale:Double
    init(model:ExperimentModel,recorder:GameRecorder,textScale:Double) {
        self.model=model;self.recorder=recorder;self.textScale=textScale
        _clock=ObservedObject(wrappedValue:recorder.clock)
    }
    var body:some View {
        let message=LocalPlayStatus(recorder:recorder)
        let warning=model.alignmentNeedsRecovery || model.lightingNeedsRecovery || recorder.state != .recording || !recorder.synchronized || recorder.needsAttention
        let tint:Color=recorder.saveError != nil || recorder.reviewSaveError != nil || recorder.pendingSaveError != nil || clock.saveError != nil ? .red:warning ? .orange:.green
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label(message.title,systemImage:warning ? "pause.circle.fill":"checkmark.circle.fill")
                    .font(.system(size:17*textScale,weight:.semibold)).foregroundStyle(tint)
                Spacer()
                if !clock.enabled || (clock.running && recorder.state == .paused) {transport}
            }
            Text(message.detail).font(.system(size:13*textScale))
            if model.alignmentNeedsRecovery {
                Text(model.recoveryLikelyObstruction
                     ? "Move hands or obstructions clear. Visible stones still match; keep the camera and board in place."
                     : "Check lighting and clear obstructions. Keep all four corners visible while the grid is checked.")
                Text(model.recoveryDetail).font(.callout).foregroundStyle(.secondary)
                Button("Board is in view — retry") {model.detectGrid()}
                    .disabled(model.detectingGrid || model.image == nil || model.frozen || model.cameraState != .live)
            } else if model.lightingNeedsRecovery {
                Text("Light the board evenly and reduce glare or strong shadows. Keep the stones in place while the view is checked.")
            }
            Text(message.nextStep).font(.system(size:13*textScale,weight:.medium))
            if let notice=recorder.reviewNotice {Label(notice,systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
            if recorder.needsTurnConfirmation,LocalPlayPresentation(recorder:recorder,clock:clock).correction==nil {LiveTurnPrompt(recorder:recorder)}
            if recorder.state == .verifying && recorder.game.handicap>0 {
                HandicapSetupBoard(size:recorder.game.boardSize,handicap:recorder.game.handicap,orientation:model.orientation).frame(width:260,height:260)
            }
            if recorder.automaticCaptureStatus != nil {
                Button("Review capture…") {
                    if let id=recorder.prepareAutomaticCaptureReview() {
                        model.reviewPresentation.open(recorder:recorder,id:id,orientation:model.orientation,onCheckPhoto:{model.beginBoardCorrection()})
                    }
                }
            }
            if recorder.needsAttention && recorder.state == .recording {
                Button("Pause and inspect board",systemImage:"pause.circle.fill") {recorder.pause()}
            }
            if recorder.saveError != nil || recorder.pendingSaveError != nil || recorder.reviewSaveError != nil || clock.saveError != nil {
                Button("Retry saving") {recorder.retryRecordingSave()}
            }
            if recorder.hasUnfinishedReviews {Text("Resolve the remaining reviews before exporting the complete SGF. Later moves remain in the recovery record.").font(.callout).foregroundStyle(.secondary)}
            if !model.exportStatus.isEmpty {Text(model.exportStatus).textSelection(.enabled)}
            if let pause=clock.automaticPause,!clock.running || clock.timingNote != nil {
                DisclosureGroup("Earlier clock details") {
                    Text("Original pause: \(pause.reason)")
                    if let note=clock.timingNote {Text(note)}
                }.font(.callout).foregroundStyle(.secondary)
            } else if let note=clock.timingNote {
                DisclosureGroup("Earlier clock details") {Text(note)}.font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
            .background(tint.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(tint.opacity(0.5),lineWidth:1))
            .accessibilityIdentifier("play-status")
    }
    private var transport:some View {
HStack(alignment:.center,spacing:16) {
                // A clock deliberately left running must not prevent recording from resuming.
                if (!clock.enabled || clock.running) && (recorder.state == .paused || recorder.state == .idle) {
                    Button {
                        if recorder.state == .paused {model.resumeRecording()} else {model.startRecording()}
                    } label: {
                        Label(recorder.awaitingFirstStart ? "Start game" : recorder.state == .paused ? "Resume recording" : "Start recording",systemImage:"record.circle.fill")
                            .font(.system(size:14*textScale,weight:.semibold)).padding(.vertical,6)
                    }.tint(.accentColor).buttonStyle(.borderedProminent)
                        .disabled(!model.recordingControlReady)
                } else if (!clock.enabled && recorder.state == .recording) || recorder.state == .verifying {
                    Button {recorder.pause()} label: {Label("Pause",systemImage:"pause.fill")}
                        .font(.system(size:14*textScale,weight:.semibold)).controlSize(.large)
                        .accessibilityLabel("Pause recording")
                }
            }
    }
}

/// Online play and offline recording have separate game states. Never present
/// the recorder's default Black-to-play state as the turn of an online game.
struct GameStatusBanner: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var recorder: GameRecorder
    @ObservedObject var bridge: PhysicalOnlineBoard
    let textScale: Double
    var body: some View {
        if bridge.enabled {
            VStack(alignment:.leading,spacing:8) {
                OnlineTurnIndicator(bridge:bridge,textScale:textScale)
                if model.boardCorrections.isEditing { Text("Correcting board · moves paused").foregroundStyle(.purple) }
                else if !model.boardCorrections.values.isEmpty { Text("\(model.boardCorrections.values.count) manual intersections · purple rings in Board interpretation").foregroundStyle(.purple) }
                if let issue=bridge.moveIssue {
                    Label(issue,systemImage:"exclamationmark.triangle.fill")
                        .font(.system(size:17*textScale,weight:.semibold)).foregroundStyle(.red)
                } else if let issue=bridge.placementIssue {
                    Label(issue.title,systemImage:issue.needsCorrection ? "exclamationmark.triangle.fill" : "hand.point.down.fill")
                        .font(.system(size:17*textScale,weight:.semibold))
                        .foregroundStyle(issue.needsCorrection ? Color.red : Color.blue)
                } else if bridge.turnColor == nil {
                    Text(bridge.status).font(.system(size:14*textScale))
                }
            }
        } else {
            RecordingStatusBanner(model:model,recorder:recorder,textScale:textScale)
        }
    }
}

/// Derive both dimensions from the available width. A tab's footer cannot
/// compress the board vertically or change its grid spacing.
struct SquareBoardLayout:Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let side=max(0,min(520,proposal.width ?? 520))
        return CGSize(width:side,height:side)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        for view in subviews {view.place(at:bounds.origin,anchor:.topLeading,proposal:ProposedViewSize(width:bounds.width,height:bounds.width))}
    }
}
