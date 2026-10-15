// MARK: - File: OGSBrowserView.swift (v4.202)
import SwiftUI

struct OGSBrowserView: View {
    @EnvironmentObject var app: AppModel
    @Binding var isPresentingCreate: Bool
    var onJoin: (Int) -> Void
    @State private var isPresentingLogin = false

    @AppStorage("ogs_filter_speed") private var selectedSpeed: GameSpeedFilter = .all
    @AppStorage("ogs_filter_ranked") private var showRankedOnly: Bool = false
    @AppStorage("ogs_filter_ineligible") private var showIneligible: Bool = false
    @AppStorage("ogs_filter_sizes") private var sizeFiltersRaw: String = "19,13,9,Other"

    private var sizeFilters: Set<BoardSizeCategory> {
        Set(sizeFiltersRaw.split(separator: ",").compactMap { BoardSizeCategory(rawValue: String($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            if let error = app.ogsClient.lastError {
                Text(error).font(.caption).foregroundColor(.orange).padding(8)
            }
            Divider().background(Color.white.opacity(0.1))
            if filteredChallenges.isEmpty {
                emptyState
            } else {
                challengeList
            }
        }
        .sheet(isPresented: $isPresentingLogin) { OGSLoginView(isPresented: $isPresentingLogin) }
        .onAppear { app.ogsClient.refreshChallengeLobby() }
        .onChange(of: app.ogsClient.isSocketAuthenticated) { ready in
            if ready { app.ogsClient.refreshChallengeLobby() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Lobby").font(.headline).foregroundColor(.white)
                Button(action: { isPresentingCreate = true }) {
                    Text("Create").font(.caption).bold().padding(.horizontal, 4)
                }.buttonStyle(.bordered).tint(.blue)
                    .disabled(!app.ogsClient.isConnected || !app.ogsClient.isSocketAuthenticated)
                Spacer()
                if app.ogsClient.isConnected {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let name = app.ogsClient.username {
                            Label("Connected as \(name)", systemImage: "circle.fill").font(.caption).foregroundColor(.green)
                        } else {
                            Label("Connected", systemImage: "circle.fill").font(.caption).foregroundColor(.green)
                        }
                        
                        if app.ogsClient.isAuthenticated {
                            Button("Logout") { app.ogsClient.logout() }.font(.caption).buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                        } else {
                            Button("Log In") { isPresentingLogin = true }.font(.caption).buttonStyle(.bordered).tint(.green)
                        }
                    }
                } else { 
                    Button("Log In") { isPresentingLogin = true }.font(.caption).buttonStyle(.borderedProminent).tint(.green)
                }
            }
            // Resume Button
            if let rid = app.returnToOnlineGameID {
                Button(action: { app.resumeOnlineGame(id: rid) }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Return to Game \(rid)")
                        if let name = app.ogsClient.opponentName(for: app.ogsClient.playerID) { Text("vs \(name)") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .padding(.horizontal)
            }
            HStack(spacing: 12) {
                Text("Size:").font(.caption).foregroundColor(.white.opacity(0.7))
                ForEach(BoardSizeCategory.allCases) { size in
                    Toggle(size.rawValue, isOn: sizeBinding(for: size)).toggleStyle(.checkbox).font(.caption)
                }
                Spacer()
            }
            HStack {
                Picker("", selection: $selectedSpeed) {
                    ForEach(GameSpeedFilter.allCases) { speed in Text(speed.rawValue).tag(speed) }
                }.labelsHidden().frame(width: 120).controlSize(.small)
                Toggle("Rated Only", isOn: $showRankedOnly).toggleStyle(.checkbox).font(.caption)
                Toggle("Ineligible", isOn: $showIneligible).toggleStyle(.checkbox).font(.caption).foregroundColor(.gray)
                Spacer()
            }
        }.padding().background(Color.black.opacity(0.1))
    }

    private var emptyState: some View {
        VStack { Spacer(); Text(app.ogsClient.isConnected ? "No challenges found." : "Connecting...").foregroundColor(.white.opacity(0.5)); Spacer() }
    }

    private var challengeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredChallenges) { challenge in
                    ChallengeRow(challenge: challenge, isMine: isChallengeMine(challenge)) {
                        if isChallengeMine(challenge) { app.ogsClient.cancelChallenge(challengeID: challenge.id) }
                        else { onJoin(challenge.id) }
                    }
                    Divider().background(Color.white.opacity(0.1))
                }
            }
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }

    // FIX: Broken down into sub-expressions to prevent compiler timeout
    private var filteredChallenges: [OGSChallenge] {
        let all = app.ogsClient.availableGames
        // NSLog("[OGS-UI] 🔍 Filtering \(all.count) games. My ID: \(app.ogsClient.playerID ?? -1)")
        
        let filtered = all.filter { game in
            // ALWAYS show my own challenges, regardless of filters
            if isChallengeMine(game) { return true }
            
            if showRankedOnly && !(game.game?.ranked ?? false) { return false }
            
            let w = game.game?.width ?? 19
            let h = game.game?.height ?? 19
            let cat: BoardSizeCategory = (w == 19 && h == 19) ? .size19 : (w == 13 && h == 13) ? .size13 : (w == 9 && h == 9) ? .size9 : .other
            if !sizeFilters.contains(cat) { return false }
            
             if !sizeFilters.contains(cat) { return false }
            
            // Eligibility Check
            if !showIneligible, let myRank = app.ogsClient.userRank {
                let min = game.min_rank ?? -999
                let max = game.max_rank ?? 999
                if myRank < min || myRank > max { return false }
            }
            
            if selectedSpeed != .all {
                let speed = game.speedCategory
                if selectedSpeed == .realTime && (speed != "live" && speed != "blitz") { return false }
                if selectedSpeed == .live && speed != "live" { return false }
                if selectedSpeed == .blitz && speed != "blitz" { return false }
                if selectedSpeed == .correspondence && speed != "correspondence" { return false }
            }
            return true
        }
        let finalList = filtered.sorted { a, b in
            let mineA = isChallengeMine(a)
            let mineB = isChallengeMine(b)
            if mineA && !mineB { return true }
            if !mineA && mineB { return false }
            return a.id > b.id
        }
        
        // LOGGING: Pipeline Stage 3 - UI Filtering
        NSLog("[OGS-TRACE] 🖥️ UI Showing \(finalList.count) challenges (Local Total: \(all.count))")
        return finalList
    }

    private func isChallengeMine(_ challenge: OGSChallenge) -> Bool {
        guard let pid = app.ogsClient.playerID else { return false }
        return challenge.challenger?.id == pid
    }

    private func sizeBinding(for size: BoardSizeCategory) -> Binding<Bool> {
        Binding(
            get: { sizeFilters.contains(size) },
            set: { isActive in
                var current = sizeFilters
                if isActive { current.insert(size) } else { current.remove(size) }
                sizeFiltersRaw = current.map { $0.rawValue }.sorted().joined(separator: ",")
            }
        )
    }
}

struct ChallengeRow: View {
    let challenge: OGSChallenge; let isMine: Bool; let onAction: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onAction) {
                Text(isMine ? "CANCEL" : "ACCEPT")
                    .font(.system(size: 11, weight: .bold)) // Slightly increased
                    .fixedSize() // Prevent truncation
                    .padding(.horizontal, 4)
                    .foregroundColor(isMine ? .black : .white)
            }
            .buttonStyle(.borderedProminent)
            .tint(isMine ? .yellow : .green)
            .controlSize(.regular) // Use regular size for better layout
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(challenge.challenger?.displayRank ?? "?").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    Text(challenge.challenger?.username ?? "Unknown").font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                }
                Text(challenge.timeControlDisplay).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if challenge.game?.ranked ?? false {
                        Text("RATED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Text(challenge.boardSize).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                }
                Text(challenge.game?.rules?.capitalized ?? "Japanese")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.001)) // Hit testing
    }

    // rankColor helper removed as it is no longer used
}

