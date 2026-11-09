import SwiftUI
import AVFoundation

@MainActor struct LocalPlayPresentation {
    struct Correction {
        let id:UUID
        let title:String
        let guidance:String
    }
    let correction:Correction?
    let automaticHold:Bool
    let title:String
    init(recorder:GameRecorder,clock:LocalGameClock) {
        if !clock.running,recorder.state != .finished,let plan=recorder.pendingCaptureReview {
            correction=Correction(id:plan.id,title:"Finish capture…",
                guidance:"The capturing move has not been saved. Choose Finish capture to verify the removal and confirm it, then Resume. Clocks stay stopped until then.")
        } else if !clock.running,recorder.state != .finished,let plan=recorder.pendingBoardRestoration {
            correction=Correction(id:plan.id,title:"Check moved stones…",
                guidance:"The physical board needs checking against the saved position. Choose Check moved stones before resuming the clocks.")
        } else {correction=nil}
        automaticHold = [.recording,.verifying].contains(recorder.state) &&
            clock.enabled && !clock.running && !clock.requiresReview && !recorder.synchronized && correction==nil
        if let correction {title=correction.title.replacingOccurrences(of:"…",with:"")+" · clocks stopped"}
        else if recorder.awaitingFirstStart && recorder.state == .paused {title="Ready to start"}
        else if recorder.state == .finished {title="Game finished"}
        else if recorder.state == .paused {title="Game paused"}
        else if automaticHold {title="Waiting for board · clocks stopped"}
        else if clock.enabled && !clock.running {title="Clocks paused"}
        else if !recorder.synchronized {title="Checking board"}
        else {title="Playing"}
    }
}

struct LocalPlayHeading:View {
    @ObservedObject var recorder:GameRecorder
    @ObservedObject var clock:LocalGameClock
    var body:some View {
        let state=LocalPlayPresentation(recorder:recorder,clock:clock)
        Text(state.title).font(.largeTitle.bold()).foregroundStyle(state.automaticHold ? Color.orange:Color.primary)
    }
}

struct LocalClockSettingsView:View {
    @Binding var settings:LocalClockSettings
    private func number(_ title:String,_ key:WritableKeyPath<LocalClockSettings,Int>)->some View {
        HStack {
            Text(title);Spacer()
            TextField(title,value:Binding(get:{settings[keyPath:key]},set:{settings[keyPath:key]=$0}),format:.number.grouping(.never))
                .frame(width:90).multilineTextAlignment(.trailing).accessibilityLabel(title)
        }
    }
    private func duration(_ title:String,_ key:WritableKeyPath<LocalClockSettings,Int>)->some View {
        HStack {
            Text(title);Spacer()
            TextField("Minutes",value:Binding(get:{settings[keyPath:key]/60},set:{settings[keyPath:key]=min(10080,max(0,$0))*60+max(0,settings[keyPath:key]%60)}),format:.number.grouping(.never))
                .frame(width:55).multilineTextAlignment(.trailing).accessibilityLabel(title+" minutes")
            Text("min").foregroundStyle(.secondary)
            TextField("Seconds",value:Binding(get:{settings[keyPath:key]%60},set:{settings[keyPath:key]=max(0,settings[keyPath:key]/60)*60+min(59,max(0,$0))}),format:.number.grouping(.never))
                .frame(width:45).multilineTextAlignment(.trailing).accessibilityLabel(title+" seconds")
            Text("sec").foregroundStyle(.secondary)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Picker("Clock",selection:$settings.kind) {
                ForEach(LocalClockSettings.Kind.allCases,id:\.self) {Text($0.label).tag($0)}
            }
            if settings.kind != .none {
                if settings.kind != .simple {duration(settings.kind == .fischer ? "Initial time":"Main time",\.mainSeconds)}
                switch settings.kind {
                case .byoyomi:
                    duration("Time per period",\.periodSeconds)
                    number("Byoyomi periods",\.periods)
                case .canadian:
                    duration("Time per overtime block",\.periodSeconds)
                    number("Moves per overtime block",\.stonesPerPeriod)
                case .fischer:
                    duration("Increment",\.incrementSeconds)
                    duration("Maximum time",\.maximumSeconds)
                case .simple:duration("Time per move",\.periodSeconds)
                default:EmptyView()
                }
                Text(settings.summary).font(.caption).foregroundStyle(.secondary)
                Text("The clock starts after the starting board is verified. A recognized legal move or Pass switches it to the other player.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error=settings.validationError {Text(error).foregroundStyle(.red)}
        }
    }
}

struct LocalClockSoundControls:View {
    @ObservedObject var clock:LocalGameClock
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Toggle("Pause clock when the camera is interrupted",isOn:$clock.pauseOnInterruption)
            Toggle("Quiet beep when a move switches the clock",isOn:$clock.sounds.moveBeep)
            Toggle("Beep every second",isOn:$clock.sounds.tickEverySecond)
            Toggle("Beep during the final 10 seconds",isOn:$clock.sounds.tickFinalTen)
            Toggle("Speak the final 10 seconds",isOn:$clock.sounds.speakFinalTen)
            Toggle("Announce overtime and periods remaining",isOn:$clock.sounds.announcePeriods)
            Toggle("Announce 1:30 remaining without byoyomi",isOn:$clock.sounds.announceNinety)
            Toggle("Sound when time expires",isOn:$clock.sounds.timeoutSound)
            HStack {Text("Volume");Slider(value:$clock.sounds.volume,in:0...1).frame(maxWidth:240)}
            Picker("Voice",selection:$clock.sounds.voiceID) {
                Text("Amelia · Kokoro (included)").tag("")
                Text("System English voice").tag(KokoroSpeech.systemVoiceID)
                ForEach(AVSpeechSynthesisVoice.speechVoices().filter {$0.language.hasPrefix("en")},id:\.identifier) {voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                }
            }
            Text("Kokoro works offline. Countdown audio is cached; the speech model loads only when needed.").font(.caption).foregroundStyle(.secondary)
            Button("Preview voice") {clock.testSound()}
        }.toggleStyle(.checkbox)
    }
}

