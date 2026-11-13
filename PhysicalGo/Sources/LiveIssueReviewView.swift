import SwiftUI

struct LiveIssueSelection:Identifiable {let id=UUID();let point:Int;let position:String;var observed:Occupancy?=nil}

enum LiveIssueReviewStatus:CaseIterable {
    case disagreement,centering,acknowledged,resolved,changed
    var title:String {
        switch self {
        case .disagreement:return "Check the current disagreement"
        case .centering:return "Check stone centering"
        case .acknowledged:return "Check recognition"
        case .resolved:return "RESOLVED"
        case .changed:return "POSITION CHANGED"
        }
    }
    var message:String {
        switch self {
        case .disagreement:return "The camera and retained position disagree here. A covered, moved, or removed stone can explain this; it does not establish an incorrect saved move."
        case .centering:return "The camera sees a stone between intersections near this recorded point. If it was bumped, center it on the recorded intersection. Review a correction only if the saved location is wrong."
        case .acknowledged:return "You confirmed the recorded position. Clear hands, glare, and obstructions so recognition can check again."
        case .resolved:return "The camera now agrees with the recorded stone at this intersection. No correction is needed."
        case .changed:return "New evidence or a changed game position has made this review out of date. Close it and check Live position."
        }
    }
    var actionable:Bool {self == .disagreement || self == .centering || self == .acknowledged}
}

/// Inspection never takes ownership of the recording or the clock lifecycle.
struct LiveIssueReviewView:View {
    @ObservedObject var recorder:GameRecorder
    let selection:LiveIssueSelection
    let orientation:BoardOrientation
    let onCorrect:(Int)->Void
    let onClose:()->Void
    @State private var result:String?
    var status:LiveIssueReviewStatus {
        guard selection.position==recorder.issuePositionSignature,
              (0..<recorder.game.boardSize*recorder.game.boardSize).contains(selection.point) else {return .changed}
        let observed=recorder.discrepancyObservation(at:selection.point)
        if recorder.adjustmentIssues[selection.point] != nil {
            guard selection.observed.map({$0==observed}) ?? true else {return .changed}
            return acknowledged ? .acknowledged:recorder.adjustmentIssues[selection.point] == .centering ? .centering:.disagreement
        }
        // A changed or unavailable view is not a successful resolution. The
        // recorder clears a marker only after repeated fresh agreement.
        if let stone=recorder.positions.last?.grid[selection.point/recorder.game.boardSize][selection.point%recorder.game.boardSize],
           observed?.stone==stone {return .resolved}
        return .changed
    }
    private var current:Bool {status.actionable}
    private var acknowledged:Bool {recorder.positionAcknowledgments[selection.point] != nil}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            // All variants participate in layout. Only the current one is
            // visible/accessibility-readable, so the board never shifts when
            // the title or explanation changes, including acknowledgment.
            ZStack(alignment:.leading) {
                ForEach(LiveIssueReviewStatus.allCases,id:\.self) {value in
                    Text(value.title).font(value == .resolved ? .largeTitle.bold():.title2.bold())
                        .foregroundStyle(value == .resolved ? Color.green:Color.primary)
                        .opacity(status==value ? 1:0).accessibilityHidden(status != value)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            ZStack(alignment:.topLeading) {
                ForEach(LiveIssueReviewStatus.allCases,id:\.self) {value in
                    Text(value.message).frame(maxWidth:.infinity,alignment:.leading)
                        .opacity(status==value ? 1:0).accessibilityHidden(status != value)
                }
            }.fixedSize(horizontal:false,vertical:true)
            if let observed=selection.observed,(0..<recorder.game.boardSize*recorder.game.boardSize).contains(selection.point) {
                let point=selection.point,size=recorder.game.boardSize
                let coordinate=BoardCoordinates.name(point:point,size:size,orientation:orientation)
                Text("Original camera report: \(observed.rawValue) at \(coordinate); saved position: \(recorder.positions.last?.grid[point/size][point%size]?.rawValue ?? "empty").").font(.callout)
            }
            RecordedBoard(recorder:recorder,orientation:orientation,boardOverride:recorder.positions.last,
                highlightedPoints:current ? [selection.point]:[],highlightColor:.orange,showsLastMoveMarker:false,onPoint:{_ in})
                .frame(width:440,height:440)
            Text("Inspection keeps tracking active and preserves any existing clock hold.").font(.callout)
            Text(result ?? "Recorded position confirmed. No moves or clock balances changed.")
                .opacity(result == nil ? 0:1).accessibilityHidden(result == nil)
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
