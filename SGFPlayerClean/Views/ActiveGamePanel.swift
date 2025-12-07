//
//  ActiveGamePanel.swift
//  SGFPlayerClean
//
//  Updated: Transparent background + Readable inner cards
//

import SwiftUI

struct ActiveGamePanel: View {
    @ObservedObject var client: OGSClient
    @ObservedObject var boardVM: BoardViewModel
    
    var body: some View {
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
                        captures: opponentIsWhite ? boardVM.whiteCapturedCount : boardVM.blackCapturedCount,
                        isActive: (boardVM.nextTurnColor == (opponentIsWhite ? .white : .black))
                    )
                    
                    // --- GAME STATS ---
                    HStack(spacing: 30) {
                        VStack {
                            Text("Komi")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("6.5")
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
                        captures: opponentIsWhite ? boardVM.blackCapturedCount : boardVM.whiteCapturedCount,
                        isActive: (boardVM.nextTurnColor == (opponentIsWhite ? .black : .white))
                    )
                    
                    Spacer()
                    
                    Button(action: {
                        // TODO: Resign
                    }) {
                        Text("Resign")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
        }
        // CRITICAL: Transparent to let RightPanel material show
        .background(Color.clear)
    }
}

struct PlayerCard: View {
    let name: String?
    let rank: Double?
    let color: Stone
    let time: TimeInterval?
    let periods: Int?
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
        
        let seconds = Int(t)
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
                    .background(Color.black.opacity(0.3)) // Readable on blur
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
                    Text("(\(p))")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .offset(y: 2)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3)) // Readable on blur
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
