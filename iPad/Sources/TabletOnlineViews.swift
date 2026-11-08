import SwiftUI

struct TabletOnlineLobby: View {
    @ObservedObject var online: TabletOnline
    @ObservedObject var client: OGSClient
    @Environment(\.scenePhase) private var phase
    @State private var username = ""
    @State private var password = ""
    @State private var gameID = ""
    @State private var selectedChallenge: OGSChallenge?
    @State private var creating = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(online.status, systemImage: client.isSocketAuthenticated ? "network" : "wifi.slash")
                    if let message = online.message ?? client.lastError { Text(message).foregroundStyle(.orange) }
                }
                if !client.isAuthenticated {
                    Section("Sign in to Online-Go.com") {
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                        Button(online.busy ? "Signing in…" : "Sign in") {
                            online.login(username: username, password: password); password = ""
                        }.disabled(online.busy || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                        Link("Create or recover an OGS account", destination: URL(string: "https://online-go.com")!)
                        Text("Use your OGS username and password. Your password is not saved. Your session stays within this app.").font(.caption)
                    }
                } else {
                    Section("Signed in as \(client.username ?? "OGS player")") {
                        Button("Reconnect") { online.reconnect() }.disabled(online.busy)
                        Button("Sign out", role: .destructive) { online.logout() }
                    }
                    if online.browsingObservedGames { observedGames }
                    if !online.browsingObservedGames && !client.myActiveGames.subtracting(client.finishedGameIDs).isEmpty {
                        Section("Your games") {
                            ForEach(client.myActiveGames.subtracting(client.finishedGameIDs).sorted(), id: \.self) { id in
                                Button("Resume game \(String(id))") { online.join(id) }.disabled(!client.isSocketAuthenticated || online.busy).accessibilityIdentifier("resumeGame_\(id)")
                            }
                        }
                    }
                    Section(online.browsingObservedGames ? "Observe by link or number" : "Open a game") {
                        TextField("OGS game number or link", text: $gameID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ogsGameID")
                        Button("Open link or number") { if let id = OGSClient.observationGameID(gameID) { online.join(id, observing: online.browsingObservedGames) } }
                            .disabled(OGSClient.observationGameID(gameID) == nil || !client.isSocketAuthenticated || online.busy)
                        Text(online.browsingObservedGames ? "Watch the board update live without playing moves." : "Your games open for play. Other players’ games open for spectating.").font(.caption)
                    }
                    if !online.browsingObservedGames {
                        Section("Open challenges") {
                            Button("Create challenge") { creating = true }.disabled(!client.isSocketAuthenticated || online.busy)
                            Button("Refresh challenges") { client.refreshChallengeLobby() }.disabled(!client.isSocketAuthenticated || client.activeGameID != nil)
                            if client.activeGameID != nil {
                                Button("Leave board and browse challenges") { online.lobby() }
                                Text("Leaving the board does not resign the game. Its clock continues on OGS.").font(.caption)
                            } else if client.availableGames.isEmpty {
                                Text(client.isSocketAuthenticated ? "No challenges currently available." : "Waiting for connection…").foregroundStyle(.secondary)
                            }
                            ForEach(client.availableGames) { challenge in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(challenge.challenger?.username ?? "Player") · \(challenge.challenger?.displayRank ?? "?")").font(.headline)
                                    Text(challengeDescription(challenge)).font(.subheadline)
                                    if challenge.challenger?.id == client.playerID {
                                        Button("Cancel my challenge", role: .destructive) { client.cancelChallenge(challengeID: challenge.id) }.disabled(!client.isSocketAuthenticated)
                                    } else {
                                        if let restriction = challenge.rankRestriction(for: client.userRank) { Text(restriction).font(.caption).foregroundStyle(.orange) }
                                        Button("Accept challenge") { selectedChallenge = challenge }
                                            .disabled(!client.isSocketAuthenticated || online.busy || challenge.rankRestriction(for: client.userRank) != nil || challenge.game?.width != challenge.game?.height || (challenge.game?.width ?? 19) > 25)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle(online.browsingObservedGames ? "Observe games" : "Online play")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { online.showLobby = false } } }
            .task(id: online.browsingObservedGames) {
                online.refreshBrowser()
                while online.browsingObservedGames && !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    if phase == .active { online.refreshBrowser() }
                }
            }
            .refreshable { online.refreshBrowser() }
            .sheet(isPresented: $creating) { TabletChallengeForm(online: online) }
            .confirmationDialog("Accept this challenge?", isPresented: Binding(get: { selectedChallenge != nil }, set: { if !$0 { selectedChallenge = nil } }), titleVisibility: .visible) {
                if let challenge = selectedChallenge { Button("Accept and start game") { online.accept(challenge); selectedChallenge = nil } }
            } message: {
                if let challenge = selectedChallenge { Text("\(challenge.challenger?.username ?? "Player")\n\(challengeDescription(challenge))") }
            }
        }
    }
    private var observedGames: some View {
        Section("Ongoing games") {
            Button("Refresh games", systemImage: "arrow.clockwise") { online.refreshBrowser() }
                .disabled(!client.isSocketAuthenticated || client.isLoadingObservedGames)
            if let error = client.observedGamesError { Text(error).foregroundStyle(.orange) }
            if client.isLoadingObservedGames { ProgressView("Loading games…") }
            else if client.observedGames.isEmpty {
                Text(client.isSocketAuthenticated ? "No ongoing games found. Try refreshing." : "Waiting for connection…")
                    .foregroundStyle(.secondary)
            }
            ForEach(client.observedGames) { game in
                Button { online.join(game.id, observing: true) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(game.blackName) (\(game.blackRank)) vs \(game.whiteName) (\(game.whiteRank))")
                            .font(.headline)
                        Text([game.boardSize, game.moveCount.map { "Move \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(client.observedTimeControlLabel(for: game)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                .disabled(!client.isSocketAuthenticated || online.busy)
                .accessibilityIdentifier("observeGame_\(game.id)")
                .onAppear { client.loadObservedTimeControl(for: game) }
            }
            if client.hasMoreObservedGames {
                Button("More games") { client.loadMoreObservedGames() }
                    .disabled(!client.isSocketAuthenticated || client.isLoadingObservedGames)
            }
        }
    }
    private func challengeDescription(_ c: OGSChallenge) -> String {
        "\(c.boardSize) · \(c.game?.rules ?? "Go") · \(c.game?.ranked == true ? "Ranked" : "Unranked") · \(ChallengeHelpers.formatTimeControl(tc: c.time_control, params: c.time_control_parameters, perMove: c.time_per_move))"
    }
}

private struct TabletChallengeForm: View {
    @ObservedObject var online: TabletOnline
    @Environment(\.dismiss) private var dismiss
    @State private var setup: ChallengeSetup = { var s = ChallengeSetup(); s.ranked = false; return s }()
    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    TextField("Name", text: $setup.name)
                    Picker("Board", selection: $setup.size) { ForEach([9,13,19], id: \.self) { Text("\($0) × \($0)").tag($0) } }
                    Picker("Rules", selection: $setup.rules) { Text("Japanese").tag("japanese"); Text("Chinese").tag("chinese"); Text("AGA").tag("aga") }
                    Toggle("Ranked", isOn: $setup.ranked)
                    Picker("Your color", selection: $setup.color) { Text("Automatic").tag("automatic"); Text("Black").tag("black"); Text("White").tag("white") }
                    Picker("Handicap", selection: $setup.handicap) { Text("None").tag(0); Text("Automatic").tag(-1); ForEach(2...9, id: \.self) { Text("\($0)").tag($0) } }
                }
                Section("Clock") {
                    Picker("System", selection: $setup.timeControl) { Text("Byo-yomi").tag("byoyomi"); Text("Fischer").tag("fischer"); Text("Per move").tag("simple") }
                    if setup.timeControl == "byoyomi" {
                        Stepper("Main time: \(setup.mainTime / 60) min", value: $setup.mainTime, in: 0...7200, step: 60)
                        Stepper("Periods: \(setup.periods)", value: $setup.periods, in: 1...10)
                        Stepper("Period: \(setup.periodTime) sec", value: $setup.periodTime, in: 5...300, step: 5)
                    } else if setup.timeControl == "fischer" {
                        Stepper("Initial: \(setup.initialTime / 60) min", value: $setup.initialTime, in: 60...7200, step: 60)
                        Stepper("Increment: \(setup.increment) sec", value: $setup.increment, in: 0...300, step: 5)
                        Stepper("Maximum: \(setup.maxTime / 60) min", value: $setup.maxTime, in: 60...14400, step: 60)
                    } else { Stepper("Per move: \(setup.perMove) sec", value: $setup.perMove, in: 5...300, step: 5) }
                }
                if let error = setup.validationError { Text(error).foregroundStyle(.orange) }
            }.navigationTitle("Create challenge")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Post challenge") { online.create(setup); dismiss() }.disabled(setup.validationError != nil || online.busy || !online.client.isSocketAuthenticated) }
                }
        }
    }
}

