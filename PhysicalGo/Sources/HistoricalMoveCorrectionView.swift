import SwiftUI

struct HistoricalMoveSelection:Identifiable {let id=UUID();let number:Int}

/// Attached editor, with click and coordinate entry as alternatives to dragging.
struct HistoricalMoveCorrectionView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let number:Int
    let onClose:()->Void
    var initialDestination:BoardPosition?=nil
    var reviewEdit:ReviewObservationEdit?=nil
    var onSaved:(()->Void)?=nil
    @State private var destination:BoardPosition?
    @State private var keepsLaterMoves=true
    @State private var coordinateText=""
    @State private var saveError:String?
    private var original:BoardPosition? {recorder.game.moves[number-1].1.map{BoardPosition($0.1,$0.0)}}
    private var result:Result<HistoricalMoveCorrection,Error>? {
        destination.map{point in Result{try HistoricalMoveCorrection(recorder:recorder,number:number,destination:point,keepsLaterMoves:keepsLaterMoves,reviewEdit:reviewEdit)}}
    }
    private var plan:HistoricalMoveCorrection? {try? result?.get()}
    private func coordinate(_ p:BoardPosition)->String {
        let last=Double(recorder.game.boardSize-1)
        let p=orientation.display(ImagePoint(x:Double(p.col)/last,y:Double(p.row)/last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x*last).rounded())])\(recorder.game.boardSize-Int((p.y*last).rounded()))"
    }
    private func select(_ point:BoardPosition) {destination=point;coordinateText=coordinate(point);saveError=nil}
    private func enterCoordinate() {
        let value=coordinateText.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        let letters=Array("ABCDEFGHJKLMNOPQRST"),size=recorder.game.boardSize
        guard let first=value.first,let col=letters.firstIndex(of:first),col<size,
              let row=Int(value.dropFirst()),(1...size).contains(row) else {saveError="Enter a coordinate on this board, such as N17.";return}
        let last=Double(size-1),p=orientation.source(ImagePoint(x:Double(col)/last,y:Double(size-row)/last))
        select(BoardPosition(Int((p.y*last).rounded()),Int((p.x*last).rounded())))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Correct move \(number)").font(.title2.bold())
            Text("Drag the marked stone to where it was played, or click the correct intersection.")
            Text("\(recorder.game.moves[number-1].0.rawValue.capitalized) · \(original.map(coordinate) ?? "Pass") → \(destination.map(coordinate) ?? "Choose intersection")").font(.headline)
            RecordedBoard(recorder:recorder,orientation:orientation,allowsLiveSelection:true,
                boardOverride:plan?.positions[number] ?? recorder.positions[number],
                highlightedPoints:[destination ?? original].compactMap{$0.map{$0.row*recorder.game.boardSize+$0.col}},
                showsLastMoveMarker:false,onDrag:{from,to in
                    if from==(destination ?? original) {select(to)}
                },onPoint:select)
                .frame(width:500,height:500)
            HStack {
                Text("Correct intersection")
                TextField("Coordinate",text:$coordinateText).frame(width:80).onSubmit(enterCoordinate)
                Button("Use coordinate",action:enterCoordinate)
            }
            Toggle("Keep later moves",isOn:$keepsLaterMoves).disabled(number==recorder.moveCount)
            if let plan {
                Text(plan.discardedMoves==0
                    ? "All \(plan.game.moves.count-number) later moves replay legally. \(plan.reviews.unresolved) reviews still need checking."
                    : "\(plan.discardedMoves) later moves will be set aside. They remain in the original recording. Review clock times before continuing.")
            } else if case .failure(let error)=result {Text(error.localizedDescription).foregroundStyle(.orange)}
            Text("Save creates a corrected copy and preserves the original. Clocks remain paused until you check the live board and resume.").font(.callout).foregroundStyle(.secondary)
            if let saveError {Text(saveError).foregroundStyle(.red)}
            HStack {
                Spacer()
                Button("Cancel",action:onClose).keyboardShortcut(.cancelAction)
                Button("Save corrected copy") {
                    guard let plan else {return}
                    do {try recorder.applyHistoricalCorrection(plan);onSaved?();onClose()} catch {saveError=error.localizedDescription}
                }.disabled(plan==nil).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:560).onAppear {if destination==nil,let initialDestination {select(initialDestination)}}
    }
}
