//
//  ActiveGamePanel.swift
//  SGFPlayerClean
//
//  v3.500: Logic Refresh.
//  - Ported Main-thread safe player stats display.
//  - Sync with AppModel EnvironmentObject.
//

import SwiftUI

struct ActiveGamePanel: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider().background(Color.white.opacity(0.1))
            
            if let username = app.ogsClient.undoRequestedUsername {
                VStack(spacing: 8) {
                    Text("Undo request from \(username)").font(.caption).bold()
                    HStack {
                        Button("Reject") {
                            if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoReject(gameID: id) }
                        }.tint(.red)
                        Button("Accept") {
                            if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoAccept(gameID: id) }
                        }.tint(.green)
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding().background(Color.orange.opacity(0.2)).cornerRadius(8)
            }
            
            playerInfoSection
            Spacer()
            controlsSection
        }
        .padding()
    }
    
    private var headerSection: some View {
        HStack {
            Text("Game #\(app.ogsClient.activeGameID?.description ?? "?")").font(.headline)
            Spacer()
            Button("Resign") {
                if let id = app.ogsClient.activeGameID { app.ogsClient.resignGame(gameID: id) }
            }.foregroundColor(.red)
        }
    }
    
    private var playerInfoSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(app.ogsClient.blackPlayerName ?? "Black").bold()
                Text("\(Int(app.ogsClient.blackTimeRemaining ?? 0))s").font(.title3).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(app.ogsClient.whitePlayerName ?? "White").bold()
                Text("\(Int(app.ogsClient.whiteTimeRemaining ?? 0))s").font(.title3).monospacedDigit()
            }
        }
    }
    
    private var controlsSection: some View {
        HStack {
            Button("Undo") {
                if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoRequest(gameID: id, moveNumber: app.player.currentIndex) }
            }
            Spacer()
            Button("Pass") {
                if let id = app.ogsClient.activeGameID { app.ogsClient.sendPass(gameID: id) }
            }
        }.buttonStyle(.bordered)
    }
}
