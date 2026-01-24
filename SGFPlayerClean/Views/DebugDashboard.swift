// ========================================================
// FILE: ./Views/DebugDashboard.swift
// VERSION: v3.285 (Stability & Binding Alignment)
// ========================================================

import SwiftUI

struct DebugDashboard: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var client: OGSClient
    
    init(appModel: AppModel) {
        self.appModel = appModel
        self.client = appModel.ogsClient
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Black Box (Live Traffic)").font(.headline).foregroundColor(.white)
                    Spacer()
                    Button("Copy All") {
                        #if os(macOS)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(client.blackBoxContent, forType: .string)
                        #endif
                    }.buttonStyle(.bordered).controlSize(.small)
                    Button(action: { client.blackBoxContent = "" }) {
                        Image(systemName: "trash")
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
                .padding(10).background(Color.black.opacity(0.8))
                
                TextEditor(text: $client.blackBoxContent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
            }
            .frame(minWidth: 450)
            
            Divider().background(Color.gray)
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Inspector").font(.headline).foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    DebugStateRow(label: "Connected", value: client.isConnected ? "YES" : "NO")
                    DebugStateRow(label: "Login (JWT)", value: client.userJWT != nil ? "Verified" : "Missing")
                    DebugStateRow(label: "Socket Auth", value: client.isSocketAuthenticated ? "YES" : "NO")
                    DebugStateRow(label: "Target Game ID", value: "\(client.activeGameID ?? -1)")
                    DebugStateRow(label: "My ID", value: "\(client.playerID ?? -1)")
                    DebugStateRow(label: "Black ID", value: "\(client.blackPlayerID ?? -1)")
                    DebugStateRow(label: "White ID", value: "\(client.whitePlayerID ?? -1)")
                    DebugStateRow(label: "My Color", value: client.playerColor?.rawValue.capitalized ?? "Spectator")
                }
                
                Divider().background(Color.gray)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Engine Sync").font(.subheadline).foregroundColor(.yellow)
                    DebugStateRow(label: "State Version", value: "\(client.currentStateVersion)")
                    DebugStateRow(label: "Stone Count", value: "\(appModel.player.board.stones.count)")
                    DebugStateRow(label: "Engine Turn", value: appModel.player.turn.rawValue.capitalized)
                }
                
                /*
                Button("Simulate Game Load") {
                    appModel.simulateOGSLoad()
                }
                .frame(maxWidth: .infinity).padding(8).background(Color.blue.opacity(0.6)).cornerRadius(8)
                */
                
                Spacer()
                Button("Close") { appModel.showDebugDashboard = false }
                    .frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.1)).cornerRadius(8)
            }
            .padding().frame(width: 250).background(Color(white: 0.15))
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct DebugStateRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced)).foregroundColor(.white)
        }
    }
}
