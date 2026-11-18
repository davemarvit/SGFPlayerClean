import SwiftUI

/// Review known turns without constructing permutations of their locations.
struct DeferredLocationsReviewView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let number:Int
    let initialDestination:BoardPosition?
    let onClose:()->Void
    @State private var records=[RecordingStoneLedger.Record]()
    @State private var points=[Int:Int]()
    @State private var selected=0
    @State private var error:String?
    private var current:Bool {records.map(\.id)==recorder.deferredPendingRecords.map(\.id)}
    private func load() {
        records=recorder.deferredPendingRecords;points=[:];selected=records.firstIndex(where:{$0.number==number}) ?? 0;error=nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Confirm retained turn locations").font(.title2.bold())
            Text("The order and original clock presses are saved. Choose the intended intersection for each move; the final sequence will be checked against Go rules.")
            if records.indices.contains(selected) {
                let record=records[selected]
                Stepper("Move \(record.number) · \(record.color.rawValue.capitalized)",value:$selected,in:0...max(0,records.count-1))
                RecordedBoard(recorder:recorder,orientation:orientation,allowsLiveSelection:true,
                    boardOverride:recorder.positions.last,highlightedPoints:points[record.number].map{[$0]} ?? record.candidates.sorted(),
                    highlightColor:.orange,showsLastMoveMarker:false,onPoint:{p in points[record.number]=p.row*recorder.game.boardSize+p.col;error=nil})
                    .frame(width:500,height:500)
                Text("\(points.count) of \(records.count) locations selected")
            }
            if !current {Text("Play advanced. Refresh before confirming.").foregroundStyle(.orange);Button("Refresh",action:load)}
            if let error {Text(error).foregroundStyle(.red)}
            Text("Confirmation pauses play for review. Original turn times and increments remain unchanged.").font(.caption)
            HStack {
                Button("Cancel",action:onClose)
                Spacer()
                Button("Confirm locations") {
                    error=recorder.resolveDeferredLocations(points,identities:records.map(\.id))
                    if error==nil {onClose()}
                }.disabled(!current || records.isEmpty || points.count != records.count)
            }
        }.padding(20).frame(width:600).onAppear {
            load()
            if let p=initialDestination,records.indices.contains(selected) {points[records[selected].number]=p.row*recorder.game.boardSize+p.col}
        }
    }
}