struct LocalClockPanel:View {
    @ObservedObject var clock:LocalGameClock
    @ObservedObject var recorder:GameRecorder
    var large=false
    var onReview:(UUID)->Void = {_ in}
    @State private var expanded=false
    @State private var correction=false
    @State private var resumeAfterReview=false
    private func review(resume:Bool) {
        recorder.pause();clock.pause("Clock paused for review")
        resumeAfterReview=resume;correction=true
    }
    var body:some View {
        let presentation=LocalPlayPresentation(recorder:recorder,clock:clock)
        VStack(alignment:.leading,spacing:large ? 18:8) {
            HStack {
                Text(clock.engine.settings.kind.label).font(large ? .title:.headline)
                Text(clock.engine.settings.summary).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !large {
                    Menu("Clock options") {
                        Button("Large clock") {expanded=true}
                        Button("Adjust clocks…") {review(resume:false)}.disabled(recorder.state == .finished)
                    }.fixedSize()
                }
                if large {
                    Button("\((recorder.liveNextPlayer ?? recorder.nextPlayer).rawValue.capitalized) pass") {recorder.pass()}.disabled(!recorder.canPass)
                }
                if large {Button("Adjust clocks…") {review(resume:false)}.disabled(recorder.state == .finished)}
            }
            HStack(spacing:16) {
                side(black:true)
                side(black:false)
            }
            transport
            if recorder.needsTurnConfirmation,presentation.correction==nil {LiveTurnPrompt(recorder:recorder)}
            if let note=clock.timingNote {
                DisclosureGroup("Earlier clock timing") {Text(note).font(.callout)}
            }
            if let pause=clock.automaticPause,!clock.running,recorder.state != .finished {
                ClockPauseFeedback(pause:pause,paused:recorder.state == .paused,
                    pendingMoves:recorder.pendingMoveCount,requiresReview:clock.requiresReview,awaitingTurn:clock.awaitingTurn,
                    correctionGuidance:presentation.correction?.guidance,boardStatus:recorder.synchronized ? nil:recorder.status)
            } else if let correction=presentation.correction {
                Text(correction.guidance).font(.callout).foregroundStyle(.orange)
            } else {
                Text(clock.notice).font(large ? .title2:.headline)
                    .foregroundStyle(clock.needsCorrection || clock.engine.expiredBlack != nil ? Color.red:clock.running ? Color.primary:Color.orange)
                    .frame(maxWidth:.infinity,alignment:.leading)
            }
            if clock.requiresReview {
                Text("Choose Review & resume to check both times. You can keep the displayed times or enter corrections agreed by both players.").font(.callout)
            }
            if let error=clock.saveError {Text(error).foregroundStyle(.red)}
            if large {
                Text("Move recognition switches the clock automatically. Use the recording controls to pass. Countdown numbers show seconds remaining; byoyomi counts include the current period.")
                    .foregroundStyle(.secondary)
                Text("Clock and sound settings are under Info.").foregroundStyle(.secondary)
            }
        }.padding(large ? 24:12)
            .background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:14))
            .sheet(isPresented:$expanded) {
                VStack {
                    HStack {Spacer();Button("Close large clock") {expanded=false}.keyboardShortcut(.cancelAction)}.padding([.top,.horizontal])
                    LocalClockPanel(clock:clock,recorder:recorder,large:true,onReview:onReview)
                }.frame(minWidth:960,minHeight:540)
            }
            .sheet(isPresented:$correction) {LocalClockCorrection(clock:clock,recorder:recorder,resumeAfterReview:resumeAfterReview)}
    }
    // One shared transport: recognizing a move, not pressing this button,
    // switches players. Keep the clock-review gate on every resume path.
    private var transport:some View {
        let presentation=LocalPlayPresentation(recorder:recorder,clock:clock)
        let waiting=presentation.automaticHold,correction=presentation.correction
        let reviewing = !clock.running && clock.requiresReview
        let pausing = !reviewing && (clock.running || recorder.state == .recording)
        let title = correction?.title ?? (waiting ? "Pause checking" : pausing ? "Pause" : reviewing ? "Review & resume…" : recorder.awaitingFirstStart ? "Start" : "Resume")
        return HStack {
            Spacer(minLength:0)
            Button {
                if let correction {onReview(correction.id)}
                else if waiting || pausing {
                    recorder.pause();clock.pause("Clock and recording paused")
                } else if clock.requiresReview {
                    review(resume:true)
                } else {
                    clock.requestResume()
                    if recorder.state == .paused {recorder.resume()}
                    else if recorder.synchronized {clock.resume()}
                }
            } label: {
                HStack(spacing:14) {
                    Image(systemName:correction != nil ? "checkmark.circle.fill":waiting ? "hourglass.circle.fill":pausing ? "pause.circle.fill":"play.circle.fill")
                        .font(.system(size:large ? 56:44,weight:.semibold))
                    VStack(alignment:.leading,spacing:2) {
                        Text(title).font(.system(size:large ? 28:24,weight:.semibold))
                        Text(waiting || correction != nil ? "Clocks stay stopped":"Clock & recording").font(.callout)
                    }
                    if reviewing {Image(systemName:"exclamationmark.triangle.fill").font(.title2)}
                }.padding(.horizontal,20).padding(.vertical,8)
                    .frame(minWidth:250,minHeight:64)
                    .contentShape(Rectangle())
            }.buttonStyle(.borderedProminent).tint(reviewing ? .red:waiting || correction != nil ? .orange:.accentColor)
                .actionAttention(reviewing || correction != nil ? .required:.none)
                .disabled(!waiting && !clock.running && ![.recording,.paused].contains(recorder.state))
                .accessibilityLabel(correction?.title ?? (waiting ? "Pause board checking and keep clocks stopped":reviewing ? "Review clocks and resume" : pausing ? "Pause clock and recording":recorder.awaitingFirstStart ? "Start game and clocks":"Resume clock and recording"))
                .help(correction?.guidance ?? (waiting ? "Clocks are stopped while the board is checked. Pause checking prevents automatic resumption when the view recovers.":reviewing ? "Check both times before resuming." : "Pauses or resumes both the clock and recording. Recognized moves switch players automatically."))
            Spacer(minLength:0)
        }.padding(.vertical,4)
    }
    private func side(black:Bool)->some View {
        let state=black ? clock.engine.black:clock.engine.white
        let active = !recorder.needsTurnConfirmation && clock.engine.blackToPlay==black
        let urgent=active && state.remaining<=10
        let player=black ? recorder.game.info.playerBlack:recorder.game.info.playerWhite
        let count=recorder.recordedMoveCount(for:black ? .black:.white)
        let countLabel=recorder.moveCountsNeedReview
            ? "\(count) recorded \(count==1 ? "move":"moves") · review pending"
            : "\(count) \(count==1 ? "move":"moves") played"
        return VStack(spacing:8) {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Circle().fill(black ? Color.black:Color.white).overlay(Circle().stroke(.gray,lineWidth:1)).frame(width:22,height:22)
                Text((black ? "Black":"White")+(player.map{ $0.isEmpty ? "":" · "+$0 } ?? "")).font(.system(size:large ? 28:22,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(recorder.needsTurnConfirmation ? (LocalPlayPresentation(recorder:recorder,clock:clock).correction != nil ? "REVIEW PENDING":"CONFIRM TURN"):active ? (recorder.awaitingFirstStart ? "READY":clock.running ? "TO PLAY":"PAUSED"):"Waiting").font(.headline)
            }
            Text(LocalClockEngine.display(state.remaining))
                .font(.system(size:large ? 180:160,weight:.bold,design:.rounded)).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(urgent ? Color.red:Color.primary)
                .accessibilityLabel("\(black ? "Black":"White") time \(LocalClockEngine.display(state.remaining))")
            Text(detail(state)).font(.system(size:large ? 32:28,weight:.medium)).lineLimit(2,reservesSpace:true).minimumScaleFactor(0.7)
            if clock.engine.settings.kind == .byoyomi {
                ByoyomiPeriodBars(settings:clock.engine.settings,side:state,active:active,large:large)
                    .accessibilityLabel("\(black ? "Black":"White") byoyomi periods")
            }
        }.padding(large ? 24:20).frame(maxWidth:.infinity,alignment:.leading)
            .background(active ? (urgent ? Color.red:Color.accentColor).opacity(0.15):Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(active ? (urgent ? Color.red:Color.accentColor):Color.clear,lineWidth:urgent ? 4:3))
            Text(countLabel).font(.system(size:large ? 24:20,weight:.medium)).monospacedDigit()
                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth:.infinity)
                .accessibilityLabel("\(black ? "Black":"White"): \(countLabel)")
                .help("Includes passes and excludes handicap setup stones. Captures do not reduce the count. Unresolved sequences are included after review.")
        }.frame(maxWidth:.infinity)
    }
    private func detail(_ side:LocalClockEngine.Side)->String {
        let settings=clock.engine.settings
        switch settings.kind {
        case .byoyomi:
            if side.overtime && side.remaining<=0 {return "Byoyomi · no periods left\nTime expired"}
            if side.overtime && side.periods==1 {return "Byoyomi · Final period\n\(settings.periodSeconds)s per move"}
            return side.overtime ? "Byoyomi · \(side.periods) \(side.periods==1 ? "period":"periods") left\nIncludes this \(settings.periodSeconds)s period" : "Main time\nThen \(side.periods) × \(settings.periodSeconds)s byoyomi"
        case .canadian:return side.overtime ? "Overtime\n\(side.stones) moves left in this block":"Main time\nThen \(settings.stonesPerPeriod) moves in \(settings.periodSeconds)s"
        case .fischer:return "+\(settings.incrementSeconds)s after each move\nMaximum \(LocalClockEngine.display(Double(settings.maximumSeconds)))"
        case .simple:return "Per move\nNew \(settings.periodSeconds)s allowance each turn"
        case .absolute:return "Main time\nNo overtime"
        case .none:return "Untimed"
        }
    }
}

