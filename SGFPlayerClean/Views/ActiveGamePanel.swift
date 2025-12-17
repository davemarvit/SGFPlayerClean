//
//  ActiveGamePanel.swift
//  SGFPlayerClean
//
//  v3.77: Restored missing PlayerCard struct.
//  - Added Debug Trigger.
//  - Updated Initialization.
//

import SwiftUI

struct ActiveGamePanel: View {
    // We now observe the full AppModel to toggle the dashboard
    @ObservedObject var appModel: AppModel
    
    // Shortcuts for cleaner code
    var client: OGSClient { appModel.ogsClient }
    var boardVM: BoardViewModel { appModel.boardVM! }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // HEADER
                HStack {
                    Text("Active Game")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Circle()
                        .fill(client.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: client.isConnected ? .green : .red, radius: 4)
                }
                .padding()
                .background(Color.black.opacity(0.1))
                
                Divider().background(Color.white.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // --- OPPONENT CARD ---
                        let opponentIsWhite = (client.playerColor == .black || client.playerColor == nil)
                        
                        PlayerCard(
                            name: opponentIsWhite ? client.whitePlayerName : client.blackPlayerName,
                            rank: opponentIsWhite ? client.whitePlayerRank : client.blackPlayerRank,
                            color: opponentIsWhite ? .white : .black,
                            time: opponentIsWhite ? client.whiteTimeRemaining : client.blackTimeRemaining,
                            periods: opponentIsWhite ? client.whitePeriodsRemaining : client.blackPeriodsRemaining,
                            periodTime: opponentIsWhite ? client.whitePeriodTime : client.blackPeriodTime,
                            captures: opponentIsWhite ? boardVM.whiteCapturedCount : boardVM.blackCapturedCount,
                            isActive: (boardVM.nextTurnColor == (opponentIsWhite ? .white : .black))
                        )
                        
                        // --- GAME STATS ---
                        HStack(spacing: 30) {
                            VStack {
                                Text("Komi")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatKomi(client.komi))
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            VStack {
                                Text("Move")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(boardVM.currentMoveIndex)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 10)
                        
                        // --- SELF CARD ---
                        PlayerCard(
                            name: opponentIsWhite ? client.blackPlayerName : client.whitePlayerName,
                            rank: opponentIsWhite ? client.blackPlayerRank : client.whitePlayerRank,
                            color: opponentIsWhite ? .black : .white,
                            time: opponentIsWhite ? client.blackTimeRemaining : client.whiteTimeRemaining,
                            periods: opponentIsWhite ? client.blackPeriodsRemaining : client.whitePeriodsRemaining,
                            periodTime: opponentIsWhite ? client.blackPeriodTime : client.whitePeriodTime,
                            captures: opponentIsWhite ? boardVM.blackCapturedCount : boardVM.whiteCapturedCount,
                            isActive: (boardVM.nextTurnColor == (opponentIsWhite ? .black : .white))
                        )
                        
                        Spacer()
                        
                        // --- CONTROLS ---
                        HStack(spacing: 12) {
                            Button(action: { boardVM.requestUndo() }) {
                                Text("Undo")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { boardVM.passTurn() }) {
                                Text("Pass")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { boardVM.resignGame() }) {
                                Text("Resign")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        
                        // --- DEBUG LINK ---
                        Button(action: { appModel.showDebugDashboard = true }) {
                            HStack {
                                Image(systemName: "ladybug")
                                Text("Network Inspector")
                            }
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            
            // --- UNDO REQUEST OVERLAY ---
            if let requester = client.undoRequestedUsername {
                Color.black.opacity(0.6)
                    .allowsHitTesting(true) // Block interaction
                
                VStack(spacing: 16) {
                    Text("\(requester) requested an undo.")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            if let id = client.activeGameID { client.sendUndoReject(gameID: id) }
                        }) {
                            Text("Reject")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            if let id = client.activeGameID { client.sendUndoAccept(gameID: id) }
                        }) {
                            Text("Accept")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .background(Material.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 20)
            }
        }
        .background(Color.clear)
    }
    
    func formatKomi(_ k: Double?) -> String {
        guard let k = k else { return "-" }
        return k.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", k) : String("\(k)")
    }
}

// MARK: - Player Card (Restored)
struct PlayerCard: View {
    let name: String?
    let rank: Double?
    let color: Stone
    let time: TimeInterval?
    let periods: Int?
    let periodTime: TimeInterval?
    let captures: Int
    let isActive: Bool
    
    func formatRank(_ r: Double?) -> String {
        guard let r = r else { return "?" }
        let ri = Int(r)
        if ri >= 30 { return "\(ri - 29)d" }
        return "\(30 - ri)k"
    }
    
    func formatTime(_ t: TimeInterval?) -> String {
        guard let t = t else { return "--:--" }
        let safeTime = max(0, t)
        let seconds = Int(safeTime)
        if seconds >= 86400 {
            let d = seconds / 86400
            let h = (seconds % 86400) / 3600
            return "\(d)d \(h)h"
        }
        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return String(format: "%02d:%02d:--", h, m)
        }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(color == .black ? Color.black : Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                
                Text(name ?? "Waiting...")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(formatRank(rank))
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if captures > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "circle.grid.cross")
                            .font(.caption2)
                        Text("\(captures)")
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            
            HStack {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundColor(isActive ? .green : .gray)
                
                Text(formatTime(time))
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? .white : .white.opacity(0.6))
                
                if let p = periods {
                    if let pt = periodTime {
                        Text("(\(p)x\(Int(pt))s)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .offset(y: 2)
                    } else {
                        Text("(\(p))")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .offset(y: 2)
                    }
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .opacity(name == nil ? 0.5 : 1.0)
    }
}
