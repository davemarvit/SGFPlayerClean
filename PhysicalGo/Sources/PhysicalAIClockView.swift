import SwiftUI

struct PhysicalAIPlayHeading:View {
    @ObservedObject var ai:PhysicalAI
    private var title:String {
        switch ai.phase {
        case .idle:return "Ready for a game?"
        case .checking:return "Checking board"
        case .human:return "Playing"
        case .thinking:return "KataGo is thinking"
        case .placing:return ai.clockPausedForCaptureCleanup ? "Removing captured stones":"Place the AI move"
        case .paused:return "Game paused"
        case .finished:return "Game finished"
        case .failed:return "Game needs attention"
        }
    }
    var body:some View {Text(title).font(.largeTitle.bold())}
}

/// Matches the local two-player clock panel while retaining AI practice's
/// elapsed-time policy. All controls call the existing game lifecycle methods.
struct PhysicalAIClockPanel:View {
    @ObservedObject var ai:PhysicalAI
    var large=false
    @AppStorage("PhysicalGo.clockSidesSwitched") private var sidesSwitched=false
    @State private var expanded=false
    var body:some View {
        VStack(alignment:.leading,spacing:large ? 18:8) {
            HStack {
                Text("Elapsed practice time").font(large ? .title:.headline)
                Spacer()
                Menu("Clock options") {
                    Button("Switch sides",systemImage:"arrow.left.arrow.right") {sidesSwitched.toggle()}
                        .help("Swap the left and right clock displays to match where you sit.")
                    if !large {Button("Large clock") {expanded=true}}
                }.fixedSize()
            }
            TimelineView(.periodic(from:.now,by:0.5)) { _ in
                let now=ProcessInfo.processInfo.systemUptime
                HStack(spacing:16) {
                    side(black:!sidesSwitched,at:now)
                    side(black:sidesSwitched,at:now)
                }
            }
            HStack(spacing:16) {
                summary(black:!sidesSwitched)
                transport.fixedSize(horizontal:true,vertical:false)
                summary(black:sidesSwitched)
            }
            if large {Text(ai.status).font(.title2)}
            if ai.clockPausedForCaptureCleanup {
                Label("Clock paused for capture cleanup",systemImage:"pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("Complete the move and remove the captured stones.").font(.callout)
            }
        }.padding(large ? 24:12)
            .background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:14))
            .sheet(isPresented:$expanded) {
                VStack {
                    HStack {Spacer();Button("Close large clock") {expanded=false}.keyboardShortcut(.cancelAction)}
                        .padding([.top,.horizontal])
                    PhysicalAIClockPanel(ai:ai,large:true)
                    Text("Elapsed time counts up. Your clock starts when the AI move arrives, including aiming and placement.")
                        .foregroundStyle(.secondary).padding([.horizontal,.bottom])
                }.frame(minWidth:960,minHeight:540)
            }
    }
    private func side(black:Bool,at now:Double)->some View {
        PhysicalAIClockFace(black:black,human:(ai.human == .black)==black,
            time:LocalClockEngine.display(ai.timing.elapsed(black:black,at:now)),
            selected:ai.timing.blackToPlay==black,running:ai.timing.anchor != nil,
            finished:ai.phase == .finished,large:large)
    }
    private func summary(black:Bool)->some View {
        let total=ai.snapshot?.moves.count ?? 0
        let count=black ? (total+1)/2:total/2
        return Text("\(count) \(count==1 ? "move":"moves") played")
            .font(.system(size:large ? 24:13,weight:.medium)).monospacedDigit()
            .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth:.infinity)
            .accessibilityLabel("\(black ? "Black":"White"): \(count) moves played")
            .help("Includes passes and the AI’s committed move awaiting physical placement.")
    }
    private var transport:some View {
        let pausing=ai.active
        let title=pausing ? "Pause":ai.phase == .failed ? "Retry":ai.phase == .finished ? "Finished":"Resume"
        return Button {
            if pausing {ai.pause()} else {ai.resume()}
        } label: {
            HStack(spacing:14) {
                Image(systemName:pausing ? "pause.circle.fill":"play.circle.fill")
                    .font(.system(size:large ? 56:28,weight:.semibold))
                VStack(alignment:.leading,spacing:2) {
                    Text(title).font(.system(size:large ? 28:20,weight:.semibold))
                    Text("Game & elapsed time").font(.callout)
                }
            }.padding(.horizontal,12).padding(.vertical,4)
                .frame(minWidth:210,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.borderedProminent)
            .disabled(!pausing && ai.phase != .paused && ai.phase != .failed)
            .accessibilityLabel(pausing ? "Pause AI game and elapsed clocks":"\(title) AI game and elapsed clocks")
            .help("Recognized moves and AI decision receipt switch players automatically. This control pauses or resumes the game.")
    }
}
