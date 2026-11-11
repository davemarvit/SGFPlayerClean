import SwiftUI

struct HistoricalMoveSelection:Identifiable {let id=UUID();let number:Int;var destination:BoardPosition?=nil}

/// A staged edit session: several historical placements become one corrected SGF.
struct HistoricalMoveCorrectionView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let number:Int
    let onClose:()->Void
    var initialDestination:BoardPosition?=nil
    var reviewEdit:ReviewObservationEdit?=nil
    var onSaved:(()->Void)?=nil
    @State private var selectedNumber=0
    @State private var destinations=[Int:BoardPosition]()
    @State private var coordinateText=""
    @State private var saveError:String?
    private var activeNumber:Int {max(1,min(selectedNumber==0 ? number:selectedNumber,recorder.moveCount))}
    private var edits:[HistoricalMoveCorrection.Edit] {destinations.keys.sorted().map{.init(number:$0,destination:destinations[$0]!)}}
    private var result:Result<HistoricalMoveCorrection,Error>? {
        edits.isEmpty ? nil:Result{try HistoricalMoveCorrection(recorder:recorder,edits:edits,reviewEdit:reviewEdit)}
    }
    private var plan:HistoricalMoveCorrection? {try? result?.get()}
    private func original(_ move:Int)->BoardPosition? {recorder.game.moves[move-1].1.map{BoardPosition($0.1,$0.0)}}
    private func coordinate(_ p:BoardPosition)->String {BoardCoordinates.name(point:p.row*recorder.game.boardSize+p.col,size:recorder.game.boardSize,orientation:orientation)}
    private var heading:String {
        guard edits.count==1,let edit=edits.first else {return "Correct game record"}
        return "Change move \(edit.number) from \(original(edit.number).map(coordinate) ?? "Pass") to \(coordinate(edit.destination))?"
    }
    private func select(_ point:BoardPosition,move:Int?=nil) {
        let n=move ?? activeNumber
        if point==original(n) {destinations.removeValue(forKey:n)} else {destinations[n]=point}
        // Dragging an older stone should keep the viewed position in place,
        // so the next correction can be made on the same board.
        if move==nil {selectedNumber=n}
        coordinateText=(destinations[activeNumber] ?? original(activeNumber)).map(coordinate) ?? "";saveError=nil
    }
    private func drag(_ from:BoardPosition,_ to:BoardPosition) {
        guard from != to,let n=HistoricalMoveCorrection.moveNumber(at:from,through:activeNumber,
            game:plan?.game ?? recorder.game,positions:plan?.positions ?? recorder.positions) else {return}
        select(to,move:n)
    }
    private func enterCoordinate() {
        let value=coordinateText.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        let letters=Array("ABCDEFGHJKLMNOPQRST"),size=recorder.game.boardSize
        guard let first=value.first,let col=letters.firstIndex(of:first),col<size,
              let row=Int(value.dropFirst()),(1...size).contains(row) else {saveError="Enter a coordinate on this board, such as N17.";return}
        let last=Double(size-1),p=orientation.source(ImagePoint(x:Double(col)/last,y:Double(size-row)/last))
        select(BoardPosition(Int((p.y*last).rounded()),Int((p.x*last).rounded())))
    }
    var body:some View {
        VStack(spacing:0) {
        ScrollView {
        VStack(alignment:.leading,spacing:12) {
            Text(heading).font(.title2.bold())
            Text("Drag a stone to its intended intersection. Browse earlier moves to correct stones that were later captured. All edits stay in this preview until you confirm.")
            HStack {
                Stepper("View after move \(activeNumber)",value:$selectedNumber,in:1...max(1,recorder.moveCount))
                Button("Latest") {selectedNumber=recorder.moveCount}
            }
            Text("\(recorder.game.moves[activeNumber-1].0.rawValue.capitalized) move \(activeNumber) · \(original(activeNumber).map(coordinate) ?? "Pass") → \(destinations[activeNumber].map(coordinate) ?? "unchanged")").font(.headline)
            RecordedBoard(recorder:recorder,orientation:orientation,allowsLiveSelection:true,
                boardOverride:plan?.positions[activeNumber] ?? recorder.positions[activeNumber],
                highlightedPoints:[plan == nil ? original(activeNumber):destinations[activeNumber] ?? original(activeNumber)].compactMap{$0.map{$0.row*recorder.game.boardSize+$0.col}},
                showsLastMoveMarker:false,onDrag:drag,onPoint:{select($0)})
                .frame(width:500,height:500)
            HStack {
                Text("Move \(activeNumber) belongs at")
                TextField("Coordinate",text:$coordinateText).frame(width:80).onSubmit(enterCoordinate)
                Button("Use coordinate",action:enterCoordinate)
            }
            if !edits.isEmpty {
                Text("Changes to save (\(edits.count))").font(.headline)
                ForEach(edits,id:\.number) {edit in
                    HStack {
                        Text("Move \(edit.number): \(original(edit.number).map(coordinate) ?? "Pass") → \(coordinate(edit.destination))")
                        Spacer()
                        Button("Show") {selectedNumber=edit.number}
                        Button("Remove edit") {destinations.removeValue(forKey:edit.number)}
                    }
                }
            }
            if let plan {
                Text(plan.discardedMoves==0
                    ? "The complete sequence replays legally. \(plan.reviews.unresolved==0 ? "No unresolved board reviews remain.":"\(plan.reviews.unresolved) board reviews still need checking.")"
                    : "\(plan.discardedMoves) later moves will be set aside in the original recording. Check clock times before continuing.")
            } else if case .failure(let error)=result {
                Text(error.localizedDescription).foregroundStyle(.orange)
                Text("The board shows the original position while the edits conflict. You can still browse and stage more corrections.").font(.caption)
            }
            Text("Confirm saves all corrections to a new SGF and preserves the original. Keep the physical stones at their intended intersections. Clocks stay paused; Resume checks the corrected board before play continues.").font(.callout).foregroundStyle(.secondary)
            if let saveError {Text(saveError).foregroundStyle(.red)}
        }.padding(20)
        }
        Divider()
            HStack {
                Button("Cancel",action:onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button(edits.count==1 ? "Yes, correct move":"Confirm \(edits.count) corrections") {
                    guard let plan else {return}
                    do {try recorder.applyHistoricalCorrection(plan);onSaved?();onClose()} catch {saveError=error.localizedDescription}
                }.disabled(plan==nil).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width:620,height:850)
        .onAppear {
            if selectedNumber==0 {selectedNumber=number;if let initialDestination {select(initialDestination)}}
        }
        .onChange(of:selectedNumber) {_,_ in coordinateText=(destinations[activeNumber] ?? original(activeNumber)).map(coordinate) ?? ""}
    }
}
