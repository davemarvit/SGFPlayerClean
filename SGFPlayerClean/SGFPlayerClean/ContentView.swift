//
//  ContentView.swift
//  SGFPlayerClean
//
//  v3.75: Root Container (Fixes Argument Labels)
//  - Removed redundant 'Group' that was causing type inference issues.
//  - Wraps the 2D/3D views.
//  - Manages the DebugDashboard presentation.
//  - Global Keyboard Shortcuts (Cmd+D for Debug).
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject var appModel = AppModel()

    var body: some View {
        ZStack {
            // MAIN CONTENT
            // We removed the 'Group' here to avoid compiler ambiguity with TabContentBuilder
            if appModel.viewMode == .view3D {
                ContentView3D(app: appModel)
            } else {
                // FIX: Use 'app:' label here as well
                ContentView2D(app: appModel)
            }
            
            // PRE-GAME OVERLAY (If applicable)
            if appModel.showPreGameOverlay {
                Color.black.opacity(0.4).ignoresSafeArea()
                // You can insert a specific OverlayView here if you have one
            }
        }
        // GLOBAL MODIFIERS
        .environmentObject(appModel)
        .preferredColorScheme(.dark)
        
        // DEBUG DASHBOARD SHEET
        .sheet(isPresented: $appModel.showDebugDashboard) {
            DebugDashboard(appModel: appModel)
                .frame(minWidth: 700, minHeight: 500)
        }
        
        // KEYBOARD SHORTCUTS
        .background(
            Button("Toggle Debug") {
                appModel.showDebugDashboard.toggle()
            }
            .keyboardShortcut("d", modifiers: .command)
            .opacity(0) // Hidden button to capture the shortcut
        )
    }
}
