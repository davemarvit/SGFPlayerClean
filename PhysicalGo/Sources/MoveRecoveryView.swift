import SwiftUI

/// The camera snapshot and draft stay fixed while the user supplies chronology.
/// Nothing enters the recorder until the whole proposal is approved.
struct MoveRecoveryView:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    @State var draft:MoveRecoveryDraft
    var initialSelection:BoardPosition?=nil
    var onApproved:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var error:String?
    @State private var colorOverride:BoardPosition?
    @State private var approved=false
    @State private var initialized=false
    private var remainingDetections:Int {
        InterpretationDetectionMarks.make(board:draft.board,observation:draft.observation,size:draft.baseGame.boardSize)
            .filter{$0.kind == .untracked}.count
    }
    private func select(_ point:BoardPosition?,checkColor:Bool=true) {
        error=draft.add(point,checkCameraColor:checkColor)
        colorOverride=error?.contains("camera sees") == true ? point:nil
    }
    var body:some View {
        VStack(spacing:12) {
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    Text("Order missed moves").font(.title2.bold())
                    Text("Clock and recording are paused. Click the missing stones in the order they were played, then choose Accept below. For a captured stone, click its former intersection.")
                    if draft.retainedMoveCount>0 {
                        Text("\(draft.retainedMoveCount) previously tracked moves were preselected. Keep their numbered order before adding later moves.").font(.callout)
                    }
                    Text("Selection \(draft.moves.count+1) · \(draft.nextPlayer.rawValue.capitalized) next")
                        .font(.title3.bold())
                    HStack {
                        Button("Undo selection",systemImage:"arrow.uturn.backward") {draft.undo();error=nil;colorOverride=nil}.disabled(draft.moves.isEmpty)
                        Button("Clear order") {draft.clear();error=nil;colorOverride=nil}.disabled(draft.moves.isEmpty)
                        Spacer()
                        Button("\(draft.nextPlayer.rawValue.capitalized) passed") {select(nil)}
                    }
                    if let error {Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
                    if let point=colorOverride {
                        Button("Camera color is wrong — use \(draft.nextPlayer.rawValue)") {select(point,checkColor:false)}
                    }
                    RecordedBoard(recorder:recorder,orientation:orientation,showsLivePosition:true,
                                  observation:draft.observation,allowsLiveSelection:true,
                                  boardOverride:draft.board,numberedMoves:draft.moves) {select($0)}
                        .frame(width:540,height:540)
                    if !draft.moves.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(draft.moves.enumerated()),id:\.offset) {offset,point in
                                    let first=draft.baseGame.moves.last?.0.opponent ?? draft.baseGame.initialPlayer ?? .black
                                    let color=offset%2==0 ? first:first.opponent
                                    Text("\(offset+1) · \(color.rawValue.capitalized)\(point == nil ? " pass":"")")
                                        .padding(6).background(.secondary.opacity(0.1),in:RoundedRectangle(cornerRadius:6))
                                }
                            }
                        }
                    }
                    Text("\(draft.moves.count) selected · \(remainingDetections) other camera detections. Only the numbered moves will be saved, starting at move \(draft.baseGame.moves.count+1).")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("The camera snapshot stays fixed while you order moves. Its colors can be corrected; the saved game still enforces legal play.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
            Divider()
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(recorder.clock.enabled ? "Accept \(draft.moves.count) moves & review clocks…":"Accept \(draft.moves.count) moves") {
                    error=recorder.approveRecovery(draft)
                    guard error == nil else {return}
                    approved=true;onApproved();dismiss()
                }.buttonStyle(.borderedProminent).disabled(draft.moves.isEmpty || approved)
            }
        }.padding(20).frame(width:580,height:780)
            .onAppear {
                guard !initialized else {return};initialized=true
                if let initialSelection,!draft.moves.contains(initialSelection) {select(initialSelection)}
            }
    }
}
