//
//  DebugDashboard.swift
//  SGFPlayerClean
//
//  A comprehensive debug view for OGS traffic and state inspection.
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
                ScrollViewReader { proxy in
                    List {
                        ForEach(appModel.ogsClient.trafficLogs) { entry in
                            if showHeartbeats || !entry.isHeartbeat {
                                LogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.black.opacity(0.9))
                    .onChange(of: appModel.ogsClient.trafficLogs.count) { _ in
                        if let first = appModel.ogsClient.trafficLogs.first {
                            // proxy.scrollTo(first.id, anchor: .top) // Auto-scroll if desired
                        }
                    }
                }
            }
            .frame(minWidth: 350)
            
            Divider().background(Color.gray)
            
            // RIGHT PANEL: State Inspector
            VStack(alignment: .leading, spacing: 20) {
                Text("State Inspector")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                // Game Info
                Group {
                    StateRow(label: "Game ID", value: "\(appModel.ogsClient.activeGameID ?? -1)")
                    StateRow(label: "Auth", value: appModel.ogsClient.activeGameAuth == nil ? "Missing" : "OK")
                    StateRow(label: "Player ID", value: "\(appModel.ogsClient.playerID ?? -1)")
                    StateRow(label: "My Color", value: appModel.ogsClient.playerColor == .black ? "Black" : (appModel.ogsClient.playerColor == .white ? "White" : "Spectator"))
                }
                
                Divider().background(Color.gray)
                
                // Move Counters (The critical test for Undo)
                Group {
                    Text("Sync Status")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                    
                    if let boardVM = appModel.boardVM {
                        StateRow(label: "Local Move Index", value: "\(boardVM.currentMoveIndex)")
                        StateRow(label: "Processing Move", value: boardVM.isProcessingMove ? "YES" : "NO")
                        StateRow(label: "Last Remote Color", value: boardVM.nextTurnColor == .black ? "White" : "Black") // Inferred
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
