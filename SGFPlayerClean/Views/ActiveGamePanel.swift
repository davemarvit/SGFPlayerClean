// MARK: - File: ActiveGamePanel.swift (v3.505)
import SwiftUI

struct ActiveGamePanel: View {
    @EnvironmentObject var app: AppModel
    @State private var showResignConfirmation = false
    @State private var resignTarget: Int?
    @State private var isSavingSGF = false
    @State private var exportError: String?
    @State private var resultDismissed = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                headerSection
                
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
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
                if let vm = app.ogsGame {
                    OGSChatView(gameVM: vm)
                        // .frame(height: 200) // Flexible height preferred
                        .cornerRadius(8)
                }
                
                Spacer() // Pushes controls to bottom
                
                // Controls (Moved to Bottom)
                controlsSection
            }
            .padding()
            
            if !resultDismissed && app.ogsClient.isGameFinished && (app.ogsClient.activeGameResult != nil || app.ogsClient.activeGameOutcome != nil) {
                resultOverlay.transition(.opacity.combined(with: .scale))
            }
        }
        .onChange(of: app.ogsClient.activeGameID) { _ in
            resultDismissed = false; cancelResignation(); exportError = nil
        }
        .onChange(of: app.ogsClient.canResign) { allowed in if !allowed { cancelResignation() } }
        .onDisappear { cancelResignation() }
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
    
    private var resultOverlay: some View {
        VStack(spacing: 20) {
            if let res = app.ogsClient.activeGameResult {
                Text(res.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)
                
                VStack(spacing: 4) {
                    Text(res.subtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                    Text(res.method)
                        .font(.title3)
                        .bold()
                        .foregroundColor(.yellow)
                }
            } else if let outcome = app.ogsClient.activeGameOutcome {
                Text(outcome).font(.title2).foregroundColor(.yellow)
            }
            
            // Save SGF moved to persistent controlsSection at bottom
            
            // Redundant "Return to Lobby" button removed to prevent blocking chat/board.
            // User can use the "< Lobby" button in the header.
            

            // Redundant "Return to Lobby" button removed to prevent blocking chat/board.
            // User can use the "< Lobby" button in the header.
        }
        .padding(40)
        .background(Material.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            Button(action: {
                // Dimiss Overlay so user can chat/view board
                resultDismissed = true
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss game result")
            .padding(16),
            alignment: .topTrailing
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(radius: 20)
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
            Text("v1.0.0").font(.caption2).foregroundColor(.white.opacity(0.3))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let tc = app.ogsClient.activeGameTimeControl {
                    Text(tc).font(.subheadline).foregroundColor(.secondary)
                }
                if let k = app.ogsClient.komi {
                    Text("Komi: \(k, specifier: "%.1f")")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                HStack(spacing: 4) {
                    if let rules = app.ogsClient.gameRules {
                        Text(rules).font(.caption2).foregroundColor(.white.opacity(0.5))
                    }
                    Text(app.ogsClient.isRanked ? "Ranked" : "Unranked")
                        .font(.caption2)
                        .foregroundColor(app.ogsClient.isRanked ? .green.opacity(0.8) : .white.opacity(0.4))
                }
            }.padding(.horizontal)
            Spacer()
            // Resign moved to bottom controls
        }
    }
    
    private func undoApprovalSection(username: String) -> some View {
        VStack(spacing: 8) {
            Text("Undo request from \(username)").font(.caption).bold()
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
                        Text("[\(ChallengeHelpers.formatRank(r))]").font(.caption).foregroundColor(.white.opacity(0.7)) 
                    }
                }
                Text("\(app.ogsClient.blackCaptures) captures").font(.caption2).foregroundColor(.white.opacity(0.6))
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
                        Text("[\(ChallengeHelpers.formatRank(r))]").font(.caption).foregroundColor(.black.opacity(0.6)) 
                    }
                }
                Text("\(app.ogsClient.whiteCaptures) captures").font(.caption2).foregroundColor(.black.opacity(0.5))
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
                Text(outcome).font(.headline).multilineTextAlignment(.center)
            }
            if !app.ogsClient.isConnected || !app.ogsClient.isSocketAuthenticated {
                Text(app.ogsClient.connectionStatus).font(.caption).foregroundColor(.orange)
            }
            if app.player.currentIndex != app.player.maxIndex {
                Text("Showing move \(app.player.currentIndex) of \(app.player.maxIndex)")
                    .font(.caption).foregroundColor(.secondary)
                Button("Return to latest move") { app.boardVM?.goToEnd() }
            }
            if let error = app.ogsClient.lastError { Text(error).font(.caption).foregroundColor(.orange) }
            if let error = exportError { Text(error).font(.caption).foregroundColor(.orange) }
            controlButtons
            saveSGFButton
            Button("Review this game") { app.copyCurrentBoard(to: .review) }
        }
    }
    
    private var controlButtons: some View {
        Group {
            if app.ogsClient.isReconcilingMoves {
                Label("Refreshing game state…", systemImage: "arrow.clockwise").font(.caption)
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
                    summary: app.ogsClient.scoreSummary,
                    scoringSettings: app.player.analysisSettings,
                    winnerDescription: app.ogsClient.scoreSummary?.winnerDescription(blackName: app.ogsClient.blackPlayerName, whiteName: app.ogsClient.whitePlayerName),
                    serverTerritory: app.ogsClient.scoreSummary?.positions(width: app.player.board.size, height: app.player.board.size) != nil,
                    error: app.ogsClient.scoringError,
                    accept: { if let id = app.ogsClient.activeGameID { app.ogsClient.acceptScore(gameID: id) } },
                    resume: { if let id = app.ogsClient.activeGameID { app.ogsClient.rejectScore(gameID: id) } }
                )
            } else {
                // NORMAL CONTROLS
                if !app.ogsClient.isGameParticipant {
                    Text("Observing • Game actions disabled").font(.caption).foregroundColor(.secondary)
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
            .padding(.top, 4)
        }
    }


    private func cancelResignation() {
        showResignConfirmation = false
        resignTarget = nil
    }

    private func saveSGF() {
        guard !isSavingSGF, let gid = app.ogsClient.activeGameID else { return }
        func filename(_ name: String) -> String {
            name.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        }
        let black = filename(app.ogsClient.blackPlayerName ?? "Black")
        let white = filename(app.ogsClient.whitePlayerName ?? "White")
        isSavingSGF = true; exportError = nil
        app.ogsClient.fetchSGF(gameID: gid) { data in
            DispatchQueue.main.async {
                guard app.mode.usesOGS, app.ogsClient.activeGameID == gid else { isSavingSGF = false; return }
                guard let data, !data.isEmpty else {
                    isSavingSGF = false
                    exportError = "Could not download this SGF. Check the connection and try again."
                    return
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
                let date = Date().formatted(.iso8601.year().month().day())
                panel.nameFieldStringValue = "\(black)_vs_\(white)_\(date).sgf"
                panel.begin { response in
                    isSavingSGF = false
                    if response == .OK, let url = panel.url {
                        do { try data.write(to: url, options: .atomic) }
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
                        .font(.title2).monospacedDigit().bold() // Promoted Size
                        .foregroundColor(isDark ? .white : .black) // Standard Color
                }
                
                // MAIN TIME (Small/Hidden or "0:00")
                // User said "main time is exhausted anyways", so we can arguably hide it or show simplified.
                // We'll show "0:00" small just for context, or hide it.
                // Text("0:00").font(.caption).foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                
            } else {
                // NORMAL MAIN TIME (Large)
                Text(mainTime.map(Self.formattedTime) ?? "--:--")
                    .font(.title2).monospacedDigit().bold()
                    .foregroundColor(isDark ? .white : .black)
                
                // BYOYOMI (Small/Secondary)
                if let p = periods, let pt = periodTime {
                    let pStr = (p == 1) ? "SD" : "\(p)"
                    Text("+ \(Self.formattedTime(pt)) (\(pStr))")
                        .font(.body).monospacedDigit()
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
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
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
                    .overlay(Text(msg.sender.prefix(1).uppercased()).font(.caption).bold())
            } else {
                Spacer()
            }
            
            VStack(alignment: msg.isSelf ? .trailing : .leading, spacing: 2) {
                if !msg.isSelf {
                    HStack {
                         Text(msg.sender).font(.caption2).foregroundColor(.gray)
                         Text(timeAndMoveString(for: msg)).font(.caption2).foregroundColor(.gray.opacity(0.6))
                    }
                }
                
                Text(msg.message)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(msg.isSelf ? Color.blue.opacity(0.8) : Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                
                if msg.isSelf {
                    Text(timeAndMoveString(for: msg)).font(.caption2).foregroundColor(.gray.opacity(0.5))
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