/// The same identity summary stays visible in the panel, compact rail and portrait footer.
struct TabletOnlinePlayers: View {
    @ObservedObject var online: TabletOnline
    var showClocks = false
    private var client: OGSClient { online.client }
    var body: some View {
        if client.activeGameID != nil {
            VStack(alignment: .leading, spacing: 6) {
                player(.black, time: client.blackTimeRemaining, period: client.blackClockPeriodTime, periods: client.blackClockPeriods)
                player(.white, time: client.whiteTimeRemaining, period: client.whiteClockPeriodTime, periods: client.whiteClockPeriods)
            }
        }
    }
    private func player(_ color: Stone, time: Double?, period: Double?, periods: Int?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(color == .black ? Color.black : .white).overlay(Circle().stroke(.gray))
                .frame(width: 12, height: 12).padding(.top, 2).accessibilityHidden(true)
            Text(online.playerLabel(color)).font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(color == .black ? "Black" : "White"): \(online.playerLabel(color))")
                .accessibilityIdentifier(color == .black ? "onlinePlayerBlack" : "onlinePlayerWhite")
            if showClocks {
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TabletOnlineDetails.clock(time)).font(.caption).monospacedDigit()
                    if let periods, periods > 0 {
                        Text("\(periods) × \(TabletOnlineDetails.clock(period))").font(.caption2).monospacedDigit()
                    }
                }
            }
        }
    }
}

