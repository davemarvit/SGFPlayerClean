// MARK: - File: ActiveGamePanel.swift (v3.505)
import SwiftUI

struct ActiveGamePanel: View {
    @EnvironmentObject var app: AppModel
    @State private var showResignConfirmation = false
    @State private var resignTarget: Int?
    @State private var isSavingSGF = false
    @State private var exportError: String?
    @State private var physicalBoardEnabled = false
    @State private var physicalToken = UUID().uuidString
    @State private var physicalSentVersion: Int?
    @State private var physicalRevision = PhysicalBoardBridgeRevision()
    @State private var physicalLegalityKey = ""
    @State private var physicalIllegalMoves = [String:String]()
    @State private var physicalFeedback = [String:Any]()
    @State private var physicalRequestErrorRevision = 0
    @State private var physicalExportID: UUID?
    private var physicalDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Physical Go/Online Bridge")
    }
    private func physicalExportTick() {
        let requestURL=physicalDirectory.appendingPathComponent("sgf-request.json")
        guard let data=try? Data(contentsOf:requestURL),
              let request=try? JSONDecoder().decode(PhysicalSGFExportRequest.self,from:data) else {return}
        try? FileManager.default.removeItem(at:requestURL)
        guard request.matches(token:physicalToken,game:app.ogsClient.activeGameID) else {return}
        physicalExportID=request.id
        let token=physicalToken
        let replyURL=physicalDirectory.appendingPathComponent("sgf-result.json")
        app.ogsClient.fetchSGFDownload(gameID:request.game) { data,name in
            DispatchQueue.main.async {
                guard physicalExportID == request.id else {return}
                physicalExportID=nil
                let current=physicalBoardEnabled && token == physicalToken && app.ogsClient.activeGameID == request.game
                let reply=PhysicalSGFExportReply(id:request.id,game:request.game,data:current ? data:nil,
                    filename:name,error:!current ? "The connected game changed. Try saving again." : data == nil ? "OGS could not download this game's SGF. Try again." : nil)
                do {try JSONEncoder().encode(reply).write(to:replyURL,options:.atomic)}
                catch {exportError="Physical board SGF export: \(error.localizedDescription)"}
            }
        }
    }
    private func physicalTick() {
        guard physicalBoardEnabled else { return }
        let client = app.ogsClient
        let ready = client.canPlayMoves && app.player.currentIndex == app.player.maxIndex
        let board = app.player.board
        let cells = board.grid.flatMap { $0.map { $0?.rawValue ?? "empty" } }
        let version = physicalRevision.update(.init(
            game: client.activeGameID ?? -1, serverVersion: client.currentStateVersion,
            size: board.size, cells: cells, moveNumber: app.player.currentIndex,
            currentPlayerID: client.currentPlayerID, color: client.playerColor?.rawValue ?? "",
            lastX: app.player.lastMove?.x ?? -1, lastY: app.player.lastMove?.y ?? -1,
            ready: ready))
        let legalityKey="\(version)/\(String(describing:app.player.analysisSettings.playRules))"
        if physicalLegalityKey != legalityKey {
            physicalLegalityKey=legalityKey
            physicalIllegalMoves=[:]
            if ready,let color=client.playerColor {
                for y in 0..<board.size { for x in 0..<board.size where board.grid[y][x] == nil {
                    if let reason=app.player.moveRejection(color:color,x:x,y:y) {
                        physicalIllegalMoves[String(y*board.size+x)]=reason.rawValue
                    }
                } }
            }
        }
        if physicalFeedback["version"] as? Int != version {physicalFeedback=[:]}
        if physicalFeedback["status"] as? String == "submitted",
           let error=client.lastGameError,error.gameID==client.activeGameID,error.revision>physicalRequestErrorRevision {
            physicalFeedback["status"]="rejected";physicalFeedback["message"]="OGS: \(error.message)"
            physicalSentVersion=nil
        }
        let state: [String: Any] = ["token":physicalToken,"time":Date().timeIntervalSince1970,
            "sgfExport":true,"game":client.activeGameID ?? -1,"version":version,"size":board.size,"cells":cells,
            "ready":ready,"myTurn":client.currentPlayerID != nil && client.currentPlayerID == client.playerID,
            "color":client.playerColor?.rawValue ?? "", "lastX":app.player.lastMove?.x ?? -1,
            "lastY":app.player.lastMove?.y ?? -1,"illegalMoves":physicalIllegalMoves,"moveFeedback":physicalFeedback]
        do {
            try FileManager.default.createDirectory(at:physicalDirectory,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:state).write(to:physicalDirectory.appendingPathComponent("state.json"),options:.atomic)
            physicalExportTick()
            let requestURL = physicalDirectory.appendingPathComponent("move.json")
            guard let data = try? Data(contentsOf:requestURL),
                  let request = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
            try? FileManager.default.removeItem(at:requestURL)
            // Only requests from this bridge session can receive feedback.
            guard request["token"] as? String == physicalToken,
                  request["game"] as? Int == client.activeGameID else {return}
            let reply:[String:Any]=["id":request["id"] as? String ?? "","version":request["version"] as? Int ?? -1,
                "status":"rejected","message":"The game position changed before this move could be sent. Match the online board and try again."]
            guard ready, client.currentPlayerID == client.playerID,
                  request["token"] as? String == physicalToken,
                  request["game"] as? Int == client.activeGameID,
                  request["version"] as? Int == version, physicalSentVersion != version,
                  let stamp = request["time"] as? Double, abs(Date().timeIntervalSince1970-stamp)<3,
                  let x = request["x"] as? Int, let y = request["y"] as? Int,
                  (0..<board.size).contains(x), (0..<board.size).contains(y), board.grid[y][x] == nil else { physicalFeedback=reply; return }
            if let color=client.playerColor,let reason=app.player.moveRejection(color:color,x:x,y:y) {
                physicalFeedback=reply;physicalFeedback["message"]=reason.rawValue
                return
            }
            physicalSentVersion = version
            physicalFeedback=reply;physicalFeedback["status"]="submitted";physicalFeedback["message"]="Move submitted to OGS."
            physicalRequestErrorRevision=client.lastGameError?.revision ?? 0
            client.sendMove(gameID:client.activeGameID!,x:x,y:y)
        } catch { exportError = "Physical board connection: \(error.localizedDescription)" }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
            VStack(spacing: 12) {
                headerSection
                Toggle("Use physical board", isOn: $physicalBoardEnabled)
                    .help("Open Physical Go, choose Online play, and match the server position before placing your move.")
                if physicalBoardEnabled,physicalFeedback["status"] as? String == "rejected",
                   let reason=physicalFeedback["message"] as? String {
                    Label(reason,systemImage:"exclamationmark.triangle.fill").foregroundColor(.red)
                }
                if app.ogsClient.isGameFinished { resultBanner }
                
                Divider().background(Color.white.opacity(0.1))
                
                if app.ogsClient.isGameParticipant, let username = app.ogsClient.undoRequestedUsername {
                    undoApprovalSection(username: username)
                }
                
                playerInfoSection
                
                Divider().background(Color.white.opacity(0.1)).padding(.vertical, 8)
                
                // Chat Section (Always Visible)
                if let last = app.player.lastMove,
                   last.x == -1, last.y == -1,
                   !app.ogsClient.isGameFinished, !app.ogsClient.isScoringPhase {
                    let passedColor = last.color == .black ? "Black" : "White"
                    Text("\(passedColor) Passed")
                        .interfaceFont(.headline)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
                if let vm = app.ogsGame {
                    OGSChatView(gameVM: vm)
                        .frame(minHeight: 140, idealHeight: 200)
                        .cornerRadius(8)
                }
                
                if app.ogsClient.isGameFinished { controlButtons }
            }
            .padding()
            
            }
            controlsSection.padding([.horizontal, .bottom])
        }
        .task(id: physicalBoardEnabled) {
            guard physicalBoardEnabled else { return }
            while !Task.isCancelled {
                physicalTick()
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
            }
        }
        .onChange(of: physicalBoardEnabled) { _ in physicalToken = UUID().uuidString; physicalSentVersion = nil; physicalFeedback=[:];physicalLegalityKey="" }
        .onChange(of: app.ogsClient.activeGameID) { _ in
            cancelResignation(); exportError = nil; physicalBoardEnabled = false; physicalToken = UUID().uuidString; physicalSentVersion = nil
        }
        .onChange(of: app.ogsClient.canResign) { allowed in if !allowed { cancelResignation() } }
        .onDisappear { cancelResignation(); physicalBoardEnabled = false }
        .alert("Are you sure you want to resign?", isPresented: $showResignConfirmation) {
            Button("Resign Game", role: .destructive) {
                if let id = resignTarget { app.ogsClient.resignGame(gameID: id) }
                resignTarget = nil
            }
            Button("Cancel", role: .cancel) { resignTarget = nil }
        } message: {
            Text("Resigning ends this game as a loss. This cannot be undone.")
        }
    }
    
    private var resultBanner: some View {
        VStack(spacing: 4) {
            if let result = app.ogsClient.activeGameResult {
                Text(result.title).interfaceFont(.title2, weight: .bold)
                Text(result.subtitle).interfaceFont(.headline)
                Text(result.method).foregroundStyle(.yellow)
            } else if let outcome = app.ogsClient.activeGameOutcome {
                Text(outcome).interfaceFont(.headline)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("game-result-banner")
    }

    private var headerSection: some View {
        HStack {
            Button(action: {
                app.showOnlineBrowser()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(app.mode == .observe ? "Games" : "Lobby")
                }
            }

            Spacer()
            // Version Indicator
            Text("v1.0.0").interfaceFont(.caption2).foregroundColor(.white.opacity(0.3))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let tc = app.ogsClient.activeGameTimeControl {
                    Text(tc).interfaceFont(.subheadline).foregroundColor(.secondary)
                }
                if let k = app.ogsClient.komi {
                    Text("Komi: \(k, specifier: "%.1f")")
                        .interfaceFont(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                HStack(spacing: 4) {
                    if let rules = app.ogsClient.gameRules {
                        Text(rules).interfaceFont(.caption2).foregroundColor(.white.opacity(0.5))
                    }
                    Text(app.ogsClient.isRanked ? "Ranked" : "Unranked")
                        .interfaceFont(.caption2)
                        .foregroundColor(app.ogsClient.isRanked ? .green.opacity(0.8) : .white.opacity(0.4))
                }
            }.padding(.horizontal)
            Spacer()
            // Resign moved to bottom controls
        }
    }
    
    private func undoApprovalSection(username: String) -> some View {
        VStack(spacing: 8) {
            Text("Undo request from \(username)").interfaceFont(.caption).bold()
            HStack {
                Button("Decline") {
                    if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoReject(gameID: id) }
                }.buttonStyle(.bordered)
                Button("Accept Undo") {
                    if let id = app.ogsClient.activeGameID, let move = app.ogsClient.undoRequestedMoveNumber {
                        app.ogsClient.sendUndoAccept(gameID: id, moveNumber: move)
                    }
                }.tint(.green).buttonStyle(.borderedProminent)
            }
            .disabled(!app.ogsClient.canPlayMoves || app.ogsClient.isRequestingUndo)
            .controlSize(.small)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(8)
        .padding()
    }
    
    private var playerInfoSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // BLACK PLAYER
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let c = app.ogsClient.blackPlayerCountry { Text(ChallengeHelpers.flagEmoji(for: c)) }
                    Text(app.ogsClient.blackPlayerName ?? "Black")
                        .bold()
                        .foregroundColor(.white)
                        // Active Indicator
                        .overlay(
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(.green)
                                .opacity((app.ogsClient.currentPlayerID == app.ogsClient.blackPlayerID) ? 1 : 0)
                                .offset(y: 4),
                            alignment: .bottomLeading
                        )
                    if let r = app.ogsClient.blackPlayerRank { 
                        Text("[\(ChallengeHelpers.formatRank(r))]").interfaceFont(.caption).foregroundColor(.white.opacity(0.7)) 
                    }
                }
                Text("\(app.ogsClient.blackCaptures) captures").interfaceFont(.caption2).foregroundColor(.white.opacity(0.6))
                GameClockView(
                    mainTime: app.ogsClient.blackTimeRemaining,
                    periods: app.ogsClient.blackClockPeriods,
                    periodTime: app.ogsClient.blackClockPeriodTime,
                    side: .left,
                    isDark: true
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.4).opacity(0.85)) // Neutral Dark Gray + Trans
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // WHITE PLAYER
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    if let c = app.ogsClient.whitePlayerCountry { Text(ChallengeHelpers.flagEmoji(for: c)) }
                    Text(app.ogsClient.whitePlayerName ?? "White")
                        .bold()
                        .foregroundColor(.black)
                        // Active Indicator
                        .overlay(
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(.green)
                                .opacity((app.ogsClient.currentPlayerID == app.ogsClient.whitePlayerID) ? 1 : 0)
                                .offset(y: 4),
                            alignment: .bottomTrailing
                        )
                    if let r = app.ogsClient.whitePlayerRank { 
                        Text("[\(ChallengeHelpers.formatRank(r))]").interfaceFont(.caption).foregroundColor(.black.opacity(0.6)) 
                    }
                }
                Text("\(app.ogsClient.whiteCaptures) captures").interfaceFont(.caption2).foregroundColor(.black.opacity(0.5))
                GameClockView(
                    mainTime: app.ogsClient.whiteTimeRemaining,
                    periods: app.ogsClient.whiteClockPeriods,
                    periodTime: app.ogsClient.whiteClockPeriodTime,
                    side: .right,
                    isDark: false
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(Color(white: 0.75).opacity(0.85)) // Neutral Light Gray + Trans
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
        }
    }
    
    private var controlsSection: some View {
        VStack(spacing: 8) {
            if app.ogsClient.isGameFinished, let outcome = app.ogsClient.activeGameOutcome {
                Text(outcome).interfaceFont(.headline).multilineTextAlignment(.center)
            }
            if !app.ogsClient.isConnected || !app.ogsClient.isSocketAuthenticated {
                Text(app.ogsClient.connectionStatus).interfaceFont(.caption).foregroundColor(.orange)
            }
            if app.player.currentIndex != app.player.maxIndex {
                Text("Showing move \(app.player.currentIndex) of \(app.player.maxIndex)")
                    .interfaceFont(.caption).foregroundColor(.secondary)
                Button("Return to latest move") { app.boardVM?.goToEnd() }
            }
            if let error = app.ogsClient.lastError { Text(error).interfaceFont(.caption).foregroundColor(.orange) }
            if let error = exportError { Text(error).interfaceFont(.caption).foregroundColor(.orange) }
            if !app.ogsClient.isGameFinished { controlButtons }
            saveSGFButton
            HStack {
                Button("Review game") { app.copyCurrentBoard(to: .review) }
                if app.ogsClient.isGameFinished {
                    Button(app.mode == .observe ? "Back to games" : "Back to lobby") { app.showOnlineBrowser() }
                }
            }
        }
    }
    
    private var controlButtons: some View {
        Group {
            if app.ogsClient.isReconcilingMoves {
                Label("Refreshing game state…", systemImage: "arrow.clockwise").interfaceFont(.caption)
            }
            if app.ogsClient.isScoringPhase || app.ogsClient.isGameFinished {
                OGSScoringPanel(
                    finished: app.ogsClient.isGameFinished,
                    connected: app.ogsClient.isConnected && app.ogsClient.isSocketAuthenticated,
                    participant: app.ogsClient.isGameParticipant,
                    atLivePosition: app.player.currentIndex == app.player.maxIndex,
                    canEdit: app.ogsClient.canEditScore,
                    acceptance: app.ogsClient.scoreAcceptance,
                    strictSeki: app.ogsClient.strictSekiMode,
                    summary: app.ogsClient.scoringDisplaySummary,
                    scoringSettings: app.player.analysisSettings,
                    winnerDescription: app.ogsClient.scoringDisplaySummary?.winnerDescription(blackName: app.ogsClient.blackPlayerName, whiteName: app.ogsClient.whitePlayerName),
                    serverTerritory: app.ogsClient.scoringDisplaySummary?.positions(width: app.player.board.size, height: app.player.board.size) != nil,
                    error: app.ogsClient.scoringError,
                    accept: { if let id = app.ogsClient.activeGameID { app.ogsClient.acceptScore(gameID: id) } },
                    resume: { if let id = app.ogsClient.activeGameID { app.ogsClient.rejectScore(gameID: id) } }
                )
            } else {
                // NORMAL CONTROLS
                if !app.ogsClient.isGameParticipant {
                    Text("Observing • Game actions disabled").interfaceFont(.caption).foregroundColor(.secondary)
                } else {
                HStack(spacing: 8) {
                    if app.ogsClient.isRequestingUndo {
                        Button("Cancel undo") {
                            if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoReject(gameID: id) }
                        }.disabled(!app.ogsClient.canPlayMoves)
                    } else {
                        Button("Undo") {
                            if let id = app.ogsClient.activeGameID {
                                app.ogsClient.sendUndoRequest(gameID: id, moveNumber: app.player.maxIndex)
                            }
                        }.disabled(!app.ogsClient.canPlayMoves || app.player.maxIndex == 0 ||
                                   app.player.currentIndex != app.player.maxIndex || app.ogsClient.undoRequestedMoveNumber != nil)
                    }
                    Spacer(minLength: 0)
                    Button("Pass") { app.boardVM?.passOnline() }
                        .disabled(app.boardVM?.onlinePassUnavailableReason != nil)
                        .help(app.boardVM?.onlinePassUnavailableReason ?? "Pass your turn")
                    Button("Resign…") {
                        resignTarget = app.ogsClient.activeGameID
                        showResignConfirmation = true
                    }
                    .foregroundColor(.red)
                    .disabled(!app.ogsClient.canResign)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .buttonStyle(.bordered)
                }
            }
        }
    }
    
    @ViewBuilder
    private var saveSGFButton: some View {
        if app.ogsClient.activeGameID != nil {
            Button(action: { saveSGF() }) {
                HStack {
                    Image(systemName: "arrow.down.doc")
                    Text(isSavingSGF ? "Downloading SGF…" : "Save SGF")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(isSavingSGF)
            .accessibilityIdentifier("save-game-sgf")
            .padding(.top, 4)
        }
    }


    private func cancelResignation() {
        showResignConfirmation = false
        resignTarget = nil
    }

    private func saveSGF() {
        guard !isSavingSGF, let gid = app.ogsClient.activeGameID else { return }
        let black = app.ogsClient.blackPlayerName
        let white = app.ogsClient.whitePlayerName
        isSavingSGF = true; exportError = nil
        app.ogsClient.fetchSGFDownload(gameID: gid) { data, _ in
            DispatchQueue.main.async {
                guard app.mode.usesOGS, app.ogsClient.activeGameID == gid else { isSavingSGF = false; return }
                guard let data, !data.isEmpty else {
                    isSavingSGF = false
                    exportError = "Could not download this SGF. Check the connection and try again."
                    return
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
                let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                var info = text.flatMap { try? SGFParser.parse(text: $0) }
                    .map { SGFGame.from(tree: $0).info } ?? SGFGame.Info()
                if info.playerBlack?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { info.playerBlack = black }
                if info.playerWhite?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { info.playerWhite = white }
                panel.nameFieldStringValue = info.suggestedFilename
                panel.directoryURL = AppSettings.shared.savedGamesFolderURL
                panel.begin { response in
                    isSavingSGF = false
                    if response == .OK, let url = panel.url {
                        do {
                            try data.write(to: url, options: .atomic)
                            app.rememberSGFSave(to: url)
                        }
                        catch { exportError = "Could not save the SGF: \(error.localizedDescription)" }
                    }
                }
            }
        }
    }
}

// MARK: - Game Clock View
struct GameClockView: View {
    let mainTime: Double?
    let periods: Int?
    let periodTime: Double?
    enum Side { case left, right }
    let side: Side
    var isDark: Bool = true // New Parameter for Text Color
    
    static func formattedTime(_ sec: Double) -> String {
        guard sec.isFinite else { return "--:--" }
        if sec < 60 {
            // Round up at tenth-second precision so a positive remainder never
            // displays zero. Normalize the minute boundary (never "0:60.0").
            let tenths = Int(ceil(max(0, sec) * 10))
            return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
        }
        // OGS Clock.tsx uses ceil((milliseconds - 1) / 1000). Match its display
        // rounding, including the 1 ms boundary tolerance, without altering clock state.
        let rounded = ceil(max(0, sec - 0.001))
        guard rounded < Double(Int.max) else { return "--:--" }
        let s = Int(rounded)
        let m = s / 60
        let remS = s % 60
        return String(format: "%d:%02d", m, remS)
    }
    
    var body: some View {
        VStack(alignment: side == .left ? .leading : .trailing) {
            
            // LOGIC: If main time is exhausted (<= 0) AND we have Byoyomi periods,
            // promote Byoyomi to the Large Text slot.
            
            let isByoyomiActive = mainTime.map { $0 <= 0 } == true && (periods ?? 0) > 0 && periodTime != nil
            
            if isByoyomiActive {
                // BYOYOMI (Large)
                if let p = periods, let pt = periodTime {
                    let pStr = (p == 1) ? "SD" : "\(p)"
                    Text("\(Self.formattedTime(pt)) (\(pStr))")
                        .interfaceFont(.title2).monospacedDigit().bold() // Promoted Size
                        .foregroundColor(isDark ? .white : .black) // Standard Color
                }
                
                // MAIN TIME (Small/Hidden or "0:00")
                // User said "main time is exhausted anyways", so we can arguably hide it or show simplified.
                // We'll show "0:00" small just for context, or hide it.
                // Text("0:00").interfaceFont(.caption).foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                
            } else {
                // NORMAL MAIN TIME (Large)
                Text(mainTime.map(Self.formattedTime) ?? "--:--")
                    .interfaceFont(.title2).monospacedDigit().bold()
                    .foregroundColor(isDark ? .white : .black)
                
                // BYOYOMI (Small/Secondary)
                if let p = periods, let pt = periodTime {
                    let pStr = (p == 1) ? "SD" : "\(p)"
                    Text("+ \(Self.formattedTime(pt)) (\(pStr))")
                        .interfaceFont(.body).monospacedDigit()
                        .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
            }
        }
        .padding(8)
        // Removed inner background since parent handles it
    }
}

// MARK: - Chat Views (Inlined for Target Membership)
struct OGSChatView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var gameVM: OGSGameViewModel
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Game Chat")
                    .interfaceFont(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                if app.postGameChatID != nil {
                    Button { app.closePostGameChat() } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                        .help("Close game chat")
                        .accessibilityLabel("Close game chat")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(gameVM.chatMessages) { msg in
                            ChatBubble(msg: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: gameVM.chatMessages.count) { _ in
                    if let last = gameVM.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.black.opacity(0.2))
            
            // Input Area
            if !app.ogsClient.observationOnly {
            HStack(spacing: 8) {
                TextField("Say something...", text: $inputText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .focused($isFocused)
                    .onChange(of: isFocused) { focused in
                         // SAFETY: Disable global shortcuts when typing
                         app.isTypingInChat = focused
                    }
                    // Root Cause Fixed: KeyboardShortcuts now uses bubbling phase.
                    // No need for manual handling here anymore.
                    .foregroundColor(.white)
                    .onSubmit { sendMessage() }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                        .padding(8)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.ogsClient.canSendChat)
                .accessibilityLabel("Send chat message")
            }
            .padding(10)
            .background(Color.black.opacity(0.3))
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5)) // Matches panels
        .onChange(of: app.ogsClient.activeGameID) { _ in inputText = ""; isFocused = false; app.isTypingInChat = false }
        .onDisappear { app.isTypingInChat = false }
    }
    
    func sendMessage() {
        guard gameVM.sendChat(inputText) else { return }
        inputText = ""
        // Keep focus? Usually yes for chat.
        isFocused = true
    }
}

struct ChatBubble: View {
    let msg: OGSChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !msg.isSelf {
                // Sender Avatar/Initials
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .overlay(Text(msg.sender.prefix(1).uppercased()).interfaceFont(.caption).bold())
            } else {
                Spacer()
            }
            
            VStack(alignment: msg.isSelf ? .trailing : .leading, spacing: 2) {
                if !msg.isSelf {
                    HStack {
                         Text(msg.sender).interfaceFont(.caption2).foregroundColor(.gray)
                         Text(timeAndMoveString(for: msg)).interfaceFont(.caption2).foregroundColor(.gray.opacity(0.6))
                    }
                }
                
                Text(msg.message)
                    .interfaceFont(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(msg.isSelf ? Color.blue.opacity(0.8) : Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                
                if msg.isSelf {
                    Text(timeAndMoveString(for: msg)).interfaceFont(.caption2).foregroundColor(.gray.opacity(0.5))
                }
            }
            
            if msg.isSelf {
                // Self Avatar (Initial) or Right Align
                // Circle().fill(Color.blue).frame(width: 24, height: 24)
            } else {
                Spacer()
            }
        }
    }
    
    private func timeAndMoveString(for msg: OGSChatMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: msg.timestamp)
        if let mv = msg.moveNumber {
            return "\(time) • Move \(mv)"
        }
        return time
    }
}
