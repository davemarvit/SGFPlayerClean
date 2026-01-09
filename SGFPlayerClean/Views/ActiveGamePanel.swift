// MARK: - File: ActiveGamePanel.swift (v3.505)
import SwiftUI

struct ActiveGamePanel: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider().background(Color.white.opacity(0.1))
            
            if let username = app.ogsClient.undoRequestedUsername {
                undoApprovalSection(username: username)
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
    
    private func undoApprovalSection(username: String) -> some View {
        VStack(spacing: 8) {
            Text("Undo request from \(username)").font(.caption).bold()
            HStack {
                Button("Reject") {
                    if let id = app.ogsClient.activeGameID { app.ogsClient.sendUndoReject(gameID: id) }
                }.tint(.red)
                Button("Accept") {
                    if let id = app.ogsClient.activeGameID {
                        let m = app.ogsClient.undoRequestedMoveNumber ?? app.player.serverMoveNumber
                        app.ogsClient.sendUndoAccept(gameID: id, moveNumber: m)
                    }
                }.tint(.green)
            }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding().background(Color.orange.opacity(0.2)).cornerRadius(8)
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
                if let id = app.ogsClient.activeGameID {
                    app.ogsClient.sendUndoRequest(gameID: id, moveNumber: app.player.serverMoveNumber)
                }
            }
            Spacer()
            Button("Pass") {
                if let id = app.ogsClient.activeGameID {
                    // PILLAR: Refactored call site
                    app.ogsClient.sendPass(gameID: id)
                }
            }
        }.buttonStyle(.bordered)
    }
}
