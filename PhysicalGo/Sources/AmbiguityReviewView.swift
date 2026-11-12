import SwiftUI

struct PendingPlacementSelection:Identifiable {let id=UUID();let number:Int;var destination:BoardPosition?=nil}

struct AmbiguityReviewView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let color:Stone
    let onReview:(UUID)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries=[PlacementAmbiguity]()
    @State private var index=0
    @State private var pending:PendingPlacementSelection?
    @State private var saved:HistoricalMoveSelection?
    private var selected:PlacementAmbiguity? {entries.indices.contains(index) ? entries[index]:nil}
    private func edit(_ destination:BoardPosition?=nil) {
        guard let item=selected else {return}
        if let review=item.reviewID {dismiss();onReview(review);return}
        guard let number=item.number else {return}
        if number<=recorder.moveCount {saved = .init(number:number,destination:destination)}
        else {pending = .init(number:number,destination:destination)}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("\(color.rawValue.capitalized) placement ambiguities").font(.title2.bold())
            HStack {
                Button("Previous ambiguity") {index-=1}.disabled(index==0)
                Spacer()
                Text("\(entries.isEmpty ? 0:index+1) of \(entries.count)")
                Spacer()
                Button("Next ambiguity") {index+=1}.disabled(index+1>=entries.count)
            }
            if let item=selected {
                Text(item.number.map{"Position after move \($0)"} ?? "Earlier observed position").font(.headline)
                let unresolved=recorder.placementAmbiguities.contains{$0.id==item.id}
                if !unresolved {Label("Resolved since this review opened",systemImage:"checkmark.circle").foregroundStyle(.green)}
                RecordedBoard(recorder:recorder,orientation:orientation,boardOverride:item.board,highlightedPoints:item.points,
                    highlightColor:.orange,showsLastMoveMarker:false,onDrag:{from,to in
                        if item.points.contains(from.row*recorder.game.boardSize+from.col) {edit(to)}
                    },onPoint:{_ in}).frame(width:500,height:500)
                Text("This is the historical position, even if the stone was captured later. Browsing does not stop the clocks. Drag the marked stone or choose Correct placement to preview a correction.").font(.callout)
                Button("Correct placement…") {edit()}
            } else {Text("No unresolved placements for this player.")}
            HStack {Spacer();Button("Return to play") {dismiss()}.keyboardShortcut(.cancelAction)}
        }.padding(20).frame(width:600)
        .onAppear {entries=recorder.placementAmbiguities.filter{$0.color==color}}
        .sheet(item:$pending) {item in PendingPlacementReviewView(recorder:recorder,orientation:orientation,number:item.number,initialDestination:item.destination,onClose:{pending=nil})}
        .sheet(item:$saved) {item in HistoricalMoveCorrectionView(recorder:recorder,orientation:orientation,number:item.number,onClose:{saved=nil},initialDestination:item.destination)}
    }
}

/// Edits the retained sequence directly. A pending placement is never sent to
/// the unrelated missed-move/order workflow, and confirmation never presses a clock.
struct PendingPlacementReviewView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let number:Int
    var initialDestination:BoardPosition?=nil
    let onClose:()->Void
    @State private var revision:ReviewRevision?
    @State private var history:MoveObservationHistory?
    @State private var selected=0
    @State private var edits=[Int:Int]()
    @State private var error:String?
    private var draft:MoveObservationHistory? {guard let history else {return nil};return edits.isEmpty ? history:try? history.correcting(edits,game:recorder.game)}
    private var path:MoveObservationHistory.Candidate? {(draft ?? history)?.bestCandidate}
    private func name(_ point:Int)->String {BoardCoordinates.name(point:point,size:recorder.game.boardSize,orientation:orientation)}
    private func choose(_ point:BoardPosition,offset:Int?=nil) {
        edits[offset ?? selected]=point.row*recorder.game.boardSize+point.col;error=nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Confirm stone locations").font(.title2.bold())
            Text("Tracking continues while you inspect. Click the intended intersection or drag a stone. You can confirm several placements together.")
            if let path,!path.moves.isEmpty {
                Stepper("Position after move \(recorder.moveCount+selected+1)",value:$selected,in:0...max(0,path.moves.count-1))
                RecordedBoard(recorder:recorder,orientation:orientation,allowsLiveSelection:true,boardOverride:path.boards[min(selected,path.boards.count-1)],
                    highlightedPoints:[path.moves[min(selected,path.moves.count-1)]],highlightColor:.orange,showsLastMoveMarker:false,
                    onDrag:{from,to in
                        let point=from.row*recorder.game.boardSize+from.col
                        if let offset=path.moves.prefix(selected+1).lastIndex(of:point) {choose(to,offset:offset)}
                    },onPoint:{choose($0)}).frame(width:500,height:500)
                ScrollView {
                    VStack(alignment:.leading) {
                        ForEach(edits.keys.sorted(),id:\.self) {offset in Text("Move \(recorder.moveCount+offset+1): \(name(edits[offset]!))")}
                    }
                }.frame(maxHeight:100)
                if draft==nil {Text("The proposed locations conflict. Adjust the affected moves before confirming.").foregroundStyle(.orange)}
                Button("Confirm this displayed location") {edits[selected]=path.moves[selected]}
            }
            if revision?.matches(recorder)==false {
                Text("Play advanced or this placement resolved. Refresh before confirming.").foregroundStyle(.orange)
                Button("Refresh placements") {history=recorder.tentativeHistory;revision=ReviewRevision(recorder);edits=[:];selected=0}
            }
            if let error {Text(error).foregroundStyle(.red)}
            Text("Confirmation pauses play and preserves recorded clock presses. Return to play and Resume when the physical stones are at their intended intersections.").font(.caption)
            HStack {
                Button("Cancel",action:onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm \(edits.count) placements") {
                    guard let history,revision?.matches(recorder)==true else {error="Play advanced. Refresh the review before confirming.";return}
                    do {try recorder.applyPendingPlacements(edits,expected:history.checkpoint,revision:revision);onClose()} catch {self.error=error.localizedDescription}
                }.disabled(edits.isEmpty || draft==nil || revision?.matches(recorder) != true).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:600)
        .onAppear {
            history=recorder.tentativeHistory;revision=ReviewRevision(recorder)
            selected=max(0,min(number-recorder.moveCount-1,(history?.pendingCount ?? 1)-1))
            if let initialDestination {choose(initialDestination)}
        }
    }
}
