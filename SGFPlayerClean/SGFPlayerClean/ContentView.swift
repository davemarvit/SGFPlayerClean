//
//  ContentView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Updated: 2025-12-11
//  Purpose: Root container switching between 2D and 3D views.
//  - Matches restored signatures: ContentView2D(app:), ContentView3D(app:)
//  - v3.25: Moved Debug Monitor to Bottom-Left to avoid blocking buttons.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppModel()
    
    var body: some View {
        ZStack(alignment: .bottomLeading) { // CHANGED: .bottomLeading
            // MARK: - Main Interface
            Group {
                // Ensure BoardVM is ready before loading views
                if app.boardVM != nil {
                    switch app.viewMode {
                    case .view2D:
                        ContentView2D(app: app)
                    case .view3D:
                        ContentView3D(app: app)
                    }
                } else {
                    LoadingView()
                }
            }
            .frame(minWidth: 1000, minHeight: 700)
            
            // MARK: - Diagnostic Overlay (Debug Only)
            // Use this to verify why Handicap/Ghost stones are missing
            VStack(alignment: .leading, spacing: 4) {
                Text("DEBUG MONITOR").font(.caption2).bold()
                
                // 1. Connection
                HStack {
                    Text("Socket:")
                    Text(app.ogsClient.isConnected ? "🟢 Connected" : "🔴 Disconnected")
                }
                
                // 2. Auth
                HStack {
                    Text("Auth:")
                    if app.ogsClient.isAuthenticated {
                        Text("✅ \(app.ogsClient.username ?? "User")")
                    } else {
                        Text("❌ Guest")
                    }
                }
                
                // 3. Game State
                HStack {
                    Text("GameID:")
                    Text(app.ogsClient.activeGameID.map { String($0) } ?? "None")
                }
                
                // 4. Turn Logic (The "Ghost Stone" blocker)
                HStack {
                    Text("Turn:")
                    if let vm = app.boardVM {
                        Text(vm.isMyTurn ? "🟢 MINE" : "🔴 OPPONENT")
                            .foregroundColor(vm.isMyTurn ? .green : .red)
                    } else {
                        Text("--")
                    }
                }
                
                // 5. Board State (The "Handicap" blocker)
                HStack {
                    Text("Stones:")
                    Text("\(app.boardVM?.stones.count ?? 0)")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(8)
            .background(Color.black.opacity(0.85))
            .foregroundColor(.white)
            .cornerRadius(6)
            .padding()
            .allowsHitTesting(false) // Clicks pass through to board
        }
    }
}
