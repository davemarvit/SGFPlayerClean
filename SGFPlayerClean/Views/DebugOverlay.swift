// MARK: - File: DebugOverlay.swift (v6.401)
import SwiftUI

struct DebugOverlay: View {
    @ObservedObject var app: AppModel
    @ObservedObject var client: OGSClient
    @ObservedObject var board: BoardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("--- DIAGNOSTICS ---").font(.caption2).bold().foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text("Game ID: \(client.activeGameID?.description ?? "NIL")").foregroundColor(client.activeGameID != nil ? .green : .red)
                Text("Socket: \(client.isConnected ? "CONNECTED" : "OFFLINE")").foregroundColor(client.isConnected ? .green : .orange)
                Text("Auth: \(client.isSocketAuthenticated ? "VERIFIED" : "PENDING")").foregroundColor(client.isSocketAuthenticated ? .green : .red)
                Text("JWT: \(client.userJWT != nil ? "OK" : "MISSING")").foregroundColor(client.userJWT != nil ? .green : .red)
            }
            Divider().background(Color.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 2) {
                Text("Context: \(board.isOnlineContext ? "ONLINE" : "LOCAL")").foregroundColor(board.isOnlineContext ? .cyan : .yellow)
                // Optimized: Using the Render Cache array instead of the raw grid dictionary
                Text("Stones: \(board.stonesToRender.count)")
                Text("MoveIdx: \(board.currentMoveIndex)")
                if let last = board.lastMovePosition {
                    Text("Last: \(last.col), \(last.row)").foregroundColor(.gray)
                }
            }
            if let err = client.lastError {
                Divider().background(Color.white.opacity(0.3))
                Text("ERR: \(err)").foregroundColor(.red).lineLimit(3)
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
}
