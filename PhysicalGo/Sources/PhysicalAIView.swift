import SwiftUI
import AppKit

struct PhysicalAISetupView: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var ai: PhysicalAI
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("Board",selection:$ai.draft.size) {ForEach([9,13,19],id:\.self) {Text("\($0) × \($0)").tag($0)}}
                    .onChange(of:ai.draft.size) {_,size in if model.size != size {model.size=size;model.boardSizeChanged()}}
                Picker("You play",selection:$ai.draft.humanBlack) {Text("Black · first").tag(true);Text("White · AI first").tag(false)}
                }
            HStack {
                Picker("Opponent",selection:Binding(get:{ai.draft.humanRank != nil},set:{ai.draft.humanRank=$0 ? "5k":nil})) {
                    Text("Human rank").tag(true);Text("Search effort").tag(false)
                }.pickerStyle(.segmented)
                if ai.draft.humanRank != nil {
                    Picker("KGS-style rank · approximate",selection:Binding(get:{ai.draft.humanRank ?? "5k"},set:{ai.draft.humanRank=$0})) {
                        ForEach(PhysicalAISettings.ranks,id:\.self) {Text(PhysicalAISettings.rankLabel($0)).tag($0)}
                    }
                } else {
                    Picker("AI strength",selection:$ai.draft.strength) {ForEach(PhysicalAISettings.Strength.allCases,id:\.self) {Text($0.title).tag($0)}}
                }
            }
            HStack {
                Picker("Rules",selection:$ai.draft.rules) {Text("Japanese").tag("Japanese");Text("Chinese").tag("Chinese")}
                TextField("Komi",value:$ai.draft.komi,format:.number).frame(width:100)
                Text("Komi").foregroundStyle(.secondary)
                Spacer()
                Text("Elapsed-time practice").foregroundStyle(.secondary)
            }
            Text(ai.draft.humanRank != nil ? "HumanSL’s rank profiles use KGS as their reference. They are approximate practice levels, not certified Pandanet, Japanese, AGA or EGF ranks. High-dan profiles may play weaker; smaller boards have less training evidence." : "KataGo runs on this Mac. Search effort changes thinking depth, not a calibrated kyu/dan rank; even Quick can be strong.")
                .font(.callout).foregroundStyle(.secondary)
            if ai.draft.humanRank != nil {
                DisclosureGroup("Which ranking system?") {
                    VStack(alignment:.leading,spacing:6) {
                        Text("KataGo’s standard profiles imitate KGS players. Cross-system surveys are small, self-reported snapshots; differences depend on rank and date. There is no verified conversion from a HumanSL opponent to an AGA, Pandanet or Japanese rank.")
                        Link("KataGo’s KGS profile definition",destination:URL(string:"https://github.com/lightvector/KataGo/blob/v1.18.2/cpp/neuralnet/sgfmetadata.cpp#L196-L214")!)
                        Link("2024 server and association rank survey",destination:URL(string:"https://forums.online-go.com/t/go-rankings-survey-feb-2024/50803")!)
                        Link("2020 survey, including Japan",destination:URL(string:"https://ntust-mitlab.github.io/go-rank-survey-2020/go-rank-survey-results-2020")!)
                    }.font(.callout).padding(.top,6)
                }
            }
            Text("Play your stones on the physical board. Place the AI’s stones at the blue ring and remove captures. The camera confirms the board before the next turn.")
            PhysicalCalibrationProgressView()
            PhysicalAILaserControls(laser:ai.laser)
            PhysicalAICenteringControls(ai:ai)
        }.disabled(ai.hasGame && ai.phase != .finished)
        PhysicalAIMoveClickControls(click:model.aiMoveClick)
        PhysicalAITestModeControls(ai:ai)
        PhysicalAIPracticeControls(ai:ai,orientation:model.orientation) {size in
            if model.size != size {model.size=size;model.boardSizeChanged()}
        }
    }
}

