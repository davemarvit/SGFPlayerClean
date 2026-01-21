// MARK: - File: OGSBrowserView.swift (v4.202)
import SwiftUI

struct OGSBrowserView: View {
    @EnvironmentObject var app: AppModel
    @Binding var isPresentingCreate: Bool
    var onJoin: (Int) -> Void
    @State private var isPresentingLogin = false

    @AppStorage("ogs_filter_speed") private var selectedSpeed: GameSpeedFilter = .all
    @AppStorage("ogs_filter_ranked") private var showRankedOnly: Bool = false
    @AppStorage("ogs_filter_sizes") private var sizeFiltersRaw: String = "19,13,9,Other"

    private var sizeFilters: Set<BoardSizeCategory> {
        Set(sizeFiltersRaw.split(separator: ",").compactMap { BoardSizeCategory(rawValue: String($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().background(Color.white.opacity(0.1))
            if filteredChallenges.isEmpty {
                emptyState
            } else {
                challengeList
            }
        }
        .sheet(isPresented: $isPresentingLogin) { OGSLoginView(isPresented: $isPresentingLogin) }
        .onAppear {
            if !app.ogsClient.isSubscribedToSeekgraph { app.ogsClient.subscribeToSeekgraph() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Lobby").font(.headline).foregroundColor(.white)
                Button(action: { isPresentingCreate = true }) {
                    Text("Create").font(.caption).bold().padding(.horizontal, 4)
                }.buttonStyle(.bordered).tint(.blue).disabled(!app.ogsClient.isConnected)
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
            if let rid = app.resumableGameID {
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
                Spacer()
            }
        }.padding().background(Color.black.opacity(0.1))
    }

    private var emptyState: some View {
        VStack { Spacer(); Text(app.ogsClient.isConnected ? "No challenges found." : "Connecting...").foregroundColor(.white.opacity(0.5)); Spacer() }
    }

    private var challengeList: some View {
        List {
            ForEach(filteredChallenges) { challenge in
                ChallengeRow(challenge: challenge, isMine: isChallengeMine(challenge)) {
                    if isChallengeMine(challenge) { app.ogsClient.cancelChallenge(challengeID: challenge.id) }
                    else { onJoin(challenge.id) }
                }
            }
        }
        .listStyle(.inset).scrollContentBackground(.hidden)
        .padding(.top, 1) // FIX: Prevent first item from clipping under certain headers
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
            
            if selectedSpeed != .all {
                let speed = game.speedCategory
                if selectedSpeed == .live && speed != "live" { return false }
                if selectedSpeed == .blitz && speed != "blitz" { return false }
                if selectedSpeed == .correspondence && speed != "correspondence" { return false }
            }
            return true
        }
        return filtered.sorted { a, b in
            let mineA = isChallengeMine(a)
            let mineB = isChallengeMine(b)
            if mineA && !mineB { return true }
            if !mineA && mineB { return false }
            return a.id > b.id
        }
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
        }.padding(.vertical, 6).listRowBackground(Color.clear)
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
        }
    }
    
    private var header: some View {
        HStack {
            Text("Login to OGS").font(.headline).foregroundColor(.white)
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
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
        isLoggingIn = true; errorMessage = nil
        app.ogsClient.login(username: username, password: password) { success, error in
            DispatchQueue.main.async {
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
}
