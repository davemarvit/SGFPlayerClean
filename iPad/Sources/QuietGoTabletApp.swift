import SwiftUI

@main struct QuietGoTabletApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            UserDefaults.standard.set(false, forKey: "tablet3D")
            UserDefaults.standard.set(PlayingEnvironment.gardenRoom.rawValue, forKey: "tabletEnvironment")
        }
    }
    @StateObject private var game = TabletGame(restore: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
    var body: some Scene { WindowGroup { TabletContentView(game:game) } }
}
struct TabletContentView: View {
    @ObservedObject var game: TabletGame
    @StateObject private var analysis = TabletAnalysis()
    @ObservedObject private var preferences = AppSettings.shared
    @State private var playing = false
    @State private var playbackSeconds = 2.0
    private let playbackClock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var playbackElapsed = 0.0
    @Environment(\.scenePhase) private var phase
    @AppStorage("tablet3D") private var use3D = false
    @AppStorage("tabletEnvironment") private var environmentName = PlayingEnvironment.gardenRoom.rawValue
    @State private var lastAnalysisID = ""
    @State private var library=false
    @State private var importing=false
    @State private var exporting=false
    @State private var newGame=false
    @State private var settings=false
    @State private var recenter=0
    @State private var showingDetails=false
    @State private var panelExpanded = true
    private var environment:PlayingEnvironment { PlayingEnvironment(rawValue:environmentName) ?? .gardenRoom }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700 && geometry.size.width > geometry.size.height
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !wide { header(wide: false) }
                    // Stable scene identity preserves the camera across rotation and panel changes.
                    board(portrait: geometry.size.height >= geometry.size.width)
                    if !wide { compactFooter }
                }
                if wide {
                    Divider()
                    if panelExpanded { sidebar.frame(width: 260) }
                    else { compactRail.frame(width: 112) }
                }
            }
            .background(Color(red:0.12,green:0.15,blue:0.14))
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $library) { TabletLibrary(game: game) }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.sgf,.plainText,.data]) { result in
            switch result { case .success(let url):game.open(url); case .failure(let error):game.error=error.localizedDescription }
        }
        .fileExporter(isPresented:$exporting,document:SGFDocument(text:game.exportedSGF),contentType:.sgf,defaultFilename:game.title) { result in
            if case .failure(let error)=result { game.error=error.localizedDescription }
        }
        .onChange(of:game.positionID) { _,_ in
            analysis.cancel()
            if preferences.analysisEnabled { analysis.restore(game.player) }
            if game.mode == .review, game.canAnalyze, lastAnalysisID != game.tree.baseAnalysisID {
                lastAnalysisID = game.tree.baseAnalysisID
                analysis.analyzeGame(game)
            }
        }
        .onChange(of: preferences.analysisEnabled) { _, enabled in
            if enabled { analysis.restore(game.player) } else { analysis.suspend() }
        }
        .onReceive(playbackClock) { _ in
            guard playing, phase == .active, !game.isOnline, game.scoring == nil else { playing = false; return }
            playbackElapsed += 0.5
            if playbackElapsed >= playbackSeconds {
                playbackElapsed = 0
                if game.tree.neighbor(direction: 1) != nil { game.step(1) } else { playing = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in analysis.suspend() }
        .sheet(isPresented: Binding(get: { game.isOnline && game.online?.showLobby == true }, set: { game.online?.showLobby = $0 })) {
            if let online = game.online { TabletOnlineLobby(online: online, client: online.client) }
        }
        .onOpenURL { game.open($0) }
        .onChange(of:phase) { _,value in
            if value == .background { playing = false; analysis.suspend(); game.player.pause(); game.persist(); game.online?.suspend() }
            else if value == .active { game.online?.resume() }
            else { analysis.cancel() }
        }
        .onChange(of: game.canAnalyze) { _,allowed in if !allowed { analysis.cancel() } }
        .alert("Quiet Go",isPresented:Binding(get:{game.error != nil},set:{if !$0 {game.error=nil}})) { Button("OK") {game.error=nil} } message: { Text(game.error ?? "") }
        .confirmationDialog("Start a new game? This game will be kept in Saved Games in Files.",isPresented:$newGame,titleVisibility:.visible) {
            ForEach([9,13,19],id:\.self) { size in Button("New \(size) × \(size) game") {game.newGame(size:size)} }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView { details }
                    .navigationTitle("Game details")
                    .toolbar { Button("Done") { showingDetails = false } }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: game.scoring != nil) { _, scoring in if scoring { showingDetails = false; playing = false; analysis.cancel() } }
        .sheet(isPresented:$settings) {
            NavigationStack {
                Form {
                    Toggle("Enable analysis", isOn: $preferences.analysisEnabled)
                    Picker("Environment",selection:$environmentName) { ForEach(PlayingEnvironment.allCases,id:\.rawValue) { e in Text(e.title).tag(e.rawValue) } }.accessibilityIdentifier("environmentPicker")
                    Text("3D: use two fingers to orbit, pinch to zoom, and three fingers to pan. Tap an intersection to place a stone directly. Apple Pencil works too. You can also twist two fingers to rotate. Entering 3D or changing environments plays a short camera tour. Touch the scene to skip it; that touch will not place a stone. Recenter glides back to the board.")
                    Text("KataGo runs offline on this iPad using the CPU. Quick analysis stops after 16 visits or about eight seconds of search. The first analysis also loads the model. Online play connects to Online-Go.com. AI is unavailable while playing online or while this account has an ongoing game.").foregroundStyle(.secondary)
                }.navigationTitle("Board settings").toolbar { Button("Done") {settings=false} }
            }.presentationDetents([.medium,.large])
        }
    }
    private func openOnline(observing: Bool = false) {
        analysis.suspend()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--online-ui-testing") {
            if TabletOnlineFixture.current == nil { TabletOnlineFixture.current = TabletOnlineFixture() }
            if ProcessInfo.processInfo.arguments.contains("--observe-ui-testing") { TabletOnlineFixture.current!.observingFixture = true }
            game.startOnline(client: TabletOnlineFixture.current!.client, observing: observing)
            return
        }
        #endif
        game.startOnline(observing: observing)
    }
    private func selectMode(_ mode: TabletMode) {
        guard game.mode != mode else { return }
        playing = false
        analysis.cancel()
        switch mode {
        case .playOnline: openOnline()
        case .observe: openOnline(observing: true)
        case .localPlay, .review: game.selectLocalMode(mode)
        }
    }
    private func modeButton(_ mode: TabletMode) -> some View {
        Button { selectMode(mode) } label: {
            Text(mode.rawValue).font(.subheadline.weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(game.mode == mode ? Color.white.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode.identifier)
        .accessibilityValue(game.mode == mode ? "Selected" : "")
        .accessibilityAddTraits(game.mode == mode ? .isSelected : [])
    }
    private func modes(side: Bool) -> some View {
        Group {
            if side {
                VStack(spacing: 2) {
                    HStack(spacing: 2) { modeButton(.playOnline); modeButton(.localPlay) }
                    HStack(spacing: 2) { modeButton(.observe); modeButton(.review) }
                }
            } else {
                HStack(spacing: 2) { ForEach(TabletMode.allCases, id: \.self) { modeButton($0) } }
            }
        }
        .padding(3).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modeSelector")
    }
    @ViewBuilder private var chooseGame: some View {
        if game.mode == .review {
            Button("Choose game…") { library = true }.frame(minHeight: 44).accessibilityIdentifier("chooseGame")
        } else if game.isOnline {
            Button("Choose game…") { game.online?.browse(observing: game.mode == .observe) }
                .frame(minHeight: 44).accessibilityIdentifier("chooseGame")
        }
    }
    private func tools(wide: Bool) -> some View {
        HStack(spacing: 0) {
            gameMenu
            dimensionButton
            if use3D { environmentMenu; recenterButton }
            if wide {
                panelToggle
            }
        }.fixedSize()
    }
    private var panelToggle: some View {
        Button { panelExpanded.toggle() } label: {
            Image(systemName: "sidebar.right").frame(width: 44, height: 44)
        }.accessibilityLabel(panelExpanded ? "Hide controls" : "Show controls")
    }
    private var compactRail: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                ForEach(TabletMode.allCases, id: \.self) { modeButton($0) }
            }.padding(3).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                gameMenu; dimensionButton
                if use3D { environmentMenu; recenterButton }
            }
            chooseGame.font(.caption)
            if game.isOnline, let online = game.online { TabletOnlinePlayers(online: online) }
            Spacer(minLength: 0)
            if game.isOnline, let online = game.online {
                Text(online.status).font(.caption).multilineTextAlignment(.center).accessibilityIdentifier("onlineStatus")
            }
            Text("Move \(game.player.currentIndex)").font(.caption).monospacedDigit().accessibilityIdentifier("moveCount")
            if game.mode == .localPlay { placement }
            HStack(spacing: 0) { detailsButton; panelToggle }
        }.padding(6)
        .accessibilityElement(children: .contain).accessibilityIdentifier("compactRail")
    }
    private var dimensionButton: some View {
        Button { use3D.toggle() } label: { Text(use3D ? "2D" : "3D").frame(minWidth: 44, minHeight: 44) }
            .accessibilityIdentifier("toggle3D")
    }
    private var recenterButton: some View {
        Button { recenter += 1 } label: { Image(systemName: "viewfinder").frame(width: 44, height: 44) }
            .accessibilityLabel("Recenter board")
    }
    private var environmentMenu: some View {
        Menu {
            Picker("Environment", selection: $environmentName) {
                ForEach(PlayingEnvironment.allCases, id: \.rawValue) { e in Text(e.title).tag(e.rawValue) }
            }
        } label: {
            Image(systemName: "photo.on.rectangle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Environment")
        .accessibilityValue(environment.title)
        .accessibilityIdentifier("environmentMenu")
    }
    private var gameMenu: some View {
        Menu {
            Button("Open SGF", systemImage: "folder") { importing = true }.disabled(game.isOnline)
            Button("Export SGF", systemImage: "square.and.arrow.up") { exporting = true }.disabled(game.isOnline)
            Button("New game", systemImage: "plus") { newGame = true }.disabled(game.isOnline)
            Button("Board settings", systemImage: "slider.horizontal.3") { settings = true }
        } label: { Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44) }
            .accessibilityLabel("Game menu")
    }
    private func header(wide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                modes(side: false).frame(minWidth: 350)
                chooseGame
                tools(wide: wide)
            }
            VStack(spacing: 2) {
                modes(side: false)
                HStack { chooseGame; Spacer(); tools(wide: wide) }
            }
        }.padding(.horizontal, 8).padding(.vertical, 4)
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                modes(side: true)
                HStack { tools(wide: true); Spacer(minLength: 0) }
                chooseGame
            }.padding(8)
            Divider()
            ScrollView { details }.frame(maxHeight: .infinity)
            Divider()
            if !game.isOnline {
                navigation(compact: true).padding(.horizontal, 8)
                if game.mode == .localPlay { placement }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gameSidebar")
    }
    private func board(portrait: Bool) -> some View {
        Group {
            if use3D { TabletBoard3D(game:game,environment:environment,active:phase == .active && !settings,recenter:recenter) }
            else { TabletBoard2D(game:game, portrait: portrait) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var compactFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { footerStatus; Spacer(minLength: 0); footerActions(includeDetails: true) }
            VStack(spacing: 0) {
                HStack { footerStatus; Spacer(); detailsButton }
                HStack { footerActions(includeDetails: false); Spacer() }
            }
        }.font(.subheadline).padding(.horizontal, 8).padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compactControls")
    }
    @ViewBuilder private var footerStatus: some View {
        if game.isOnline, let online = game.online {
            TabletOnlinePlayers(online: online).frame(maxWidth: 320, alignment: .leading)
            Text(online.status).accessibilityIdentifier("onlineStatus")
            Text("Move \(game.player.currentIndex)").monospacedDigit().accessibilityIdentifier("moveCount")
        } else { compactStatus }
    }
    private var detailsButton: some View {
        Button { showingDetails = true } label: {
            Image(systemName: "info.circle").frame(width: 44, height: 44)
        }.accessibilityLabel("Details")
    }
    private func footerActions(includeDetails: Bool) -> some View {
        HStack(spacing: 4) {
            if !game.isOnline {
                navigation(compact: true)
                if game.mode == .localPlay { placement }
                Button {
                    if game.canAnalyze && !analysis.running { analysis.analyze(game.player) }
                    showingDetails = true
                } label: { Image(systemName: "sparkle.magnifyingglass").frame(width: 44, height: 44) }
                    .disabled(!game.canAnalyze).accessibilityLabel("Analyze position").accessibilityIdentifier("analyzePosition")
            }
            if includeDetails { detailsButton }
        }
    }
    private var compactStatus: some View {
        HStack(spacing: 12) {
            Circle().fill(game.player.turn == .black ? Color.black : .white)
                .overlay(Circle().stroke(.gray)).frame(width: 18, height: 18)
            Text("\(game.player.turn == .black ? "Black" : "White") to play")
            Text("Move \(game.player.currentIndex)").monospacedDigit().accessibilityIdentifier("moveCount")
        }.frame(minHeight: 44).fixedSize(horizontal: true, vertical: false)
    }
    private var details:some View {
        VStack(alignment:.leading,spacing:10) {
            if game.isOnline, let online = game.online { TabletOnlinePlayers(online: online, showClocks: true) }
            else { Text(game.title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack { Circle().fill(game.player.turn == .black ? Color.black : .white).overlay(Circle().stroke(.gray)).frame(width:18,height:18); Text("\(game.player.turn == .black ? "Black" : "White") to play").font(.headline); Spacer(); Text("Move \(game.player.currentIndex)").monospacedDigit().accessibilityIdentifier("moveCount") }
            VStack(alignment: .leading, spacing: 2) {
                Text("Black captured \(game.player.capturesByBlack) white \(game.player.capturesByBlack == 1 ? "stone" : "stones")")
                Text("White captured \(game.player.capturesByWhite) black \(game.player.capturesByWhite == 1 ? "stone" : "stones")")
            }.font(.caption).foregroundStyle(.secondary)
            if game.isOnline, let online = game.online {
                TabletOnlineDetails(online: online, client: online.client)
            } else if let scoring=game.scoring {
                Text("Agree on dead groups and neutral areas before using the score.").font(.subheadline)
                Picker("Mark",selection:Binding(get:{scoring.tool},set:{game.scoring?.tool=$0})) { ForEach(LocalScoringSession.Tool.allCases,id:\.self) {Text($0.rawValue).tag($0)} }.pickerStyle(.segmented)
                Picker("Rules",selection:Binding(get:{scoring.rule},set:{game.scoring?.rule=$0})) {ForEach(LocalScoringRule.allCases){Text($0.rawValue).tag($0)}}
                HStack {Text("Komi"); TextField("Komi",text:Binding(get:{scoring.komiText},set:{game.scoring?.komiText=$0})).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)}
                if let result=scoring.result { Text(result.winnerDescription(blackName:nil,whiteName:nil)).font(.headline) }
                if let issue=scoring.issue {Text(issue).font(.caption).foregroundStyle(.orange)}
                Button("Resume review / play") {game.scoring=nil}
            } else {
                TabletVariationTree(game: game)
                HStack {
                    Button(playing ? "Pause" : "Play") { playbackElapsed = 0; playing.toggle() }
                        .frame(minHeight: 44).accessibilityIdentifier("reviewPlayback")
                    Picker("Playback speed", selection: $playbackSeconds) {
                        Text("1 sec").tag(1.0); Text("2 sec").tag(2.0); Text("5 sec").tag(5.0)
                    }
                }
                if !game.currentNode.children.isEmpty {
                    Text("Continuations").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) { HStack {
                        ForEach(game.currentNode.children,id:\.self) { id in
                            let node=game.tree.nodes[id]
                            Button(node.isPass ? "Pass" : "\(node.color == .white ? "White" : "Black") \(node.label)") {game.select(id)}.buttonStyle(.bordered).frame(minHeight:44)
                        }
                    }}
                }
                HStack { Button("Previous variation") {if let id=game.tree.sibling(direction:-1){game.select(id)}}.disabled(game.tree.sibling(direction:-1)==nil); Button("Next variation") {if let id=game.tree.sibling(direction:1){game.select(id)}}.disabled(game.tree.sibling(direction:1)==nil) }.font(.caption)
                if let comment=game.currentNode.comment {Text(comment).font(.subheadline)}
                Divider()
                if preferences.analysisEnabled {
                if analysis.running || analysis.sweeping {
                    HStack { ProgressView(); Text("KataGo is thinking…"); Button("Stop") {analysis.cancel()} }
                } else {
                    Button("Analyze position") {if game.canAnalyze { analysis.analyze(game.player) }}.disabled(!game.canAnalyze).buttonStyle(.bordered).accessibilityIdentifier("analyzePosition")
                }
                Button("Analyze full game") { analysis.analyzeGame(game) }
                    .disabled(!game.canAnalyze || analysis.running || analysis.sweeping)
                    .frame(minHeight: 44).accessibilityIdentifier("analyzeFullGame")
                Button("Deepen position") { analysis.analyze(game.player, visits: 128) }
                    .disabled(!game.canAnalyze || analysis.running || analysis.sweeping).frame(minHeight: 44)
                TabletEvaluationView(game: game, analysis: analysis)
                if !game.canAnalyze { Text("AI is unavailable while your OGS account has an ongoing game.").font(.caption) }
                if let message=analysis.message {Text(message).font(.caption).foregroundStyle(.secondary)}
                if let result=analysis.result, let root=result.rootInfo {
                    Text("Black win chance \(Int((root.winrate*100).rounded()))% · \(root.visits) visits").font(.subheadline).accessibilityIdentifier("analysisResult")
                    Text("Estimated lead: \(root.scoreLead >= 0 ? "Black" : "White") \(abs(root.scoreLead),specifier:"%.1f") points").font(.caption)
                    ForEach(Array((result.moveInfos ?? []).prefix(3))) { move in
                        Button("\(move.move) · \(move.visits) visits") {
                            if let point=AIVariation.position(move.move,size:game.player.board.size) {game.tap(at: point)}
                        }.buttonStyle(.bordered)
                    }
                }
                }
                Button("Score position") {game.beginScoring()}.buttonStyle(.bordered)
            }
        }.padding(12)
    }
    private func navigation(compact: Bool = false) -> some View {
        HStack(spacing: compact ? 4 : 12) {
            Button {game.select(0)} label:{Image(systemName:"backward.end.fill").frame(width:44,height:44)}.accessibilityLabel("First move")
            Button {game.step(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.accessibilityLabel("Previous move")
            Text("\(game.player.currentIndex) / \(game.player.maxIndex)").monospacedDigit().frame(minWidth: compact ? 48 : 70)
            Button {game.step(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.accessibilityLabel("Next move")
            Button {if let id=game.tree.activePath.last{game.select(id)}} label:{Image(systemName:"forward.end.fill").frame(width:44,height:44)}.accessibilityLabel("Last move")
        }.disabled(game.scoring != nil)
    }
    private var placement: some View {
        Button("Pass") { game.play(pass: true) }
            .buttonStyle(.bordered).disabled(game.scoring != nil).frame(minHeight: 44)
    }
}