struct PhysicalAIPlayView: View {
    @ObservedObject var ai: PhysicalAI
    let orientation: BoardOrientation
    var boardHeight:CGFloat=480
    var cameraNotice:String?=nil
    var moveClick:PhysicalAIMoveClick?=nil
    var practiceBoardSizeChanged:((Int)->Void)?=nil
    @State private var ending=false
    @State private var confirmingLaserOff=false
    @State private var exportError: String?
    private func coordinate(_ p: Int)->String {
        let displayed=PhysicalMoveInference.displayedPoint(row:p/ai.size,col:p%ai.size,size:ai.size,quarterTurns:orientation.turns)
        return "\(Array("ABCDEFGHJKLMNOPQRST")[displayed%ai.size])\(ai.size-displayed/ai.size)"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading) {
                    Text(ai.snapshot?.practiceTest.map {"Test position · "+$0.position.title} ?? "Play AI · KataGo").font(.title2.bold())
                    Text(ai.snapshot?.settings.opponentDescription ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if ai.phase == .thinking {ProgressView().controlSize(.small)}
                Text("Move \(ai.snapshot?.moves.count ?? 0)").monospacedDigit()
            }
            if ai.hasGame {PhysicalAIClockPanel(ai:ai)}
            if let point=ai.placementGuidancePoint {
                Label("Place \(ai.human.opponent.rawValue.capitalized) at \(coordinate(point))",systemImage:"scope")
                    .font(.title.bold()).foregroundStyle(.blue)
            }
            if let point=ai.captureGuidancePoint {
                Label("Remove captured stone at \(coordinate(point)) · \(ai.remainingCapturedStones) remaining",systemImage:"minus.circle")
                    .font(.title.bold()).foregroundStyle(.orange)
            }
            PhysicalCalibrationProgressView()
            PhysicalAILaserControls(laser:ai.laser,clockRunning:ai.timing.anchor != nil)
            if ai.centeringStone != nil {
                Label("Center the highlighted stone on the intersection you intended",systemImage:"scope").foregroundStyle(.orange)
            }
            Text(ai.status).font(.title3).accessibilityIdentifier("ai-game-status")
            if let cameraNotice {
                VStack(alignment:.leading,spacing:4) {
                    if ai.phase == .thinking {Text("Your move was accepted. AI is thinking.")}
                    if ai.phase == .placing {Text("Your move was accepted. Place the AI stone at the blue ring.")}
                    Text(cameraNotice)
                }.foregroundStyle(.orange)
            }
            if let error=ai.error {Text(error).foregroundStyle(.red).textSelection(.enabled)}
            if ai.hasGame {
                HStack {
                    if ai.phase == .paused,ai.snapshot?.guidanceInterruption != nil {
                        Button("Continue without laser") {confirmingLaserOff=true}
                    }
                    Button("Pass") {ai.pass()}.disabled(!ai.canPass)
                    Button("End game…") {ending=true}.disabled(ai.phase == .finished)
                    Spacer()
                    Button("Save SGF file") {export()}
                }
                board.frame(maxWidth:650,maxHeight:boardHeight).frame(maxWidth:.infinity)
                if let issue=ai.mismatch {
                    Text("Match the board: \(issue.remove.map{coordinate($0)}.joined(separator:", "))\(issue.remove.isEmpty ? "":" — remove marked stones. ")\(issue.place.map{coordinate($0)}.joined(separator:", "))\(issue.place.isEmpty ? "":" — place required stones.")")
                        .foregroundStyle(.orange)
                }
                Text("Center dot: last move. Blue ring: AI move to place. Red ×: remove or correct. Games save automatically; two passes finish without assigning a score.").font(.caption).foregroundStyle(.secondary)
            } else {Text("Choose your settings in Setup, then Start AI game.")}
            DisclosureGroup("Timing, sound & practice options") {
                VStack(alignment:.leading,spacing:12) {
                    Text("Elapsed time · your clock starts when the AI move arrives, including aiming and placement. Captures of two or more stones pause the clock until placement and capture removal are confirmed. Single-stone captures keep the clock running.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let moveClick {PhysicalAIMoveClickControls(click:moveClick)}
                    PhysicalAICenteringControls(ai:ai)
                    PhysicalAITestModeControls(ai:ai)
                    PhysicalAIPracticeControls(ai:ai,orientation:orientation,boardSizeChanged:practiceBoardSizeChanged)
                }.padding(.top,8)
            }
            if let exportError {Text(exportError).foregroundStyle(.red)}
        }
        .confirmationDialog("Switch the laser’s physical power switch OFF",isPresented:$confirmingLaserOff,titleVisibility:.visible) {
            Button("I switched it off") {ai.confirmLaserPhysicallyOff()}
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("Keep the stones in place. A fresh clear camera view is required before Resume. This confirmation does not claim the driver acknowledged OFF or clear its fault.")
        }
        .confirmationDialog("End this AI game?",isPresented:$ending,titleVisibility:.visible) {
            Button("Resign") {ai.finish(resign:true)}
            Button("End without a result") {ai.finish()}
            Button("Cancel",role:.cancel) {}
        }
    }
    private var board: some View {
        Canvas {context,extent in
            let size=ai.size,step=min(extent.width,extent.height)/CGFloat(size+1),inset=step
            func center(_ index: Int)->CGPoint {
                let p=PhysicalMoveInference.displayedPoint(row:index/size,col:index%size,size:size,quarterTurns:orientation.turns)
                return CGPoint(x:inset+CGFloat(p%size)*step,y:inset+CGFloat(p/size)*step)
            }
            func stoneCenter(_ point:ImagePoint)->CGPoint {
                let n=Double(size-1),x=point.x,y=point.y
                let p:ImagePoint
                switch ((orientation.turns%4)+4)%4 {
                case 1:p = .init(x:n-y,y:x)
                case 2:p = .init(x:n-x,y:n-y)
                case 3:p = .init(x:y,y:n-x)
                default:p=point
                }
                return .init(x:inset+CGFloat(p.x)*step,y:inset+CGFloat(p.y)*step)
            }
            var lines=Path()
            for i in 0..<size {
                let p=inset+CGFloat(i)*step
                lines.move(to:.init(x:inset,y:p));lines.addLine(to:.init(x:inset+CGFloat(size-1)*step,y:p))
                lines.move(to:.init(x:p,y:inset));lines.addLine(to:.init(x:p,y:inset+CGFloat(size-1)*step))
            }
            context.stroke(lines,with:.color(.black.opacity(0.65)),lineWidth:1)
            // Shared Go labels cover all four edges. Rotate their canonical
            // anchors with the stones while keeping the glyphs upright.
            let labelMargin=min(0.72,max(0,1-8/Double(step)))
            for label in BoardCoordinates.labels(size:size,orientation:orientation,margin:labelMargin) {
                context.draw(Text(label.text).font(.system(size:11)).foregroundColor(.black),at:stoneCenter(label.grid))
            }
            for i in ai.cells.indices {
                let c=center(i),rect=CGRect(x:c.x-step*0.45,y:c.y-step*0.45,width:step*0.9,height:step*0.9)
                if ai.cells[i] != "empty" {
                    context.fill(Path(ellipseIn:rect),with:.color(ai.cells[i]=="black" ? .black:.white))
                    context.stroke(Path(ellipseIn:rect),with:.color(.black.opacity(0.5)),lineWidth:1)
                    if i==ai.snapshot?.moves.last?.point {
                        let radius=step*0.12
                        let dot=CGRect(x:c.x-radius,y:c.y-radius,width:radius*2,height:radius*2)
                        context.fill(Path(ellipseIn:dot),with:.color(ai.cells[i]=="black" ? .white:.black))
                    }
                }
                if i==ai.placementGuidancePoint || ai.mismatch?.place.contains(i) == true {
                    context.stroke(Path(ellipseIn:rect),with:.color(.blue),lineWidth:4)
                }
                if i==ai.captureGuidancePoint {
                    context.stroke(Path(ellipseIn:rect),with:.color(.orange),lineWidth:4)
                }
                if ai.mismatch?.remove.contains(i) == true {
                    var cross=Path();let r=step*0.25
                    cross.move(to:.init(x:c.x-r,y:c.y-r));cross.addLine(to:.init(x:c.x+r,y:c.y+r))
                    cross.move(to:.init(x:c.x+r,y:c.y-r));cross.addLine(to:.init(x:c.x-r,y:c.y+r))
                    context.stroke(cross,with:.color(.red),lineWidth:4)
                }
            }
            if let stone=ai.centeringStone {
                let c=stoneCenter(stone),r=step*0.55
                context.stroke(Path(ellipseIn:.init(x:c.x-r,y:c.y-r,width:2*r,height:2*r)),with:.color(.orange),lineWidth:4)
            }
        }.aspectRatio(1,contentMode:.fit).background(Color(red:0.82,green:0.65,blue:0.4))
        .accessibilityLabel("AI game board. \(ai.snapshot?.moves.last?.point.map {"Last move at \(coordinate($0)), marked with a contrasting center dot. "} ?? "")\(ai.status)")
    }
    private func export() {
        guard let snapshot=ai.snapshot else {return}
        let panel=NSSavePanel();panel.nameFieldStringValue="KataGo practice.sgf";panel.allowedContentTypes=[.init(filenameExtension:"sgf") ?? .plainText]
        guard panel.runModal() == .OK,let url=panel.url else {return}
        do {try PhysicalAI.sgf(snapshot).write(to:url,atomically:true,encoding:.utf8);exportError=nil}
        catch {exportError=error.localizedDescription}
    }
}

