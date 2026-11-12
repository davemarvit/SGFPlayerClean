import SwiftUI

struct LiveIssueSelection:Identifiable {let id=UUID();let point:Int;let position:String;var observed:Occupancy?=nil}

/// Inspection never takes ownership of the recording or the clock lifecycle.
struct LiveIssueReviewView:View {
    @ObservedObject var recorder:GameRecorder
    let selection:LiveIssueSelection
    let orientation:BoardOrientation
    let onCorrect:(Int)->Void
    let onClose:()->Void
    @State private var result:String?
    private var current:Bool {
        selection.position==recorder.issuePositionSignature && recorder.adjustmentIssues[selection.point] != nil &&
            (selection.observed.map{$0==recorder.discrepancyObservation(at:selection.point)} ?? true)
    }
    private var acknowledged:Bool {recorder.positionAcknowledgments[selection.point] != nil}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(acknowledged ? "Check recognition":"Check the current disagreement").font(.title2.bold())
            Text(current ? "The camera and retained position disagree here. A covered, moved, or removed stone can explain this; it does not establish an incorrect saved move.":"This issue resolved or the position changed while the review was open. Return to the live position for current actions.")
            if let observed=selection.observed,(0..<recorder.game.boardSize*recorder.game.boardSize).contains(selection.point) {
                let point=selection.point,size=recorder.game.boardSize
                let coordinate=BoardCoordinates.name(point:point,size:size,orientation:orientation)
                Text("Camera reported \(observed.rawValue) at \(coordinate); the saved position records \(recorder.positions.last?.grid[point/size][point%size]?.rawValue ?? "empty").").font(.callout)
            }
            RecordedBoard(recorder:recorder,orientation:orientation,boardOverride:recorder.positions.last,
                highlightedPoints:[selection.point],highlightColor:.orange,showsLastMoveMarker:false,onPoint:{_ in})
                .frame(width:440,height:440)
            if acknowledged {
                Text("You confirmed the recorded position. Clear hands, glare, and obstructions so recognition can check again. If a physical correction interrupts play, use Pause before moving stones.")
            }
            Text("Inspection keeps tracking active and preserves any existing clock hold.").font(.callout)
            if let result {Text(result)}
            HStack {
                Button("Close",action:onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Recorded position is correct") {
                    result=recorder.acknowledgeRecordedPosition(point:selection.point,position:selection.position,observed:selection.observed)
                        ?? "Recorded position confirmed. No moves or clock balances changed."
                }.disabled(!current || acknowledged)
            }
            if let number=HistoricalMoveCorrection.moveNumber(at:.init(selection.point/recorder.game.boardSize,selection.point%recorder.game.boardSize),through:recorder.moveCount,game:recorder.game,positions:recorder.positions) {
                Button("Preview a correction to move \(number)…") {onCorrect(number)}.disabled(!current)
            }
            Button("Pause for physical correction") {recorder.pause()}.disabled(!current || recorder.state == .paused)
        }.padding(20).frame(width:550)
    }
}

struct AutomaticCaptureInspection:View {
    @ObservedObject var recorder:GameRecorder
    let orientation:BoardOrientation
    let onReview:()->Void
    @Environment(\.dismiss) private var dismiss
    private func coordinates(_ points:Set<Int>)->String {
        points.sorted().map{BoardCoordinates.name(point:$0,size:recorder.game.boardSize,orientation:orientation)}.joined(separator:", ")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Capture progress").font(.title2.bold())
            if let capture=recorder.captureProgressPlan {
                Text("Capturing move: \(capture.color.rawValue) at \(coordinates([capture.point])).")
                Text("Captured intersections: \(coordinates(capture.captured)).")
                let remaining=Set(recorder.captureProgressRemaining ?? [])
                Text(remaining.isEmpty ? "Removal appears complete; keep hands clear for verification.":"Still to verify empty: \(coordinates(remaining)).")
                Text(recorder.automaticCaptureStatus ?? "Remove the captured stones, keeping the capturing stone in place. The configured clock policy remains in effect.")
            } else {
                Text("This capture completed or changed. Return to the live position for current actions.")
            }
            Text("Inspection preserves the clock policy and any existing pause. Closing this view does not pause or resume play.")
            HStack {
                Button("Close") {dismiss()}
                if recorder.automaticCaptureStatus != nil {
                    Button("Stop automatic completion and review…") {dismiss();onReview()}
                }
            }
        }.padding(24).frame(width:520)
    }
}
