//
//  OGSBrowserView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-29
//  Purpose: Right-hand panel for browsing OGS challenges & Account Management
//

import SwiftUI

struct OGSBrowserView: View {
    @ObservedObject var app: AppModel
    
    // UI Filters
    @AppStorage("filterLive") private var filterLive = true
    @AppStorage("filterCorrespondence") private var filterCorrespondence = false
    @AppStorage("filter19x19") private var filter19x19 = true
    @AppStorage("filter13x13") private var filter13x13 = true
    @AppStorage("filter9x9") private var filter9x9 = true
    @AppStorage("filterOther") private var filterOther = false
    
    // Login State
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var loginError: String?
    @State private var showLoginArea = false
    
    var body: some View {
        ZStack {
            if !app.isCreatingChallenge {
                VStack(spacing: 0) {
                    headerView
                    
                    Picker("Tab", selection: $app.browserTab) {
                        ForEach(OGSBrowserTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(10)
                    
                    filterGrid
                    
                    contentList
                    
                    if app.browserTab == .challenge {
                        createGameFooter
                    }
                }
                .transition(.opacity)
            } else {
                OGSCreateChallengeView(app: app, isPresented: $app.isCreatingChallenge)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .onAppear { app.ogsClient.subscribeToSeekgraph() }
        .onDisappear { app.ogsClient.unsubscribeFromSeekgraph() }
    }
    
    // MARK: - Header & Login
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
                if let err = loginError { Text(err).font(.caption2).foregroundColor(.red) }
                Button(action: performLogin) { Text("Log In").frame(maxWidth: .infinity).padding(.vertical, 6).background(Color.blue).cornerRadius(4) }
                .buttonStyle(.plain).disabled(isLoggingIn || username.isEmpty)
            }
        }
        .padding(.horizontal).padding(.bottom, 10)
    }
    
    private func performLogin() {
        isLoggingIn = true; loginError = nil
        app.ogsClient.authenticate(username: username, password: password) { success, error in
            isLoggingIn = false
            if success { password = "" } else { loginError = error ?? "Login failed" }
        }
    }
    
    private func rankString(_ rank: Double) -> String {
        if rank < 30 { return "\(30 - Int(rank))k" }
        else { return "\(Int(rank) - 29)d" }
    }
    
    // MARK: - Filter Grid
    private var filterGrid: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Size:").font(.caption).foregroundColor(.gray)
                Toggle("19x", isOn: $filter19x19).toggleStyle(CheckboxToggleStyle())
                Toggle("13x", isOn: $filter13x13).toggleStyle(CheckboxToggleStyle())
                Toggle("9x", isOn: $filter9x9).toggleStyle(CheckboxToggleStyle())
                Toggle("Other", isOn: $filterOther).toggleStyle(CheckboxToggleStyle())
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
    
    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredGames) { challenge in
                    // ChallengeRow is defined at bottom of file
                    ChallengeRow(challenge: challenge, isWatchMode: app.browserTab == .watch) {
                        app.joinOnlineGame(id: challenge.id)
                    }
                }
            }
            .padding(10)
        }
    }
    
    private var createGameFooter: some View {
        VStack {
            Divider().background(Color.white.opacity(0.1))
            Button(action: { withAnimation { app.isCreatingChallenge = true } }) {
                Text("Create Challenge").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.green.opacity(0.6)).foregroundColor(.white).cornerRadius(6)
            }
            .buttonStyle(.plain).padding()
        }
    }
    
    private var filteredGames: [OGSChallenge] {
        return app.ogsClient.availableGames.filter { challenge in
            let isValid = !challenge.game.blackLost && !challenge.game.whiteLost && !challenge.game.annulled
            guard isValid else { return false }
            
            let isStarted = challenge.game.started != nil
            if app.browserTab == .challenge && isStarted { return false }
            if app.browserTab == .watch && !isStarted { return false }
            
            let speed = challenge.speedCategory
            let isCorr = speed == "correspondence"
            let isLive = speed == "live" || speed == "blitz" || speed == "rapid"
            
            var showSpeed = false
            if filterLive && isLive { showSpeed = true }
            if filterCorrespondence && isCorr { showSpeed = true }
            if !showSpeed { return false }
            
            let w = challenge.game.width
            let isStandard = [9, 13, 19].contains(w)
            var showSize = false
            if filter19x19 && w == 19 { showSize = true }
            if filter13x13 && w == 13 { showSize = true }
            if filter9x9 && w == 9 { showSize = true }
            if filterOther && !isStandard { showSize = true }
            if !showSize { return false }
            
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
                configuration.label
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(4)
            .background(Color.white.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// Explicitly defined here to be in scope
struct ChallengeRow: View {
    let challenge: OGSChallenge
    let isWatchMode: Bool
    let onAccept: () -> Void
    
    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text(challenge.challenger.displayRank)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if isWatchMode {
                    Text(challenge.game.name ?? "Live Game")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Text("\(challenge.challenger.username)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Text(challenge.boardSize).foregroundColor(.gray)
                    Text("•").foregroundColor(.gray)
                    Image(systemName: "clock").font(.system(size: 8)).foregroundColor(.cyan)
                    Text(challenge.timeControlDisplay).foregroundColor(.cyan)
                }
                .font(.system(size: 10))
            }
            
            Spacer()
            
            Button(action: onAccept) {
                Image(systemName: isWatchMode ? "eye.fill" : "play.fill")
                    .font(.system(size: 10))
                    .padding(8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
