// MARK: - File: ActiveGamePanel.swift (v3.505)
import SwiftUI

struct ActiveGamePanel: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        ZStack {
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
            .animation(.easeInOut(duration: 0.5), value: app.ogsClient.undoRequestedUsername)
            
            if app.ogsClient.isGameFinished {
                resultOverlay.transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private var resultOverlay: some View {
        VStack(spacing: 16) {
            Text("GAME OVER").font(.largeTitle).bold().foregroundColor(.white)
            if let outcome = app.ogsClient.activeGameOutcome {
                Text(outcome).font(.title2).foregroundColor(.yellow)
            }
            Button(action: { app.ogsClient.activeGameID = nil }) {
                Text("Return to Lobby").bold().padding(.horizontal, 20)
            }.buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(Material.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(radius: 20)
    }
    
    private var headerSection: some View {
        HStack {
            Button(action: {
                app.ogsClient.activeGameID = nil
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Lobby")
                }
            }

            Spacer()
            Spacer()
            // Version Indicator
            Text("v1.0.0").font(.caption2).foregroundColor(.white.opacity(0.3))
            Spacer()
            if let tc = app.ogsClient.activeGameTimeControl {
                Text(tc).font(.subheadline).foregroundColor(.secondary).padding(.horizontal)
            }
            Spacer()
            Button("Resign") {
                if let id = app.ogsClient.activeGameID { app.ogsClient.resignGame(gameID: id) }
            }.foregroundColor(.red).disabled(app.ogsClient.isGameFinished)
        }
    }
    
    private func undoApprovalSection(username: String) -> some View {
        VStack(spacing: 8) {
            Text("Undo request from \(username)").font(.caption).bold()
            Button("Accept Undo") {
                if let id = app.ogsClient.activeGameID {
                    let m = app.ogsClient.undoRequestedMoveNumber ?? app.player.maxIndex
                    app.ogsClient.sendUndoAccept(gameID: id, moveNumber: m)
                    
                    // Local Undo & Guard
                    // app.ogsClient.lastUndoneMoveNumber = m // REMOVED: Do not block re-entry of this move number!
                    NotificationCenter.default.post(name: NSNotification.Name("OGSUndoAcceptedLocal"), object: nil)
                    app.ogsClient.undoRequestedUsername = nil
                }
            }
            .tint(.green)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(8)
        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
        .padding()
        .animation(.easeInOut(duration: 0.5), value: app.ogsClient.undoRequestedUsername)
    }
    
    private var playerInfoSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let c = app.ogsClient.blackPlayerCountry { Text(ChallengeHelpers.flagEmoji(for: c)) }
                    Text(app.ogsClient.blackPlayerName ?? "Black").bold()
                    if let r = app.ogsClient.blackPlayerRank { Text("[\(ChallengeHelpers.formatRank(r))]").font(.caption).foregroundColor(.gray) }
                }
                Text("\(app.ogsClient.blackCaptures) captures").font(.caption2).foregroundColor(.secondary)
                GameClockView(
                    mainTime: app.ogsClient.blackTimeRemaining,
                    periods: app.ogsClient.blackClockPeriods,
                    periodTime: app.ogsClient.blackClockPeriodTime,
                    side: .left
                )
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    if let c = app.ogsClient.whitePlayerCountry { Text(ChallengeHelpers.flagEmoji(for: c)) }
                    Text(app.ogsClient.whitePlayerName ?? "White").bold()
                    if let r = app.ogsClient.whitePlayerRank { Text("[\(ChallengeHelpers.formatRank(r))]").font(.caption).foregroundColor(.gray) }
                }
                Text("\(app.ogsClient.whiteCaptures) captures").font(.caption2).foregroundColor(.secondary)
                GameClockView(
                    mainTime: app.ogsClient.whiteTimeRemaining,
                    periods: app.ogsClient.whiteClockPeriods,
                    periodTime: app.ogsClient.whiteClockPeriodTime,
                    side: .right
                )
            }
        }
    }
    
    private var controlsSection: some View {
        HStack {
            Button("Undo") {
                print("🖱️ [UI] Undo Button CLICKED")
                if let id = app.ogsClient.activeGameID {
                     app.ogsClient.sendUndoRequest(gameID: id, moveNumber: app.player.maxIndex)
                }
            }.disabled(app.ogsClient.isGameFinished || app.ogsClient.isRequestingUndo)
            if app.ogsClient.isRequestingUndo {
                Text("Requested...").font(.caption).foregroundColor(.orange)
            }
            Spacer()
            Button("Pass") {
                if let id = app.ogsClient.activeGameID {
                    // PILLAR: Refactored call site
                    app.ogsClient.sendPass(gameID: id)
                }
            }.disabled(app.ogsClient.isGameFinished)
        }.buttonStyle(.bordered)
    }
}

// MARK: - Game Clock View
struct GameClockView: View {
    let mainTime: Double?
    let periods: Int?
    let periodTime: Double?
    enum Side { case left, right }
    let side: Side
    
    private func fmt(_ sec: Double) -> String {
        let s = Int(sec)
        let m = s / 60
        let remS = s % 60
        return String(format: "%d:%02d", m, remS)
    }
    
    var body: some View {
        VStack(alignment: side == .left ? .leading : .trailing) {
            // Main Time
            Text(fmt(mainTime ?? 0))
                .font(.title2).monospacedDigit().bold()
            
            // Byoyomi / Periods
            if let p = periods, let pt = periodTime {
                let pStr = (p == 1) ? "SD" : "\(p)"
                Text("+ \(fmt(pt)) (\(pStr))")
                    .font(.body).monospacedDigit().foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
    }
}
