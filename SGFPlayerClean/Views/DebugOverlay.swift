//
//  DebugOverlay.swift
//  SGFPlayerClean
//
//  Purpose: Visual verification of App State without crashing the compiler.
//

import SwiftUI

struct DebugOverlay: View {
    @ObservedObject var app: AppModel
    @ObservedObject var client: OGSClient
    @ObservedObject var board: BoardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            diagnosticsSection
            Divider().background(Color.white.opacity(0.3))
            boardSection
            if client.lastError != nil {
                Divider().background(Color.white.opacity(0.3))
                errorSection
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(8)
        .background(Color.black.opacity(0.85))
        .foregroundColor(.white)
        .cornerRadius(8)
        .frame(maxWidth: 220, alignment: .leading)
        .padding()
    }
    
    private var headerSection: some View {
        Text("--- DIAGNOSTICS ---")
            .font(.caption2)
            .bold()
            .foregroundColor(.gray)
    }
    
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            let gid = client.activeGameID?.description ?? "NIL"
            Text("Game ID: \(gid)")
                .foregroundColor(client.activeGameID != nil ? .green : .red)
            
            Text("Socket: \(client.isConnected ? "CONNECTED" : "OFFLINE")")
                .foregroundColor(client.isConnected ? .green : .orange)
            
            Text("Auth: \(client.isSocketAuthenticated ? "VERIFIED" : "PENDING")")
                .foregroundColor(client.isSocketAuthenticated ? .green : .red)
            
            Text("JWT: \(client.userJWT != nil ? "OK" : "MISSING")")
                .foregroundColor(client.userJWT != nil ? .green : .red)
        }
    }
    
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Context: \(board.isOnlineContext ? "ONLINE" : "LOCAL")")
                .foregroundColor(board.isOnlineContext ? .cyan : .yellow)
            
            Text("Stones: \(board.stones.count)")
            Text("MoveIdx: \(board.currentMoveIndex)")
            
            if let last = board.lastMovePosition {
                Text("Last: \(last.col), \(last.row)")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var errorSection: some View {
        Text("ERR: \(client.lastError ?? "Unknown")")
            .foregroundColor(.red)
            .lineLimit(3)
    }
}
