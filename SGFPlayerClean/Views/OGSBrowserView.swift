//
//  OGSBrowserView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-29
//  Updated: 2025-12-04 (Redesigned Row for Detail)
//

import SwiftUI

struct OGSBrowserView: View {
    @ObservedObject var app: AppModel
    
    // UI Filters
    @AppStorage("filter19x19") private var filter19x19 = true
    @AppStorage("filter13x13") private var filter13x13 = true
    @AppStorage("filter9x9") private var filter9x9 = true
    @AppStorage("filterLive") private var filterLive = true
    @AppStorage("filterCorrespondence") private var filterCorrespondence = false
    
    // Login State
    @State private var showLoginArea = false
    @State private var username = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            if !app.isCreatingChallenge {
                VStack(spacing: 0) {
                    headerView
                    
                    Picker("Tab", selection: $app.browserTab) {
                        Text("Play").tag(OGSBrowserTab.challenge)
                        Text("Watch").tag(OGSBrowserTab.watch)
                    }
                    .pickerStyle(.segmented)
                    .padding(10)
                    
                    filterGrid
                    
                    contentList
                    
                    if app.browserTab == .challenge {
                        createGameFooter
                    }
                }
            } else {
                OGSCreateChallengeView(app: app, isPresented: $app.isCreatingChallenge)
            }
        }
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .onAppear { app.ogsClient.subscribeToSeekgraph() }
        .onDisappear { app.ogsClient.unsubscribeFromSeekgraph() }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(app.ogsClient.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(app.ogsClient.isConnected ? "Connected" : "Disconnected").font(.caption).foregroundColor(.gray)
                Spacer()
                Button(action: { withAnimation { showLoginArea.toggle() }}) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle")
                        Text(app.ogsClient.isAuthenticated ? (app.ogsClient.username ?? "User") : "Log In")
                    }
                    .font(.caption).padding(4).background(Color.white.opacity(0.1)).cornerRadius(4)
                }.buttonStyle(.plain)
                
                Button(action: { app.ogsClient.subscribeToSeekgraph(force: true) }) {
                    Image(systemName: "arrow.clockwise").foregroundColor(.white.opacity(0.7))
                }.buttonStyle(.plain).padding(.leading, 8)
            }
            .padding()
            
            if showLoginArea { loginArea }
        }
        .background(Color.white.opacity(0.05))
    }
    
    private var loginArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.ogsClient.isAuthenticated {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Signed in as").font(.caption).foregroundColor(.gray)
                        Text(app.ogsClient.username ?? "Unknown").font(.headline).foregroundColor(.white)
                        if let rank = app.ogsClient.userRank {
                            Text(rankString(rank)).font(.caption2).foregroundColor(.cyan)
                        }
                    }
                    Spacer()
                    Button("Log Out") {
                        app.ogsClient.deleteCredentials(); app.ogsClient.disconnect()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.ogsClient.connect() }
                    }
                    .font(.caption).padding(6).background(Color.red.opacity(0.6)).cornerRadius(4).buttonStyle(.plain)
                }
            } else {
                TextField("Username", text: $username).textFieldStyle(.plain).padding(6).background(Color.white.opacity(0.1)).cornerRadius(4)
                SecureField("Password", text: $password).textFieldStyle(.plain).padding(6).background(Color.white.opacity(0.1)).cornerRadius(4)
                Button(action: performLogin) { Text("Log In").frame(maxWidth: .infinity).padding(.vertical, 6).background(Color.blue).cornerRadius(4) }
                .buttonStyle(.plain).disabled(username.isEmpty)
            }
        }
        .padding(.horizontal).padding(.bottom, 10)
    }
    
    private func performLogin() {
        app.ogsClient.authenticate(username: username, password: password) { success, _ in
            if success { password = ""; showLoginArea = false }
        }
    }
    
    private func rankString(_ rank: Double) -> String {
        if rank < 30 { return "\(30 - Int(rank))k" }
        else { return "\(Int(rank) - 29)d" }
    }
    
    // MARK: - Filters
    private var filterGrid: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Size:").font(.caption).foregroundColor(.gray)
                Toggle("19x", isOn: $filter19x19).toggleStyle(CheckboxToggleStyle())
                Toggle("13x", isOn: $filter13x13).toggleStyle(CheckboxToggleStyle())
                Toggle("9x", isOn: $filter9x9).toggleStyle(CheckboxToggleStyle())
                Spacer()
            }
            HStack {
                Text("Time:").font(.caption).foregroundColor(.gray)
                Toggle("Live", isOn: $filterLive).toggleStyle(CheckboxToggleStyle())
                Toggle("Corresp.", isOn: $filterCorrespondence).toggleStyle(CheckboxToggleStyle())
                Spacer()
            }
        }
        .padding(10).background(Color.black.opacity(0.2))
    }
    
    // MARK: - Content
    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let games = filteredGames
                if games.isEmpty {
                    Text("No games found").foregroundColor(.gray).padding()
                } else {
                    ForEach(games) { challenge in
                        ChallengeRow(challenge: challenge, isWatchMode: app.browserTab == .watch) {
                            app.joinOnlineGame(id: challenge.id)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
    
    private var createGameFooter: some View {
        VStack {
            Divider().background(Color.white.opacity(0.1))
            HStack {
                Button(action: { app.ogsGame?.findMatch() }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Quick Play")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.blue.opacity(0.6))
                    .foregroundColor(.white).cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: { withAnimation { app.isCreatingChallenge = true } }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Custom")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.green.opacity(0.6))
                    .foregroundColor(.white).cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }
    
    // MARK: - Logic
    private var filteredGames: [OGSChallenge] {
        return app.ogsClient.availableGames.filter { challenge in
            // 1. Tab Filter
            let isStarted = challenge.game.started != nil
            if app.browserTab == .challenge && isStarted { return false }
            if app.browserTab == .watch && !isStarted { return false }
            
            // 2. Size Filter
            let w = challenge.game.width
            if !filter19x19 && w == 19 { return false }
            if !filter13x13 && w == 13 { return false }
            if !filter9x9 && w == 9 { return false }
            
            // 3. Speed Filter
            let tc = challenge.game.timeControl?.lowercased() ?? ""
            if !filterLive && (tc != "correspondence") { return false }
            if !filterCorrespondence && (tc == "correspondence") { return false }
            
            return true
        }
    }
}

// MARK: - Components

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .blue : .gray)
                configuration.label.font(.caption).foregroundColor(.white)
            }
            .padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ChallengeRow: View {
    let challenge: OGSChallenge
    let isWatchMode: Bool
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            
            // COLUMN 1: Player/Game Name
            HStack(spacing: 6) {
                // Rank Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.3)) // Dark Slate Blue
                        .frame(width: 32, height: 18)
                    Text(challenge.challenger.displayRank)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Name
                Text(isWatchMode ? (challenge.game.name ?? "Live Game") : challenge.challenger.username)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white) // Blue-ish link color like OGS
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)
            
            // COLUMN 2: Size
            Text(challenge.boardSize)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 40, alignment: .leading)
            
            // COLUMN 3: Time
            Text(challenge.timeControlDisplay) // Now contains "1m+5x 10s"
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 110, alignment: .leading)
            
            // COLUMN 4: Ranked
            Text(challenge.game.ranked ? "Yes" : "No")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30, alignment: .leading)
            
            // COLUMN 5: Rules (Hidden on small screens if needed, but useful)
            Text(challenge.game.rules.capitalized)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .frame(minWidth: 50, alignment: .leading)

            Spacer()
            
            // BUTTON: Accept
            Button(action: onAccept) {
                Text(isWatchMode ? "Watch" : "Accept")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(isWatchMode ? Color.blue : Color(red: 0.2, green: 0.7, blue: 0.2)) // OGS Green
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(4)
    }
}