struct PhysicalAITestModeControls:View {
    @ObservedObject var ai:PhysicalAI
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Toggle("Fast AI test mode",isOn:Binding(get:{ai.fastTestMode},set:{ai.setFastTestMode($0)}))
                .disabled(!ai.canChangeTestMode)
            Text(ai.fastTestMode ? "Quick replies for equipment testing. Overrides opponent strength; the first reply may take longer to load." : "Use quick AI replies for equipment testing. Pause the game to change this setting.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PhysicalAICenteringControls:View {
    @ObservedObject var ai:PhysicalAI
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            Toggle("Laser centering hints",isOn:$ai.centeringEnabled).toggleStyle(.switch).fixedSize()
            if ai.centeringEnabled {
                Text("A small wiggle marks the observed stone, without choosing its intersection. Center it where you intended. Hand entry turns the light off; opponent moves take priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PhysicalAILaserControls: View {
    @ObservedObject var laser: PhysicalLaserGuidance
    var clockRunning:Bool?=nil
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack {
                Toggle("Connect laser bridge",isOn:Binding(get:{laser.enabled},set:{laser.setEnabled($0)}))
                    .toggleStyle(.switch).fixedSize()
                if laser.enabled,laser.suppressed || laser.holdingInterrupted || laser.gameFaultNeedsRecheck {
                    Button(laser.controllerResetRequired ? "Recheck after reset":laser.holdingInterrupted || laser.gameFaultNeedsRecheck ? "Retry laser":"Show point again") {laser.showAgain()}
                }
            }
            if laser.enabled {
                Toggle("Keep motors ready during play",isOn:Binding(get:{laser.standbyEnabled},set:{laser.setStandbyEnabled($0)}))
                    .toggleStyle(.switch)
                if laser.standbyEnabled {
                    Text(laser.standbyAvailable ? "Active games only. Motors cool automatically; pausing releases them.":"Waiting for a driver with monitored motor holding.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(laser.motorMessage).font(.caption)
                    Text(laser.temperatureMessage).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if laser.controllerResetRequired {
                Text("Controller stopped; reset required. Reset the controller and verify calibration before continuing. Rechecking does not reset the controller.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(laser.message).font(.caption).foregroundStyle(.secondary)
            if laser.recoveringCamera || laser.interrupted {
                Label(laser.recoveringCamera ? "Laser temporarily off — restoring the pending move":"Laser stopped — the AI move still needs placement",systemImage:"exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text(clockRunning == true ? "Your clock is running. The blue ring shows where to place the AI stone.":"The blue ring shows where to place the AI stone.")
                    .font(.callout)
            }
            if laser.enabled {
                Text("Requires a commissioned laser driver. Hand entry turns the light off; the camera must still verify the stone. The screen marker remains available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Explicit, reversible synthetic positions. No hardware enable command is issued.
struct PhysicalAIPracticeControls:View {
    @ObservedObject var ai:PhysicalAI
    let orientation:BoardOrientation
    var boardSizeChanged:((Int)->Void)?=nil
    @State private var choice:PhysicalAIPracticePosition?
    @State private var confirmingLoad=false
    @State private var confirmingReturn=false
    private var returnTitle:String {ai.snapshot?.practiceTest?.previousGameID == nil ? "Return to setup":"Return to saved game"}
    private func coordinate(_ p:Int)->String {
        let displayed=PhysicalMoveInference.displayedPoint(row:p/19,col:p%19,size:19,quarterTurns:orientation.turns)
        return "\(Array("ABCDEFGHJKLMNOPQRST")[displayed%19])\(19-displayed/19)"
    }
    @ViewBuilder private func detail(_ position:PhysicalAIPracticePosition)->some View {
        if !position.moves.isEmpty {
            Text("Initial setup — Black: "+position.black.map(coordinate).joined(separator:", ")+" · White: "+position.white.map(coordinate).joined(separator:", "))
            if let next=position.nextMove {
                Text("Then play Black at \(coordinate(next)); remove White at \(position.prisoners.map(coordinate).joined(separator:", ")).")
            }
        }
        Text(position.clockDetail)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            if let test=ai.snapshot?.practiceTest {
                Text("Test position · "+test.position.title).font(.headline)
                Text("Synthetic practice · 19 × 19 · "+(ai.fastTestMode ? "Fast test mode":"Standard AI mode")+". Your prior game is preserved separately.").font(.caption).foregroundStyle(.secondary)
                detail(test.position).font(.callout)
                Button(returnTitle) {confirmingReturn=true}.disabled(!ai.canReturnFromPracticePosition)
                if ai.active {Text("Pause the test before returning.").font(.caption).foregroundStyle(.secondary)}
            } else {
                DisclosureGroup("Practice tests") {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Your current game is preserved before loading a separate test position. Tests start paused; arrange the board, then Resume for normal verification. Laser settings are not enabled by loading a test.")
                        ForEach(PhysicalAIPracticePosition.allCases) {position in
                            VStack(alignment:.leading,spacing:3) {
                                Button(position.title) {choice=position;confirmingLoad=true}.disabled(!ai.canLoadPracticePosition)
                                detail(position).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !ai.canLoadPracticePosition {Text("Pause the game before loading a practice test.").font(.caption)}
                    }.padding(.top,6)
                }
            }
            if let error=ai.practiceError {Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)}
        }
        .confirmationDialog("Load test position?",isPresented:$confirmingLoad,titleVisibility:.visible) {
            Button("Load test position") {
                if let choice,ai.loadPracticePosition(choice) {boardSizeChanged?(ai.size)}
            }
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("\(choice?.title ?? "Practice test"). Your saved game and elapsed clocks will be backed up. The new test stays paused until you arrange the board and Resume.")
        }
        .confirmationDialog(returnTitle+"?",isPresented:$confirmingReturn,titleVisibility:.visible) {
            Button(returnTitle) {if ai.returnFromPracticePosition() {boardSizeChanged?(ai.size)}}
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("The current test is archived. Your previous game or setup is restored with its elapsed clocks. Match the board before resuming an unfinished game.")
        }
    }
}
