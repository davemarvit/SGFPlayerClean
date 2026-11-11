import SwiftUI

struct ReviewSectionView:View {
    enum Mode {case choose,cleanup,order,restore}
    @ObservedObject var recorder:GameRecorder
    let id:UUID
    let orientation:BoardOrientation
    let context:SGFGame
    let turnKnown:Bool
    private let initialWithdrawal:AccidentalStoneWithdrawal?
    let onClose:(()->Void)?
    let onCheckPhoto:(()->Void)?
    @State private var draft:MoveRecoveryDraft
    @State private var firstColor:Stone
    @State private var mode=Mode.choose
    @State private var error:String?
    @State private var colorOverride:BoardPosition?
    @State private var overrideCamera=false
    @State private var recoveringOrder=false
    @State private var recoveryMessage:String?
    @State private var turnConflict:ReviewOrderRecovery.Interval?
    @State private var recoveredOrders=[[Int]]()
    @State private var observationEdit:ReviewObservationEdit?
    @State private var savedCorrection:HistoricalMoveSelection?
    @State private var savedMoveNumber=1
    @State private var editedWithdrawal:AccidentalStoneWithdrawal?
    @State private var hasEditedObservation=false
    @Environment(\.dismiss) private var dismiss
    init(recorder:GameRecorder,id:UUID,orientation:BoardOrientation,onClose:(()->Void)?=nil,onCheckPhoto:(()->Void)?=nil) {
        self.recorder=recorder;self.id=id;self.orientation=orientation;self.onClose=onClose;self.onCheckPhoto=onCheckPhoto
        let section=recorder.reviewHistory.sections.first{$0.id==id}!
        let source=recorder.contextForReview(id)!
        var selectedContext=source.game
        if !source.turnKnown,let first=section.moves?.first {selectedContext.initialPlayer=first.color}
        context=selectedContext;turnKnown=source.turnKnown
        initialWithdrawal=recorder.accidentalWithdrawalPlan(id)
        let observation=BoardObservation(readings:section.after.enumerated().map{p,value in
            .init(row:p/recorder.game.boardSize,col:p%recorder.game.boardSize,occupancy:value,confidence:1,delta:0)
        },size:recorder.game.boardSize)
        var proposal=MoveRecoveryDraft(game:selectedContext,observation:observation)
        _firstColor=State(initialValue:proposal.nextPlayer)
        for move in section.moves ?? [] {_=proposal.add(move.point,checkCameraColor:false)}
        _draft=State(initialValue:proposal)
        _mode=State(initialValue:section.moves == nil ? .choose:.order)
    }
    private var section:DeferredMoveHistory.Section? {recorder.reviewHistory.sections.first{$0.id==id}}
    private var restoration:BoardRestorationPlan? {recorder.boardRestorationPlan(id)}
    private var showsRestoration:Bool {
        if mode == .restore {return true}
        if mode == .choose,let restoration,case .displaced = restoration.kind {return true}
        return false
    }
    private var changeKind:ReviewChangeKind {
        guard let section else {return .mixed}
        return .classify(before:section.before,after:section.after)
    }
    private var withdrawal:AccidentalStoneWithdrawal? {section?.committed == false ? (hasEditedObservation ? editedWithdrawal:initialWithdrawal):nil}
    private var cleanupReady:Bool {withdrawal.map{recorder.accidentalRemovalVerified($0)} ?? false}
    private var showsCleanupBoard:Bool {mode == .cleanup || (mode == .choose && cleanupReady)}
    private var differences:[ReviewComparison.Difference] {ReviewComparison.differences(selected:draft.board,camera:section?.after ?? [])}
    private var changedPoints:[Int] {
        guard let section else {return []}
        return section.before.indices.filter{section.before[$0] != section.after[$0]}
    }
    private var markers:[Int] {
        if showsCleanupBoard,let plan=withdrawal {
            return plan.removedPoints.filter{recorder.reviewCameraPosition?[$0] != .empty}.sorted()
        }
        return mode == .order ? differences.map(\.point):changedPoints
    }
    private var shownBoard:BoardSnapshot {
        guard let section else {return draft.board}
        if showsCleanupBoard,let plan=withdrawal {
            var shown=plan.target
            for point in markers {shown[point]=section.after[point]}
            return DeferredMoveHistory.board(shown,size:recorder.game.boardSize)
        }
        var shown=section.after
        if mode == .order {
            for point in draft.moves.compactMap({$0}) {
                let index=point.row*recorder.game.boardSize+point.col
                if let stone=draft.board.grid[point.row][point.col] {shown[index]=stone == .black ? .black:.white}
            }
        }
        return DeferredMoveHistory.board(shown,size:recorder.game.boardSize)
    }
    private func close() {if let onClose {onClose()} else {dismiss()}}
    private func select(_ point:BoardPosition?,checkColor:Bool=true) {
        guard mode == .order,section?.committed != true else {return}
        error=draft.add(point,checkCameraColor:checkColor)
        colorOverride=error?.contains("camera sees") == true ? point:nil
        if colorOverride != nil {error="\(draft.nextPlayer.rawValue.capitalized) was next. Choose that color’s stone, or undo the accidental stones if the wrong color was played."}
    }
    private func saveCleanup() {
        error=recorder.withdrawAccidentalMoves(id,removedByPlayer:true)
        if error==nil {completeReview()}
    }
    var body:some View {
        Group {
        if mode != .order,let capture=recorder.captureReviewPlan(id) {
            CaptureReviewView(recorder:recorder,plan:capture,orientation:orientation,onClose:close,
                onSaved:completeReview,onOtherMove:{mode = .order;error=nil},onCheckPhoto:onCheckPhoto)
        }
        else if showsRestoration,let restoration {
            BoardRestorationReviewView(recorder:recorder,plan:restoration,orientation:orientation,onClose:close,
                onSaved:completeReview,onActualMoves:{mode = .order;error=nil},onCheckPhoto:onCheckPhoto,
                onCorrectMove:{number,point in savedCorrection=HistoricalMoveSelection(number:number,destination:point)})
        }
        else if let section {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Text("Review \(section.reviewNumber ?? 0)").font(.title2.bold())
                    Spacer()
                    Label("Clocks paused",systemImage:"pause.circle").foregroundStyle(.secondary)
                }
                HStack(alignment:.top,spacing:22) {
                    VStack(alignment:.leading,spacing:8) {
                        Text(showsCleanupBoard ? "Position to continue from":"Position when this review began").font(.headline)
                        RecordedBoard(recorder:recorder,orientation:orientation,allowsLiveSelection:mode == .order && !section.committed,
                            boardOverride:shownBoard,numberedMoves:mode == .order ? draft.moves:[],
                            highlightedPoints:markers,highlightColor:.orange,showsLastMoveMarker:false,onDrag:{from,to in
                                guard !section.committed else {return}
                                do {observationEdit=try ReviewObservationEdit(recorder:recorder,reviewID:id,from:from,to:to)} catch {self.error=error.localizedDescription}
                            }) {select($0)}
                            .frame(width:520,height:520)
                            .allowsHitTesting(!section.committed)
                            .accessibilityLabel("Review board")
                        Text(showsCleanupBoard ? (markers.isEmpty ? "No extra stones remain marked.":"Remove only the orange-ringed stones.")
                             : mode == .order ? "Click stones in play order. Numbers show your selections.":"Orange rings identify changes. Drag a misplaced detection to preview a correction.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            if section.committed {
                                Label("Review resolved",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                                if let undone=section.undoneMoveNumbers,!undone.isEmpty {
                                    Text("Move\(undone.count == 1 ? "":"s") \(undone.sorted().map(String.init).joined(separator:", ")) from this review \(undone.count == 1 ? "was":"were") later undone. The original review evidence is preserved here.")
                                } else {Text("These choices are already saved in the game.")}
                            } else {
                                problem
                                if mode == .cleanup {cleanupInstructions}
                                else if mode == .order {orderingInstructions}
                                else {choices}
                                if let error {Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,4)
                    }.frame(width:300)
                }
                Divider()
                HStack {
                    Button(section.committed ? "Close":"Cancel") {close()}.keyboardShortcut(.cancelAction)
                    if mode != .choose && !section.committed {Button("Choose another solution") {mode = .choose;error=nil}}
                    Spacer()
                    if !section.committed && (mode == .cleanup || (mode == .choose && cleanupReady)) {
                        Button("Confirm cleanup") {saveCleanup()}.buttonStyle(.borderedProminent).disabled(!cleanupReady)
                    } else if mode == .order && !section.committed {
                        Button("Save reviewed moves") {
                            error=recorder.resolveReview(id,draft:draft,overrideCamera:overrideCamera)
                            if error==nil {completeReview()}
                        }.buttonStyle(.borderedProminent).disabled(!differences.isEmpty && !overrideCamera)
                    }
                }
            }.padding(20).frame(minWidth:882,minHeight:670)
                .task {if !section.committed {await recoverOrder()}}
                .onChange(of:firstColor) {_,color in
                    var updated=context;updated.initialPlayer=color
                    draft=MoveRecoveryDraft(game:updated,observation:draft.observation);error=nil;recoveredOrders=[];recoveryMessage=nil;turnConflict=nil
                }
        }
        }
        .safeAreaInset(edge:.bottom) {
            if recorder.moveCount>0 {
                HStack {
                    Text("Earlier saved move wrong?")
                    TextField("Move number",value:$savedMoveNumber,format:.number).frame(width:55)
                    Button("Correct saved move…") {
                        savedCorrection=HistoricalMoveSelection(number:max(1,min(savedMoveNumber,recorder.moveCount)))
                    }.disabled(HistoricalMoveCorrection.unavailableReason(recorder) != nil)
                    Spacer()
                }.padding(12).background(.bar)
            }
        }
        .sheet(item:$observationEdit) {edit in
            ReviewObservationEditView(recorder:recorder,edit:edit,orientation:orientation,onClose:{observationEdit=nil},onSaved:{
                if let section=self.section {
                    let observation=BoardObservation(readings:section.after.enumerated().map{.init(row:$0.offset/recorder.game.boardSize,col:$0.offset%recorder.game.boardSize,occupancy:$0.element,confidence:1,delta:0)},size:recorder.game.boardSize)
                    editedWithdrawal=recorder.accidentalWithdrawalPlan(id);hasEditedObservation=true
                    draft=MoveRecoveryDraft(game:context,observation:observation);mode = .choose;error=nil;recoveredOrders=[];recoveryMessage=nil;turnConflict=nil;overrideCamera=false;colorOverride=nil
                }
            },onHistorySaved:close)
        }
        .sheet(item:$savedCorrection) {selected in
            HistoricalMoveCorrectionView(recorder:recorder,orientation:orientation,number:selected.number,onClose:{savedCorrection=nil},initialDestination:selected.destination,onSaved:close)
        }
    }
    private var problem:some View {
        VStack(alignment:.leading,spacing:8) {
            if cleanupReady,let plan=withdrawal,mode != .order {
                Text("Ready to confirm the cleanup").font(.title3.bold())
                Text("The extra stones are gone. \(plan.nextPlayer.rawValue.capitalized) plays next after you save.")
            } else {
                Text(turnConflict != nil ? "The wrong color appears to have played first":changeKind.title).font(.title3.bold())
                if let conflict=turnConflict {
                    Text("\(firstColor.rawValue.capitalized) was next. The camera saw \(conflict.color.rawValue.capitalized) first among the marked stones.")
                } else {
                    Text(changeKind.instructions)
                    Text(turnKnown ? "The saved game has \(firstColor.rawValue.capitalized) to play.":"An earlier review is unresolved. The complete sequence will be checked afterward.").font(.callout)
                }
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
    private var choices:some View {
        VStack(alignment:.leading,spacing:12) {
            if let plan=withdrawal {
                if cleanupReady {
                    Label("Accidental stones are already removed",systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                    keptMovesDescription(plan)
                    Text("Click Confirm cleanup to remove the accidental placements and their removal from the game record.")
                } else {
                    Button("Undo accidental stones") {mode = .cleanup;error=nil}.buttonStyle(.borderedProminent)
                    Text("Use this if the wrong color or extra stones were played. The next step shows exactly what to remove.").font(.callout)
                }
            }
            if restoration != nil {
                Button("Restore accidentally removed stones") {mode = .restore;error=nil}
                Text("Use this only if the stones were moved or removed accidentally.").font(.callout).foregroundStyle(.secondary)
            }
            Button(changeKind.reviewAction) {mode = .order;error=nil}
            Text("Use this for moves and captures that actually occurred. Later sections remain preserved.").font(.callout).foregroundStyle(.secondary)
        }.fixedSize(horizontal:false,vertical:true)
    }
    private func keptMovesDescription(_ plan:AccidentalStoneWithdrawal)->some View {
        VStack(alignment:.leading,spacing:8) {
            if plan.keptMoves.count==1,let move=plan.keptMoves.first {
                Text("The later \(move.color.rawValue.capitalized) move will be kept.")
            } else if !plan.keptMoves.isEmpty {Text("All \(plan.keptMoves.count) later legal moves will be kept.")}
            Text("Related reviews are resolved together. Clock times stay unchanged.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var cleanupInstructions:some View {
        VStack(alignment:.leading,spacing:12) {
            if let plan=withdrawal {
                Text(cleanupReady ? "Cleanup verified":"Remove only the marked extras").font(.headline)
                Text(cleanupReady ? "The camera confirms the extra stones are gone. Click Confirm cleanup.":markers.isEmpty ? "The extra stones appear to be gone. Keep your hands clear while the camera checks the retained moves.":"Remove the orange-ringed stones from the physical board. Leave every other stone in place. The rings disappear as removal is verified.")
                keptMovesDescription(plan)
                Text("After saving, \(plan.nextPlayer.rawValue.capitalized) plays next. You decide when to resume the clocks.").font(.callout)
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
    private var orderingInstructions:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(differences.isEmpty ? "Sequence matches":"Step \(draft.moves.count+1): select \(draft.nextPlayer.rawValue.capitalized)’s move").font(.headline)
            Text(differences.isEmpty ? "Check the numbers, then save the moves.":"Click the stone that was played next. Only the selected moves are numbered.")
            HStack {
                Button("Undo selection") {draft.undo();error=nil;colorOverride=nil}.disabled(draft.moves.isEmpty)
                Button("Clear") {draft.clear();error=nil;colorOverride=nil}.disabled(draft.moves.isEmpty)
            }
            if !turnKnown {
                Picker("First player",selection:$firstColor) {Text("Black").tag(Stone.black);Text("White").tag(Stone.white)}.disabled(!draft.moves.isEmpty)
            }
            if !differences.isEmpty {Text("\(differences.count) locations still need to be accounted for.").font(.callout)}
            DisclosureGroup("Passes, camera corrections and details") {
                VStack(alignment:.leading,spacing:10) {
                    Button("\(draft.nextPlayer.rawValue.capitalized) passed") {select(nil)}
                    Text("Use Pass only if a player actually passed. Captured stones can be selected at their former intersections.").font(.caption)
                    if let point=colorOverride {Button("Camera color is wrong — use \(draft.nextPlayer.rawValue)") {select(point,checkColor:false)}}
                    Toggle("Camera snapshot is wrong; use my selected moves",isOn:$overrideCamera)
                    Text("An empty sequence means no moves in this section. Use Undo accidental stones for physical stones you removed.").font(.caption)
                    if recoveringOrder {ProgressView("Checking saved observations…")}
                    else {Button("Recover order from observations") {Task {await recoverOrder()}}}
                    if let recoveryMessage {Text(recoveryMessage).font(.caption)}
                    ForEach(recoveredOrders.indices,id:\.self) {index in Button(orderLabel(index)) {useOrder(recoveredOrders[index])}}
                    ForEach(differences) {difference in Text("\(difference.coordinate(size:recorder.game.boardSize,orientation:orientation)): \(difference.explanation)").font(.caption)}
                }.padding(.top,8)
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
    private func completeReview() {close()}
    private func proposal(_ points:[Int])->MoveRecoveryDraft? {
        var game=context;if !turnKnown {game.initialPlayer=firstColor}
        var result=MoveRecoveryDraft(game:game,observation:draft.observation)
        for point in points {guard result.add(BoardPosition(point/game.boardSize,point%game.boardSize),checkCameraColor:false)==nil else {return nil}}
        guard DeferredMoveHistory.states(result.board)==section?.after else {return nil};return result
    }
    private func useOrder(_ points:[Int]) {
        guard let proposed=proposal(points) else {return};draft=proposed;error=nil;colorOverride=nil;overrideCamera=false
    }
    private func coordinate(_ point:Int)->String {
        let n=recorder.game.boardSize,last=Double(n-1),p=orientation.display(.init(x:Double(point%n)/last,y:Double(point/n)/last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x*last).rounded())])\(n-Int((p.y*last).rounded()))"
    }
    private func orderLabel(_ index:Int)->String {
        let order=recoveredOrders[index]
        let different=order.indices.filter{offset in Set(recoveredOrders.map{$0[offset]}).count>1}
        return "Order \(index+1): "+different.prefix(4).map{coordinate(order[$0])+" (move \($0+1))"}.joined(separator:", ")
    }
    private func recoverOrder() async {
        guard !recoveringOrder,let section,!section.committed,let url=recorder.autosaveURL?.deletingPathExtension().appendingPathExtension("observations.jsonl") else {return}
        recoveringOrder=true;defer {recoveringOrder=false}
        let before=section.before,after=section.after,through=section.recordedAt,first=firstColor
        do {
            let result=try await Task.detached(priority:.utility) {try ReviewOrderRecovery.load(url:url,before:before,after:after,first:first,through:through)}.value
            guard firstColor==first,self.section?.after==after else {return}
            recoveredOrders=result.orders.filter{proposal($0) != nil};recoveryMessage=result.message;turnConflict=result.turnConflict
            if recoveredOrders.count==1,draft.moves.isEmpty {useOrder(recoveredOrders[0]);if mode == .choose && !cleanupReady {mode = .order}}
        } catch {recoveryMessage="Saved observations could not be read. Your selections are preserved."}
    }
}

struct ReviewQueueRail:View {
    @ObservedObject var recorder:GameRecorder
    let onReview:(UUID)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Reviews").font(.headline)
            ScrollView {
                VStack(spacing:10) {
                    ForEach(recorder.reviewHistory.reviews) {section in
                        let resolved=section.moves != nil
                        Button {onReview(section.id)} label: {
                            VStack(spacing:4) {
                                Label("Review \(section.reviewNumber ?? 0)",systemImage:resolved ? "checkmark.circle.fill":"exclamationmark.circle.fill")
                                Text(section.undoneMoveNumbers?.isEmpty == false ? "Later changed by undo":resolved ? "Resolved":recorder.captureReviewPlan(section.id) != nil ? "Finish capture":recorder.boardRestorationPlan(section.id) != nil ? "Check moved stones":"Needs review").font(.caption)
                            }.frame(maxWidth:.infinity).padding(.vertical,8)
                                .background((resolved ? Color.green:Color.red).opacity(0.18),in:RoundedRectangle(cornerRadius:8))
                                .overlay(RoundedRectangle(cornerRadius:8).stroke(resolved ? Color.green:Color.red,lineWidth:2))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Review \(section.reviewNumber ?? 0), \(resolved ? "resolved":"needs review")")
                    }
                }
            }.frame(height:min(400,CGFloat(recorder.reviewHistory.reviews.count)*64))
            if recorder.hasDeferredMoves {
                Text("\(recorder.reviewHistory.retainedMoveCount) ordered moves retained after the saved game.").font(.caption)
                Text("Later moves stay saved here while reviews are unresolved.").font(.caption).foregroundStyle(.secondary)
                if recorder.reviewHistory.unresolved==0 {
                    Button("Finalize reviewed moves") {_=recorder.finalizeReviews()}.disabled(![.paused,.finished].contains(recorder.state))
                }
            }
            if let error=recorder.reviewSaveError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button(recorder.recoveryReadBlocked ? "Reload saved history":"Retry saving reviews") {recorder.retryReviewSave()}
            }
        }.frame(width:150)
    }
}


/// This completion notice follows the shared controls; an active review editor
/// is never dismissed just because play resumes elsewhere.
struct SavedReviewNotice:View {
    @ObservedObject var recorder:GameRecorder
    @ObservedObject private var clock:LocalGameClock
    let onClose:()->Void
    init(recorder:GameRecorder,onClose:@escaping ()->Void) {
        self.recorder=recorder;self.onClose=onClose
        _clock=ObservedObject(wrappedValue:recorder.clock)
    }
    private var shouldClose:Bool {recorder.state != .paused || clock.running}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Review saved",systemImage:"checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            Text("Clock and recording are still paused.").font(.title3.bold())
            if let next=recorder.liveNextPlayer {
                Text("\(next.rawValue.capitalized) plays next. Resume when the physical board matches the reviewed position.")
            } else {
                Text("Confirm who plays next before resuming. Earlier unresolved sections still need review.")
            }
            Text("Resume here or on the main screen. This notice closes when play resumes.")
            HStack {
                Button("Keep paused",action:onClose)
                Spacer()
                Button("Resume clock and recording",systemImage:"play.fill") {
                    clock.requestResume();recorder.resume();onClose()
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(24).frame(minWidth:600,minHeight:240)
            .onChange(of:shouldClose,initial:true) {_,close in if close {onClose()}}
    }
}