// MARK: - Login View (Merged for Target Simplicity)
struct OGSLoginView: View {
    @EnvironmentObject var app: AppModel
    @Binding var isPresented: Bool
    
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    
    // Focus State
    @FocusState private var focusedField: Field?
    enum Field { case username, password }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))
            formContent
        }
        .frame(width: 320, height: 250)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .onAppear {
            focusedField = .username
            app.isTypingInChat = true
        }
        .onDisappear {
            app.isTypingInChat = false
            if isLoggingIn { app.ogsClient.logout() }
        }
    }
    
    private var header: some View {
        HStack {
            Text("Login to OGS").font(.headline).foregroundColor(.white)
            Spacer()
            Button(action: cancelLogin) {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Cancel login")
        }.padding()
    }
    
    private var formContent: some View {
        VStack(spacing: 16) {
            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption).multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Username/Email").font(.caption).foregroundColor(.gray)
                TextField("", text: $username)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.caption).foregroundColor(.gray)
                HStack(spacing: 8) {
                    if isPasswordVisible {
                        TextField("", text: $password)
                     } else {
                        SecureField("", text: $password)
                     }
                     Button(action: { isPasswordVisible.toggle() }) {
                         Image(systemName: isPasswordVisible ? "eye" : "eye.slash").foregroundColor(.white.opacity(0.6))
                     }.buttonStyle(.plain)
                 }
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .focused($focusedField, equals: .password)
                    .onSubmit { performLogin() }
            }
            
            Button(action: performLogin) {
                HStack {
                    if isLoggingIn { ProgressView().controlSize(.small) }
                    Text("Log In").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
        }.padding(20)
    }
    
    private func performLogin() {
        let loginName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoggingIn, !loginName.isEmpty, !password.isEmpty else { return }
        isLoggingIn = true; errorMessage = nil
        app.ogsClient.login(username: loginName, password: password) { success, error in
            DispatchQueue.main.async {
                guard isPresented else { return }
                self.isLoggingIn = false
                if success {
                    self.isPresented = false
                    // Trigger connection immediately after successful login
                    app.ogsClient.connect()
                } else {
                    self.errorMessage = error ?? "Login failed"
                }
            }
        }
    }

    private func cancelLogin() {
        // Logout already fences both the login request and its validation response.
        if isLoggingIn { app.ogsClient.logout() }
        isLoggingIn = false
        password = ""
        isPresented = false
    }
}

