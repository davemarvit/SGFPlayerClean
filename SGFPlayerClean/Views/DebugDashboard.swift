// MARK: - File: DebugDashboard.swift (v3.260)
//
//  A comprehensive debug view for OGS traffic and state inspection.
//  Updated to harmonize with BoardViewModel v3.250.
//

import SwiftUI

struct DebugDashboard: View {
    @ObservedObject var appModel: AppModel
    @State private var showHeartbeats: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL: Traffic Logs
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Traffic Inspector")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Toggle("Beat", isOn: $showHeartbeats)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.mini)
                        .labelsHidden()
                    Text("❤️").font(.caption2).foregroundColor(.gray)
                    
                    Button(action: { appModel.ogsClient.trafficLogs.removeAll() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
                .padding(10)
                .background(Color.black.opacity(0.8))
                
                // Log List
                List {
                    ForEach(appModel.ogsClient.trafficLogs) { entry in
                        if showHeartbeats || !entry.isHeartbeat {
                            LogRow(entry: entry)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.black.opacity(0.9))
            }
            .frame(minWidth: 350)
            
            Divider().background(Color.gray)
            
            // RIGHT PANEL: State Inspector
            VStack(alignment: .leading, spacing: 20) {
                Text("State Inspector")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                // Connection & Auth Info
                VStack(alignment: .leading, spacing: 8) {
                    StateRow(label: "Connected", value: appModel.ogsClient.isConnected ? "YES" : "NO")
                    StateRow(label: "Socket Auth", value: appModel.ogsClient.isSocketAuthenticated ? "YES" : "NO")
                    StateRow(label: "Game ID", value: "\(appModel.ogsClient.activeGameID ?? -1)")
                    StateRow(label: "Auth Token", value: appModel.ogsClient.activeGameAuth == nil ? "Missing" : "OK")
                    StateRow(label: "Player ID", value: "\(appModel.ogsClient.playerID ?? -1)")
                }
                
                Divider().background(Color.gray)
                
                // Sync Status (Engine State)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Status")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                    
                    if let boardVM = appModel.boardVM {
                        StateRow(label: "Move Index", value: "\(boardVM.currentMoveIndex)")
                        StateRow(label: "Total Moves", value: "\(boardVM.totalMoves)")
                        StateRow(label: "Next Turn", value: appModel.player.turn == .black ? "Black" : "White")
                        StateRow(label: "My Color", value: appModel.ogsClient.playerColor == .black ? "Black" : (appModel.ogsClient.playerColor == .white ? "White" : "Spectator"))
                    } else {
                        Text("Board VM Not Active").foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                Button("Close") {
                    appModel.showDebugDashboard = false
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .frame(width: 250)
            .background(Color(white: 0.15))
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct LogRow: View {
    let entry: NetworkLogEntry
    
    var color: Color {
        if entry.direction == "⬆️" { return Color.blue }
        if entry.direction == "⚡️" { return Color.yellow }
        if entry.direction == "⚠️" { return Color.red }
        return Color.green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.direction)
                Text(entry.timestamp, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
            }
            
            Text(entry.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}

struct StateRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}