struct LocalClockCorrection:View {
    @ObservedObject var clock:LocalGameClock
    @ObservedObject var recorder:GameRecorder
    var resumeAfterReview=false
    @Environment(\.dismiss) private var dismiss
    @State private var black=LocalClockEngine.Side(remaining:1,overtime:false,periods:1,stones:1)
    @State private var white=LocalClockEngine.Side(remaining:1,overtime:false,periods:1,stones:1)
    @State private var selectedTurn:Stone = .black
    private var valid:Bool {clock.canCorrect(black:black,white:white)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(resumeAfterReview ? "Review clocks before resuming":"Adjust clocks").font(.title2.bold())
            Text("Check both times and overtime allowances. Keep them unchanged if both players agree, or edit them below. The next player follows the live board.")
            if resumeAfterReview {Text("Confirming resumes recording. The clock waits for the physical board to be verified.").font(.callout)}
            else {Text("Clocks stay paused after saving.").font(.callout)}
            if recorder.hasDeferredMoves {
                Picker("Next player",selection:$selectedTurn) {
                    Text("Black").tag(Stone.black);Text("White").tag(Stone.white)
                }
            }
            fields("Black",side:$black);fields("White",side:$white)
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(resumeAfterReview ? "Confirm times & resume":"Save clock correction") {
                    guard recorder.confirmClockReview(black:black,white:white,resume:resumeAfterReview,turn:recorder.hasDeferredMoves ? selectedTurn:nil) else {return}
                    dismiss()
                }.disabled(!valid).keyboardShortcut(.defaultAction)
            }
            if !valid {Text("Enter positive time for both players and valid overtime allowances before continuing.").foregroundStyle(.red)}
        }.padding(24).frame(width:520)
            .onAppear {black=clock.engine.black;white=clock.engine.white;selectedTurn=recorder.liveNextPlayer ?? (clock.engine.blackToPlay ? .black:.white)}
    }
    private func fields(_ label:String,side:Binding<LocalClockEngine.Side>)->some View {
        GroupBox(label) {
            VStack(alignment:.leading) {
                HStack {Text("Seconds remaining");TextField("Seconds",value:side.remaining,format:.number)}
                if [.byoyomi,.canadian].contains(clock.engine.settings.kind) {Toggle("In overtime",isOn:side.overtime)}
                if clock.engine.settings.kind == .byoyomi {Stepper(side.wrappedValue.periods==1 ? "Final period":"\(side.wrappedValue.periods) periods left (including current)",value:side.periods,in:1...clock.engine.settings.periods)}
                if clock.engine.settings.kind == .canadian {Stepper("\(side.wrappedValue.stones) moves left",value:side.stones,in:1...clock.engine.settings.stonesPerPeriod)}
            }.padding(6)
        }
    }
}