/// Read-only discovery of games in progress, with direct link/ID entry as well.
struct OGSObservationBrowserView: View {
    @EnvironmentObject var app: AppModel
    @State private var showLogin = false
    @State private var gameLink = ""
    @FocusState private var editingLink: Bool
    // Only the presenting sheet supplies a close action. The sidebar must stay open.
    var didObserve: () -> Void = {}
    var onCancel: (() -> Void)?
    var showsTitle: Bool
    var refreshInterval: UInt64

    init(gameLink: String = "", didObserve: @escaping () -> Void = {}, onCancel: (() -> Void)? = nil,
         showsTitle: Bool = true, refreshInterval: UInt64 = 10_000_000_000) {
        _gameLink = State(initialValue: gameLink)
        self.didObserve = didObserve
        self.onCancel = onCancel
        self.showsTitle = showsTitle
        self.refreshInterval = refreshInterval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle || onCancel != nil {
                HStack {
                    if showsTitle { Text("Select a Game").font(.headline) }
                    Spacer()
                    if let onCancel {
                        Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    }
                }
            }
            if !app.ogsClient.isAuthenticated {
                Text("Sign in with your OGS account. This app has its own login session.")
                    .font(.caption)
                Button("Log In") { showLogin = true }.buttonStyle(.borderedProminent)
            }
            currentGames
            Divider()
            Text("Open a game by link or ID").font(.subheadline)
            TextField("OGS game link or game ID", text: $gameLink)
                .textFieldStyle(.roundedBorder).focused($editingLink)
                .onChange(of: editingLink) { app.isTypingInChat = $0 }
                .onSubmit { observe() }
            Button("Observe Game") { observe() }
                .buttonStyle(.borderedProminent)
                .disabled(!app.ogsClient.isSocketAuthenticated || OGSClient.observationGameID(gameLink) == nil)
            Text("Observing does not let you play moves or send chat.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showLogin) { OGSLoginView(isPresented: $showLogin).environmentObject(app) }
        .task(id: app.ogsClient.isSocketAuthenticated) {
            guard app.ogsClient.isSocketAuthenticated else { return }
            app.ogsClient.refreshObservedGames()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: refreshInterval) }
                catch { return }
                guard !Task.isCancelled else { return }
                app.ogsClient.refreshObservedGames()
            }
        }
        .onDisappear {
            app.isTypingInChat = false
            app.ogsClient.cancelObservedGamesRefresh()
        }
    }

    private var currentGames: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Strongest player first").font(.caption).foregroundColor(.secondary)
                Spacer()
                if app.ogsClient.isLoadingObservedGames { ProgressView().controlSize(.small) }
            }
            if let error = app.ogsClient.observedGamesError {
                Text(error).font(.caption).foregroundColor(.orange)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if app.ogsClient.observedGames.isEmpty {
                        Text(!app.ogsClient.isSocketAuthenticated ? "Sign in and connect to see current games." :
                            (app.ogsClient.isLoadingObservedGames ? "Loading games…" :
                                (app.ogsClient.observedGamesError == nil ? "No live games right now." : "Game list unavailable.")))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(app.ogsClient.observedGames) { game in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(game.blackName) [\(game.blackRank)] · Black").lineLimit(1)
                                Text("\(game.whiteName) [\(game.whiteRank)] · White").lineLimit(1)
                                Text([game.boardSize, game.moveCount.map { "\($0) moves" } ?? "Moves unavailable"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                                Text(app.ogsClient.observedTimeControlLabel(for: game))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Observe") { observe(id: game.id) }
                                .disabled(!app.ogsClient.isSocketAuthenticated)
                                .accessibilityLabel("Observe \(game.blackName) versus \(game.whiteName)")
                        }
                        .task(id: app.ogsClient.observedMetadataGeneration) {
                            app.ogsClient.loadObservedTimeControl(for: game)
                        }
                        Divider()
                    }
                    if app.ogsClient.hasMoreObservedGames {
                        // A new batch recreates this sentinel. It fetches only while
                        // visible, and a failure requires an explicit retry.
                        HStack {
                            Spacer()
                            if app.ogsClient.observedGamesError != nil {
                                Button("Retry loading more") { app.ogsClient.loadMoreObservedGames() }
                            } else {
                                Text("Loading more games…").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .id(app.ogsClient.observedGamesPage)
                        .onAppear {
                            if app.ogsClient.observedGamesError == nil { app.ogsClient.loadMoreObservedGames() }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 100, maxHeight: .infinity)
        }
    }

    private func observe() {
        guard let id = OGSClient.observationGameID(gameLink) else { return }
        observe(id: id)
    }

    private func observe(id: Int) {
        guard app.ogsClient.isSocketAuthenticated else { return }
        app.ogsClient.lastError = nil
        app.mode = .observe
        app.showRightPanel = true
        app.resumeOnlineGame(id: id)
        didObserve()
    }
}
