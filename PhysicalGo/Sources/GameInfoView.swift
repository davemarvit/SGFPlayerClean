import SwiftUI

struct GameInfoView:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    @State private var draft=SGFGame.Info()
    @State private var error=""
    @State private var loading=false
    @State private var onlineSize:Int?
    @State private var onlineHandicap:Int?
    private var online:Bool {model.playMode == .online}
    private func loadLocal() {
        draft=recorder.hasGame ? recorder.game.info:model.newGameInfo
        error=""
    }
    private func save() {
        guard !online else {return}
        let komi=(draft.komi ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if !komi.isEmpty,Double(komi)?.isFinite != true {error="Enter a number for komi, such as 6.5.";return}
        error=""
        if recorder.hasGame {recorder.updateInfo(draft)} else {draft.rules=model.newGameInfo.rules;draft.komi=model.newGameInfo.komi;model.newGameInfo=draft}
    }
    private func field(_ key:WritableKeyPath<SGFGame.Info,String?>)->Binding<String> {
        Binding(get:{draft[keyPath:key] ?? ""},set:{draft[keyPath:key]=$0;save()})
    }
    private var date:Binding<Date> {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd"
        return Binding(get:{formatter.date(from:draft.date ?? "") ?? Date()},set:{draft.date=SGFGame.Info.formattedGameDate($0);save()})
    }
    var body:some View {
        GroupBox("Game info") {
            VStack(alignment:.leading,spacing:14) {
                if online {
                    Text("Online names, komi and results come from OGS. Change online game settings in SGF Player / OGS.")
                        .foregroundStyle(.secondary)
                    Button(loading ? "Loading…":"Load online game info") {
                        loading=true;error=""
                        Task { @MainActor in
                            defer {loading=false}
                            do {
                                let download=try await PhysicalSGFExport.download()
                                guard online else {return}
                                let game=SGFGame.from(tree:try SGFParser.parse(text:String(decoding:download.data,as:UTF8.self)))
                                draft=game.info;onlineSize=game.boardSize;onlineHandicap=game.handicap
                            } catch {self.error=error.localizedDescription}
                        }
                    }.disabled(loading)
                } else {
                    Text(recorder.hasGame ? "Changes are saved in this game's SGF automatically." : "Details for your next recording. Today's date is filled in; komi defaults to 6.5.")
                        .foregroundStyle(.secondary)
                }
                Form {
                    TextField("Black player",text:field(\.playerBlack))
                    TextField("Black rank",text:field(\.blackRank))
                    TextField("White player",text:field(\.playerWhite))
                    TextField("White rank",text:field(\.whiteRank))
                    if recorder.hasGame || online {TextField("Komi",text:field(\.komi))}
                    if online {TextField("Date",text:field(\.date))}
                    else {DatePicker("Date",selection:date,displayedComponents:.date)}
                    TextField("Event",text:field(\.event))
                    TextField("Result",text:field(\.result))
                    Text("Leave the result blank until known. Examples: B+R, W+3.5, or 0 for a draw.")
                        .font(.caption).foregroundStyle(.secondary)
                    if recorder.hasGame || online {
                        LabeledContent("Rules",value:draft.rules ?? "Not specified")
                        LabeledContent("Handicap",value:online ? onlineHandicap.map {$0>0 ? "\($0) stones":"None"} ?? "Not loaded" : recorder.game.handicap>0 ? "\(recorder.game.handicap) stones":"None")
                    }
                    LabeledContent("Board",value:"\(online ? (onlineSize ?? model.size) : recorder.hasGame ? recorder.game.boardSize:model.size) × \(online ? (onlineSize ?? model.size) : recorder.hasGame ? recorder.game.boardSize:model.size)")
                }.disabled(online)
                DisclosureGroup("Camera recovery") {
                    VStack(alignment:.leading,spacing:6) {
                        Toggle("Speak when the camera, board, or lighting needs adjusting",isOn:$model.recoverySpeechEnabled)
                        Text("Asks for the whole board to be visible or for better lighting when automatic recovery needs help. Brief lighting changes stay quiet. Repeated frames do not repeat the prompt. Uses the clock's voice and volume settings.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
                }
                if !online {
                    DisclosureGroup(recorder.hasGame ? "Next game rules & clock":"Rules & clock") {
                        NewGameSettings(model:model).padding(6)
                    }
                    if recorder.hasGame && !recorder.clock.enabled && model.newGameClock.kind != .none {
                        Button("Use this clock from the current position") {recorder.attachClock(model.newGameClock)}
                            .disabled(recorder.state != .paused || recorder.pendingMoveCount>0 || model.newGameClock.validationError != nil)
                        Text("Pause recording first. Earlier moves remain untimed; the clock starts when recording resumes.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("AI scoring & power use") {PhysicalAnalysisStatus(analysis:model.scoring.background)}
                    DisclosureGroup("Recording feedback") {
                        Picker("Sound",selection:$model.soundMode) {
                            ForEach(ExperimentModel.RecordingSounds.allCases,id:\.self) {Text($0.label).tag($0)}
                        }
                    }
                    DisclosureGroup("Clock sounds and pause behavior") {LocalClockSoundControls(clock:recorder.clock)}
                    if recorder.hasGame {Text("These settings apply to New game, not the current recording.").font(.caption).foregroundStyle(.secondary)}
                }
                if !error.isEmpty {Text(error).foregroundStyle(.red)}
                if let error=recorder.saveError,!online {Text(error).foregroundStyle(.red)}
            }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
        }
        .onAppear {if !online {loadLocal()}}
        .onChange(of:recorder.autosaveURL) {_,_ in if !online {loadLocal()}}
        .onChange(of:model.playMode) {_,_ in if online {draft=SGFGame.Info();onlineSize=nil;onlineHandicap=nil;error=""} else {loadLocal()}}
    }
}

private struct PhysicalAnalysisStatus:View {
    @ObservedObject var analysis:PhysicalBackgroundAnalysis
    var body:some View {
        GroupBox("AI scoring") {
            VStack(alignment:.leading,spacing:6) {
                Text(analysis.status)
                Text("Background analysis stops within a second of switching to battery. Score game works on either power source. Captures are recorded automatically, even with the AI off.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
        }
    }
}
