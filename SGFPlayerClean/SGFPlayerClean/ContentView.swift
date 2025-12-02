//
//  ContentView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Main view switcher between 2D and 3D modes
//

import SwiftUI

struct ContentView: View {
    // This is the source of truth for the entire app state
    @StateObject private var app = AppModel()

    var body: some View {
        Group {
            switch app.viewMode {
            case .view2D:
                ContentView2D(app: app)
            case .view3D:
                ContentView3D(app: app)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

#Preview {
    ContentView()
}