/// Retain the initiating cause separately from the changing recovery status.
struct ClockPauseFeedback:View {
    let pause:LocalGameClock.AutomaticPause
    let paused:Bool
    let pendingMoves:Int
    let requiresReview:Bool
    let awaitingTurn:Bool
    var correctionGuidance:String?=nil
    var boardStatus:String?=nil
    var nextStep:String {
        if let correctionGuidance {return correctionGuidance}
        if requiresReview {return "Choose Review & resume to check both times before continuing."}
        if awaitingTurn {return "Choose Black or White above to confirm whose turn it is."}
        if pendingMoves>0 {
            let moves=pendingMoves==1 ? "the unconfirmed move":"the \(pendingMoves) unconfirmed moves"
            return paused ? "Press Resume to recheck \(moves). Keep the stones in place."
                : "Resume requested. Waiting to confirm \(moves); the clocks resume after verification. Check Live position below for highlighted intersections and instructions."
        }
        return paused ? "Press Resume when the whole board is visible and the camera is steady. The clocks start after verification."
            : "Checking the board. The clocks resume after verification. Choose Pause checking if you are not ready."
    }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Label("Clocks stopped automatically",systemImage:"pause.circle.fill").font(.headline).foregroundStyle(.orange)
            if correctionGuidance == nil {Text("Why it stopped: \(pause.reason)").font(.callout)}
            Text(nextStep).font(.callout).fontWeight(.medium)
            if correctionGuidance==nil,!requiresReview,!awaitingTurn,let boardStatus,!boardStatus.isEmpty {
                Text(boardStatus).font(.callout)
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading).padding(12)
        .background(Color.orange.opacity(0.12),in:RoundedRectangle(cornerRadius:8))
        .accessibilityElement(children:.combine)
    }
}