struct TabletOnlineDetails: View {
    @ObservedObject var online: TabletOnline
    @ObservedObject var client: OGSClient
    @State private var resigning = false
    @State private var passing = false
    @State private var resignGameID: Int?
    @State private var passGameID: Int?
    @State private var passMoveNumber: Int?
    @State private var chatting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(online.status).font(.headline).accessibilityIdentifier("onlineStatus")
            if let message = online.message ?? client.lastError { Text(message).font(.caption).foregroundStyle(.orange) }
            if let id = client.activeGameID {
                Text("\(client.gameRules ?? "Go") · Komi \(client.komi.map { String($0) } ?? "—") · \(client.isRanked ? "Ranked" : "Unranked")").font(.caption)
                if let clock = client.activeGameTimeControl { Text(clock).font(.caption).foregroundStyle(.secondary) }
                if client.isScoringPhase || client.isGameFinished {
                    if client.isGameFinished { Button("Review finished game") { online.reviewFinishedGame() }.disabled(online.busy) }
                    if let result = client.activeGameResult { Text(result.subtitle).font(.subheadline) }
                    if let score = client.scoringDisplaySummary { Text("OGS score: Black \(String(score.black.total)) · White \(String(score.white.total))").font(.subheadline) }
                    if client.isScoringPhase && !client.isGameFinished && client.isGameParticipant {
                        Text("Tap a group to mark it dead or alive. Faded stones are marked dead.").font(.caption)
                        Text(scoreStatus).font(.caption)
                        if let error = client.scoringError { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button("Accept score") { client.acceptScore(gameID: id) }.disabled(!client.canEditScore || client.scoreAcceptance != .none)
                        Button("Resume play") { client.rejectScore(gameID: id) }.disabled(!client.canEditScore)
                    }
                }
                if client.isGameParticipant, let requester = client.undoRequestedUsername, let number = client.undoRequestedMoveNumber {
                    Text("\(requester) requests an undo.")
                    HStack { Button("Accept undo") { client.sendUndoAccept(gameID: id, moveNumber: number) }; Button("Decline undo") { client.sendUndoReject(gameID: id) } }.disabled(!client.canPlayMoves)
                }
                HStack {
                    if client.isGameParticipant {
                        Button("Pass") { passGameID = id; passMoveNumber = client.lastKnownRemoteMoveNumber; passing = true }.disabled(!online.canMove)
                        Button("Resign", role: .destructive) { resignGameID = id; resigning = true }.disabled(!client.canResign)
                    }
                    Button("Chat") { chatting = true }
                }.buttonStyle(.bordered)
                if client.isGameParticipant {
                    Button(client.isRequestingUndo ? "Undo requested" : "Request undo") { if let number = client.lastKnownRemoteMoveNumber { client.sendUndoRequest(gameID: id, moveNumber: number) } }
                        .disabled(!client.canPlayMoves || online.awaitingMove || client.isRequestingUndo || (client.lastKnownRemoteMoveNumber ?? 0) == 0)
                }
            }
            Button("Refresh connection") { online.reconnect() }.buttonStyle(.bordered)
        }
        .confirmationDialog("Pass your turn?", isPresented: $passing, titleVisibility: .visible) { Button("Pass") { if passGameID == client.activeGameID, passMoveNumber == client.lastKnownRemoteMoveNumber { online.play(pass: true) } } }
        .confirmationDialog("Resign this game?", isPresented: $resigning, titleVisibility: .visible) { Button("Resign", role: .destructive) { if let id = resignGameID, id == client.activeGameID { client.resignGame(gameID: id) } } }
        .sheet(isPresented: $chatting) { TabletOnlineChat(chat: online.chat, client: client) }
    }
    private var scoreStatus: String {
        switch client.scoreAcceptance {
        case .none: return "Review both players’ marks before accepting."
        case .updating: return "Updating marks…"
        case .submitting: return "Waiting for OGS to confirm acceptance…"
        case .confirmed: return "Accepted. Waiting for the other player."
        case .resuming: return "Waiting for play to resume…"
        }
    }
    static func clock(_ time: Double?) -> String {
        guard let time, time.isFinite else { return "—" }
        let seconds = Int(min(Double(Int.max / 2), max(0, time.rounded(.up))))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TabletOnlineChat: View {
    @ObservedObject var chat: OGSGameViewModel
    @ObservedObject var client: OGSClient
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        NavigationStack {
            VStack {
                ScrollViewReader { proxy in
                    List(chat.chatMessages) { message in
                        VStack(alignment: .leading) { Text(message.sender).font(.caption.bold()); Text(message.message) }.id(message.id)
                    }.onChange(of: chat.chatMessages.count) { _,_ in if let id = chat.chatMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                HStack {
                    TextField("Message", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button("Send") { if chat.sendChat(draft) { draft = "" } }.disabled(!client.canSendChat || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            }.navigationTitle("Game chat").toolbar { Button("Done") { dismiss() } }
        }
    }
}
